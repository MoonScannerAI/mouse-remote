# boot.py -- runs once at power-up, before USB is set up.
#
# Sets up USB as keyboard + mouse (with horizontal pan) + consumer control,
# and hides the CIRCUITPY drive and serial console in normal use.
#
# ESCAPE HATCH (read this before copying the files!)
# The dongle's only button is wired to P0.18, which CircuitPython permanently
# configures as the chip's hardware RESET pin (CONFIG_GPIO_AS_PINRESET in the
# nordic port). Code can never read it, so "hold the button at boot" cannot be
# detected here. Instead use CircuitPython SAFE MODE, which skips this file
# entirely and therefore leaves the drive and console enabled:
#   press the button once, then press it again while the LED blinks YELLOW
#   (the ~1 s window right after start-up).
# Pressing twice quickly (within 0.5 s) instead enters the UF2 bootloader.

import storage
import usb_cdc
import usb_hid

# Mouse with 5 buttons, X, Y, wheel and AC Pan (horizontal scroll).
# The stock usb_hid.Device.MOUSE report is only buttons/X/Y/wheel (4 bytes),
# so it cannot pan. Report ID 2 matches the stock mouse's ID.
# Report (after the ID): buttons, x, y, wheel, pan  -> 5 bytes.
MOUSE_PAN_DESCRIPTOR = bytes((
    0x05, 0x01,        # Usage Page (Generic Desktop)
    0x09, 0x02,        # Usage (Mouse)
    0xA1, 0x01,        # Collection (Application)
    0x85, 0x02,        #   Report ID (2)
    0x09, 0x01,        #   Usage (Pointer)
    0xA1, 0x00,        #   Collection (Physical)
    0x05, 0x09,        #     Usage Page (Button)
    0x19, 0x01,        #     Usage Minimum (1)
    0x29, 0x05,        #     Usage Maximum (5)
    0x15, 0x00,        #     Logical Minimum (0)
    0x25, 0x01,        #     Logical Maximum (1)
    0x95, 0x05,        #     Report Count (5)
    0x75, 0x01,        #     Report Size (1)
    0x81, 0x02,        #     Input (Data, Var, Abs)
    0x95, 0x01,        #     Report Count (1)
    0x75, 0x03,        #     Report Size (3)
    0x81, 0x01,        #     Input (Const) -- padding
    0x05, 0x01,        #     Usage Page (Generic Desktop)
    0x09, 0x30,        #     Usage (X)
    0x09, 0x31,        #     Usage (Y)
    0x09, 0x38,        #     Usage (Wheel)
    0x15, 0x81,        #     Logical Minimum (-127)
    0x25, 0x7F,        #     Logical Maximum (127)
    0x75, 0x08,        #     Report Size (8)
    0x95, 0x03,        #     Report Count (3)
    0x81, 0x06,        #     Input (Data, Var, Rel)
    0x05, 0x0C,        #     Usage Page (Consumer)
    0x0A, 0x38, 0x02,  #     Usage (AC Pan)
    0x15, 0x81,        #     Logical Minimum (-127)
    0x25, 0x7F,        #     Logical Maximum (127)
    0x75, 0x08,        #     Report Size (8)
    0x95, 0x01,        #     Report Count (1)
    0x81, 0x06,        #     Input (Data, Var, Rel)
    0xC0,              #   End Collection
    0xC0,              # End Collection
))

MOUSE_PAN = usb_hid.Device(
    report_descriptor=MOUSE_PAN_DESCRIPTOR,
    usage_page=0x01,
    usage=0x02,
    report_ids=(2,),
    in_report_lengths=(5,),
    out_report_lengths=(0,),
)

usb_hid.enable((usb_hid.Device.KEYBOARD, MOUSE_PAN, usb_hid.Device.CONSUMER_CONTROL))

# Normal operation: look like a plain keyboard/mouse to Windows.
storage.disable_usb_drive()
usb_cdc.disable()
try:
    import usb_midi
    usb_midi.disable()
except ImportError:
    pass
