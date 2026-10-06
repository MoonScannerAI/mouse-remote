import Foundation
import CoreBluetooth

enum ConnectionState: Equatable {
    case off
    case scanning
    case connecting
    case pairingNeeded
    case connected

    var title: String {
        switch self {
        case .off: return "Bluetooth Off"
        case .scanning: return "Searching"
        case .connecting: return "Connecting"
        case .pairingNeeded: return "Pairing Needed"
        case .connected: return "Connected"
        }
    }
}

/// CoreBluetooth central that talks to the MouseRemote dongle (see docs/PROTOCOL.md).
/// All CoreBluetooth callbacks are delivered on the main queue.
@MainActor
final class BLEManager: NSObject, ObservableObject {
    @Published private(set) var state: ConnectionState = .off
    @Published private(set) var detail: String = "Starting Bluetooth…"

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?

    private var authenticated = false
    private var denied = false

    // Outgoing data. Discrete packets are queued in order; motion is coalesced.
    private var queue: [Data] = []
    private var pendingDX = 0
    private var pendingDY = 0
    private var pendingScrollV = 0
    private var pendingScrollH = 0
    private var buttonMask: UInt8 = 0

    private var pingTimer: Timer?
    private var flushTimer: Timer?
    private var authTimer: Timer?
    private var reconnectTimer: Timer?

    private static let peripheralIDKey = "dongle.peripheralIdentifier"
    private static let flushInterval: TimeInterval = 1.0 / 120.0
    private static let maxQueuedPackets = 512

    var isConnected: Bool { authenticated }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public input API

    func move(dx: Int, dy: Int) {
        guard authenticated, dx != 0 || dy != 0 else { return }
        pendingDX += dx
        pendingDY += dy
    }

    func scroll(vertical: Int, horizontal: Int) {
        guard authenticated, vertical != 0 || horizontal != 0 else { return }
        pendingScrollV += vertical
        pendingScrollH += horizontal
    }

    func setButton(_ button: MouseButton, down: Bool) {
        guard authenticated else { return }
        let newMask = down ? (buttonMask | button.rawValue) : (buttonMask & ~button.rawValue)
        guard newMask != buttonMask else { return }
        buttonMask = newMask
        enqueue(Packet.buttons(newMask))
    }

    func click(_ button: MouseButton) {
        setButton(button, down: false)
        setButton(button, down: true)
        setButton(button, down: false)
    }

    func keyTap(modifiers: UInt8, key: UInt8) {
        enqueue(Packet.keyTap(modifiers: modifiers, key: key))
    }

    func keySet(modifiers: UInt8, key: UInt8, down: Bool) {
        enqueue(Packet.keySet(modifiers: modifiers, key: key, down: down))
    }

    func consumer(_ usage: UInt16) {
        enqueue(Packet.consumer(usage))
    }

    func releaseAll() {
        guard authenticated else { return }
        buttonMask = 0
        enqueue(Packet.releaseAll)
    }

    // MARK: - Lifecycle hooks

    func appDidBecomeActive() {
        guard central.state == .poweredOn else { return }
        startConnecting()
    }

    func appDidEnterBackground() {
        releaseAll()
    }

    /// Clears the remembered peripheral and the Keychain token, then searches again.
    func forgetDongle() {
        let old = peripheral
        resetSession()
        peripheral = nil
        denied = false
        UserDefaults.standard.removeObject(forKey: Self.peripheralIDKey)
        TokenStore.delete()
        if let old {
            old.delegate = nil
            central.cancelPeripheralConnection(old)
        }
        if central.isScanning { central.stopScan() }
        if central.state == .poweredOn {
            startConnecting()
        }
    }

    // MARK: - Connection management

    private func startConnecting() {
        guard central.state == .poweredOn else { return }
        reconnectTimer?.invalidate()
        reconnectTimer = nil

        if let p = peripheral {
            if p.state == .connected || p.state == .connecting { return }
            connect(p)
            return
        }

        if let idString = UserDefaults.standard.string(forKey: Self.peripheralIDKey),
           let id = UUID(uuidString: idString),
           let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            connect(known)
            return
        }

        if let alreadyConnected = central.retrieveConnectedPeripherals(withServices: [BLEProtocol.serviceUUID]).first {
            connect(alreadyConnected)
            return
        }

        if !central.isScanning {
            central.scanForPeripherals(withServices: [BLEProtocol.serviceUUID], options: nil)
        }
        setState(.scanning, "Looking for the MouseRemote dongle…")
    }

    private func connect(_ p: CBPeripheral) {
        if central.isScanning { central.stopScan() }
        peripheral = p
        p.delegate = self
        if denied {
            setState(.pairingNeeded, "Press the dongle button to pair")
        } else {
            setState(.connecting, "Connecting to dongle…")
        }
        central.connect(p, options: nil)
    }

    private func scheduleReconnect(after delay: TimeInterval) {
        reconnectTimer?.invalidate()
        reconnectTimer = makeTimer(interval: delay, repeats: false, selector: #selector(reconnectFired))
    }

    @objc private func reconnectFired() {
        reconnectTimer = nil
        startConnecting()
    }

    private func setState(_ newState: ConnectionState, _ newDetail: String) {
        if state != newState { state = newState }
        if detail != newDetail { detail = newDetail }
    }

    /// Drops all per-connection state. Does not touch `peripheral`.
    private func resetSession() {
        pingTimer?.invalidate(); pingTimer = nil
        flushTimer?.invalidate(); flushTimer = nil
        authTimer?.invalidate(); authTimer = nil
        authenticated = false
        rxCharacteristic = nil
        txCharacteristic = nil
        queue.removeAll()
        pendingDX = 0; pendingDY = 0
        pendingScrollV = 0; pendingScrollH = 0
        buttonMask = 0
    }

    private func makeTimer(interval: TimeInterval, repeats: Bool, selector: Selector) -> Timer {
        let timer = Timer(timeInterval: interval, target: self, selector: selector, userInfo: nil, repeats: repeats)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    // MARK: - Authentication

    private func sendAuth() {
        guard let p = peripheral, let rx = rxCharacteristic else { return }
        setState(denied ? .pairingNeeded : .connecting, denied ? "Press the dongle button to pair" : "Authenticating…")
        // AUTH must be the first packet of every connection, so it bypasses the queue.
        p.writeValue(Packet.auth(token: TokenStore.load()), for: rx, type: .withoutResponse)
        authTimer?.invalidate()
        authTimer = makeTimer(interval: 4.0, repeats: false, selector: #selector(authTimedOut))
    }

    @objc private func authTimedOut() {
        authTimer = nil
        guard !authenticated, let p = peripheral else { return }
        detail = "No reply from dongle, retrying…"
        central.cancelPeripheralConnection(p)
    }

    private func handleAuthReply(_ data: Data) {
        guard let code = data.first, let reply = AuthReply(rawValue: code) else { return }
        switch reply {
        case .ok:
            authSucceeded()
        case .newToken:
            let token = Data(data.dropFirst().prefix(BLEProtocol.tokenLength))
            guard token.count == BLEProtocol.tokenLength else { return }
            TokenStore.save(token)
            authSucceeded()
        case .denied:
            authTimer?.invalidate(); authTimer = nil
            authenticated = false
            denied = true
            setState(.pairingNeeded, "Press the dongle button to pair")
        }
    }

    private func authSucceeded() {
        authTimer?.invalidate(); authTimer = nil
        authenticated = true
        denied = false
        queue.removeAll()
        buttonMask = 0
        setState(.connected, peripheral?.name ?? "MouseRemote")
        pingTimer?.invalidate()
        pingTimer = makeTimer(interval: BLEProtocol.pingInterval, repeats: true, selector: #selector(pingTick))
        flushTimer?.invalidate()
        flushTimer = makeTimer(interval: Self.flushInterval, repeats: true, selector: #selector(flushTick))
    }

    // MARK: - Sending

    private func enqueue(_ packet: Data) {
        guard authenticated else { return }
        // Keep ordering: motion that happened before this packet goes first.
        flushMotionIntoQueue()
        if queue.count < Self.maxQueuedPackets {
            queue.append(packet)
        }
        pump()
    }

    private func flushMotionIntoQueue() {
        if pendingDX != 0 || pendingDY != 0 {
            let dx = max(Int(Int16.min), min(Int(Int16.max), pendingDX))
            let dy = max(Int(Int16.min), min(Int(Int16.max), pendingDY))
            queue.append(Packet.move(dx: Int16(dx), dy: Int16(dy)))
            pendingDX -= dx
            pendingDY -= dy
        }
        if pendingScrollV != 0 || pendingScrollH != 0 {
            let v = max(-127, min(127, pendingScrollV))
            let h = max(-127, min(127, pendingScrollH))
            queue.append(Packet.scroll(vertical: Int8(v), horizontal: Int8(h)))
            pendingScrollV -= v
            pendingScrollH -= h
        }
    }

    @objc private func flushTick() {
        guard authenticated else { return }
        // Under back-pressure, keep coalescing motion instead of queueing stale moves.
        if queue.isEmpty {
            flushMotionIntoQueue()
        }
        pump()
    }

    @objc private func pingTick() {
        guard authenticated else { return }
        if queue.count < Self.maxQueuedPackets {
            queue.append(Packet.ping)
        }
        pump()
    }

    /// Writes as many queued packets as the link accepts, batching several per write.
    private func pump() {
        guard authenticated, let p = peripheral, let rx = rxCharacteristic, p.state == .connected else { return }
        let maxLength = max(20, p.maximumWriteValueLength(for: .withoutResponse))
        while !queue.isEmpty && p.canSendWriteWithoutResponse {
            var batch = Data()
            while let next = queue.first, batch.count + next.count <= maxLength {
                batch.append(next)
                queue.removeFirst()
            }
            if batch.isEmpty {
                // Cannot happen with v1 packet sizes (max 17 bytes), but never stall.
                batch = queue.removeFirst()
            }
            p.writeValue(batch, for: rx, type: .withoutResponse)
        }
    }

    // MARK: - Delegate handlers (main actor)

    private func handleCentralState() {
        switch central.state {
        case .poweredOn:
            startConnecting()
        case .poweredOff:
            resetSession()
            peripheral = nil
            setState(.off, "Bluetooth is turned off")
        case .unauthorized:
            resetSession()
            peripheral = nil
            setState(.off, "Allow Bluetooth access in Settings")
        case .unsupported:
            setState(.off, "Bluetooth LE is not supported")
        default:
            resetSession()
            peripheral = nil
            setState(.off, "Bluetooth unavailable")
        }
    }

    private func handleDiscover(_ p: CBPeripheral) {
        guard peripheral == nil else { return }
        connect(p)
    }

    private func handleConnect(_ p: CBPeripheral) {
        guard p === peripheral else { return }
        UserDefaults.standard.set(p.identifier.uuidString, forKey: Self.peripheralIDKey)
        if !denied { detail = "Securing connection…" }
        p.discoverServices([BLEProtocol.serviceUUID])
    }

    private func handleDisconnect(_ p: CBPeripheral, error: Error?) {
        guard p === peripheral else { return }
        resetSession()
        if denied {
            setState(.pairingNeeded, "Press the dongle button to pair")
        } else {
            setState(.connecting, "Reconnecting…")
        }
        scheduleReconnect(after: denied ? 1.5 : 0.5)
    }

    private func handleServices(_ p: CBPeripheral, error: Error?) {
        guard p === peripheral else { return }
        guard error == nil,
              let service = p.services?.first(where: { $0.uuid == BLEProtocol.serviceUUID }) else {
            central.cancelPeripheralConnection(p)
            return
        }
        p.discoverCharacteristics([BLEProtocol.rxUUID, BLEProtocol.txUUID], for: service)
    }

    private func handleCharacteristics(_ p: CBPeripheral, service: CBService, error: Error?) {
        guard p === peripheral else { return }
        let characteristics = service.characteristics ?? []
        rxCharacteristic = characteristics.first(where: { $0.uuid == BLEProtocol.rxUUID })
        txCharacteristic = characteristics.first(where: { $0.uuid == BLEProtocol.txUUID })
        guard error == nil, rxCharacteristic != nil, let tx = txCharacteristic else {
            central.cancelPeripheralConnection(p)
            return
        }
        // TX is encrypted, so subscribing triggers iOS system pairing on first use.
        p.setNotifyValue(true, for: tx)
    }

    private func handleNotificationState(_ p: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        guard p === peripheral, characteristic.uuid == BLEProtocol.txUUID else { return }
        if let error {
            detail = "Pairing failed (\(error.localizedDescription)). If the dongle was reset, forget it in iOS Settings › Bluetooth."
            central.cancelPeripheralConnection(p)
            return
        }
        if characteristic.isNotifying {
            sendAuth()
        }
    }

    private func handleValue(_ p: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        guard p === peripheral, characteristic.uuid == BLEProtocol.txUUID,
              error == nil, let data = characteristic.value else { return }
        handleAuthReply(data)
    }

    private func handleReadyToSend(_ p: CBPeripheral) {
        guard p === peripheral else { return }
        pump()
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            self.handleCentralState()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            self.handleDiscover(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            self.handleConnect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            self.handleDisconnect(peripheral, error: error)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            self.handleDisconnect(peripheral, error: error)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            self.handleServices(peripheral, error: error)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        MainActor.assumeIsolated {
            self.handleCharacteristics(peripheral, service: service, error: error)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                error: Error?) {
        MainActor.assumeIsolated {
            self.handleNotificationState(peripheral, characteristic: characteristic, error: error)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        MainActor.assumeIsolated {
            self.handleValue(peripheral, characteristic: characteristic, error: error)
        }
    }

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            self.handleReadyToSend(peripheral)
        }
    }
}
