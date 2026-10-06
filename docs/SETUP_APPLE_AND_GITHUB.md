# Setup: Apple + GitHub (no Mac needed)

GitHub's cloud Mac builds the app, Apple signs it in the cloud, and it lands in TestFlight on your iPhone.

## 1. Find your Team ID
1. Go to https://developer.apple.com/account and sign in.
2. Click **Membership details** (sidebar, or scroll down).
3. Copy the 10-character **Team ID** (for example `AB12CD34EF`). This is `APPLE_TEAM_ID`.

## 2. Bundle ID (`com.andyli.mouseremote`)
Automatic signing (`-allowProvisioningUpdates`) normally registers the App ID for you on the first build, so you can skip this. To be safe, do it manually:
1. https://developer.apple.com/account -> **Certificates, Identifiers & Profiles** -> **Identifiers** -> **+**.
2. Choose **App IDs** -> **App** -> Continue.
3. Description `MouseRemote`, Bundle ID **Explicit** = `com.andyli.mouseremote`. Continue -> Register.

## 3. Create the app record in App Store Connect
This is required; the upload fails without it.
1. https://appstoreconnect.apple.com -> **Apps** -> **+** -> **New App**.
2. Platform **iOS**, Name `MouseRemote` (names are globally unique; if taken use e.g. `MouseRemote AndyLi`), Primary language English.
3. Bundle ID: pick `com.andyli.mouseremote` from the list (if missing, do step 2 first).
4. SKU: any unique text, e.g. `mouseremote-001`. User access: Full Access. Click **Create**.

## 4. Create the App Store Connect API key
1. App Store Connect -> **Users and Access** -> **Integrations** tab -> **App Store Connect API** -> **Team Keys**.
2. Click **+** (or **Request Access** first if shown, then confirm).
3. Name `GitHub CI`, Access: **Admin**. Click **Generate**.
   - **Admin is required.** Cloud signing a distribution certificate with `xcodebuild` fails with "Cloud signing permission error" for App Manager keys.
4. Note the **Key ID** (`ASC_KEY_ID`) and, at the top of the page, the **Issuer ID** (`ASC_ISSUER_ID`).
5. Click **Download API Key**. You get `AuthKey_XXXX.p8`. **It can only be downloaded once.** Keep it safe and never commit it (`.gitignore` blocks `*.p8`).

## 5. Create a private GitHub repo and push
1. Install Git for Windows (https://git-scm.com) if needed. Create a repo at https://github.com/new -> name `mouse_remote`, **Private** -> Create (leave it empty).
2. In PowerShell:
```powershell
cd "C:\Users\andyl\Desktop\GitHub Apps\mouse_remote"
git init -b main
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/<your-username>/mouse_remote.git
git push -u origin main
```
Option with the GitHub CLI (`winget install GitHub.cli`, then `gh auth login`):
```powershell
git init -b main
git add .
git commit -m "Initial commit"
gh repo create mouse_remote --private --source . --push
```

## 6. Add the 4 secrets
Repo -> **Settings** -> **Secrets and variables** -> **Actions** -> **New repository secret**:

| Name | Value |
|---|---|
| `APPLE_TEAM_ID` | Team ID from step 1 |
| `ASC_KEY_ID` | Key ID from step 4 |
| `ASC_ISSUER_ID` | Issuer ID from step 4 |
| `ASC_KEY_P8` | Open the `.p8` in Notepad, copy **everything** (including the `-----BEGIN PRIVATE KEY-----` lines), paste |

Or with `gh` (run in the repo folder):
```powershell
gh secret set APPLE_TEAM_ID --body "AB12CD34EF"
gh secret set ASC_KEY_ID --body "XXXXXXXXXX"
gh secret set ASC_ISSUER_ID --body "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
gh secret set ASC_KEY_P8 < "C:\path\to\AuthKey_XXXX.p8"
```
(If `<` fails in PowerShell: `Get-Content "C:\path\AuthKey_XXXX.p8" -Raw | gh secret set ASC_KEY_P8`.)

## 7. Run the workflow
1. Repo -> **Actions** -> **iOS TestFlight** -> **Run workflow** -> main -> Run. (It also runs on pushes to `main` that change `ios/**`.)
2. Takes roughly 10 to 20 minutes. On failure, open the run and download the `ios-debug-*` artifact (logs).
3. Each run uses its run number as the build number, so uploads never collide.

## 8. Install via TestFlight
1. On the iPhone, install **TestFlight** from the App Store and sign in with the same Apple ID.
2. App Store Connect -> **Users and Access** -> make sure your Apple ID is a user (the account holder already is).
3. App Store Connect -> your app -> **TestFlight** -> **Internal Testing** -> **+** next to the group -> create a group (e.g. `Me`), enable automatic distribution, add yourself as a tester.
4. After processing (a few minutes after upload; you get an email) open TestFlight on the iPhone and tap **Install**.
- Internal testing needs **no Beta App Review**.
- Export compliance: the app sets `ITSAppUsesNonExemptEncryption=false`, so Apple will not prompt for it.

## 9. GitHub Actions cost
macOS minutes are billed at 10x on private repos. The free plan gives 2,000 included minutes per month, which equals about 200 macOS minutes. A build of roughly 10 to 15 minutes means about 13 to 20 builds per month. Public repos are free, but keep this one private. Check usage under GitHub -> Settings -> Billing.
