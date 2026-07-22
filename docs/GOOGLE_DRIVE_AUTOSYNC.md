# Automatic Google Drive Backup (Optional — Phase 2)

> **You do not need this to back up to Google Drive.** NQE already lets you save your
> encrypted `.nqe` backup to Google Drive **for free, with zero setup**: export a backup
> and tap **"Save to Drive"** in the Android share sheet. That method works today.
>
> This document describes an **optional** enhancement: fully **automatic** Google Drive
> sync, where the app uploads your encrypted backup on its own without going through the
> share sheet. It requires a one-time Google Cloud setup and a couple of extra packages.
> Everything below is free.

---

## What automatic sync gives you

- The app signs in with your Google account and uploads the encrypted `.nqe` backup
  automatically (e.g., after changes, or on a schedule) — no manual share-sheet step.
- Backups are stored in Drive's **hidden app-data folder** (`drive.appdata`), which:
  - Is **free** and does not count meaningfully against normal usage.
  - Is **not visible** in the user's normal "My Drive" file list.
  - Is **scoped to this app only** — the app cannot see any of your other Drive files.

The backup uploaded is the same **AES-256-GCM encrypted** `.nqe` file NQE already produces,
so Google never sees your plaintext ledger.

---

## Prerequisites

- A Google account (free).
- Access to the [Google Cloud Console](https://console.cloud.google.com/) (free).
- The app's package name: **`com.willong.nqe`**.
- The **SHA-1 fingerprint** of the signing certificate you use to build the APK
  (see [Step 4](#step-4-get-your-signing-certificate-sha-1-fingerprint)).

---

## Step 1 — Create a Google Cloud project

1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. In the project picker (top bar), click **New Project**.
3. Give it a name (e.g., `NQE Drive Sync`) and click **Create**.
4. Make sure the new project is selected in the project picker.

## Step 2 — Enable the Google Drive API

1. In the console, open **APIs & Services → Library**.
2. Search for **Google Drive API**.
3. Open it and click **Enable**.

## Step 3 — Configure the OAuth consent screen

1. Go to **APIs & Services → OAuth consent screen**.
2. Choose **User type: External** (unless you have a Google Workspace org and want Internal),
   then click **Create**.
3. Fill in the required app information:
   - **App name:** `NQE`
   - **User support email:** your email
   - **Developer contact email:** your email
4. On the **Scopes** step, click **Add or Remove Scopes** and add the Drive app-data scope:

   ```
   https://www.googleapis.com/auth/drive.appdata
   ```

   This is a restricted-but-narrow scope that grants access **only** to the app's own hidden
   data folder — not your whole Drive.
5. On the **Test users** step, add the Google account(s) you'll sign in with while the app is
   in "Testing" status. (You can keep the app in Testing indefinitely for personal use; you do
   not need to publish/verify it just for yourself and your test users.)
6. Save.

## Step 4 — Get your signing certificate SHA-1 fingerprint

An Android OAuth client is tied to your app's **package name + signing certificate SHA-1**.
Use the fingerprint of whatever certificate actually signs the APK you install.

**Option A — Gradle `signingReport` (recommended)**

From the generated Android project folder:

```bash
cd android
./gradlew signingReport
```

Look for the **SHA1** line under the relevant variant (the `debug` config uses the debug
keystore; `release` uses your release keystore if configured).

**Option B — `keytool` directly**

For the default **debug** keystore:

```bash
keytool -list -v \
  -alias androiddebugkey \
  -keystore ~/.android/debug.keystore \
  -storepass android -keypass android
```

For your **release** keystore:

```bash
keytool -list -v \
  -alias <your-key-alias> \
  -keystore /path/to/your/release.keystore
```

Copy the **SHA1** value (a colon-separated hex string like `AB:CD:EF:...`).

> ⚠️ If you install a **release** APK (e.g., the one CI publishes to GitHub Releases),
> you must register the **release** certificate's SHA-1 — the debug SHA-1 will not match.
> If you distribute via Google Play, also register the **Play App Signing** SHA-1 from the
> Play Console.

## Step 5 — Create the Android OAuth client ID

1. Go to **APIs & Services → Credentials**.
2. Click **Create Credentials → OAuth client ID**.
3. **Application type:** **Android**.
4. **Name:** e.g., `NQE Android`.
5. **Package name:** `com.willong.nqe`
6. **SHA-1 certificate fingerprint:** paste the value from [Step 4](#step-4-get-your-signing-certificate-sha-1-fingerprint).
7. Click **Create**.

For an Android OAuth client, you do **not** embed a client secret in the app — Google
authorizes the app by matching the package name + SHA-1 at sign-in time.

---

## Step 6 — Add the required packages

Automatic sync needs two additional Dart packages (add them to `pubspec.yaml`):

```yaml
dependencies:
  google_sign_in: ^6.2.1     # Google account sign-in / OAuth
  googleapis: ^13.2.0        # Google Drive API client (drive.appdata)
```

Then:

```bash
flutter pub get
```

> Check pub.dev for the latest compatible versions when you add them.

At sign-in, request the app-data scope:

```
https://www.googleapis.com/auth/drive.appdata
```

The high-level flow the app would implement:

1. `google_sign_in` signs the user in and requests the `drive.appdata` scope.
2. Obtain an authenticated HTTP client from the signed-in account.
3. Use `googleapis` (`drive/v3`) to upload the encrypted `.nqe` file into the
   **`appDataFolder`** space (create-or-update by filename).
4. To restore, list files in `appDataFolder`, download the latest `.nqe`, and run the app's
   existing encrypted **import** (which validates, decrypts, and atomically replaces the ledger).

Because the uploaded file is already AES-256-GCM encrypted by NQE, Drive only ever stores
ciphertext.

---

## Notes & reminders

- **This is optional.** The free share-sheet method ("Save to Drive") already works with no
  setup and no Cloud project.
- **Everything here is free** — the Cloud project, the Drive API, and the `drive.appdata`
  storage.
- **SHA-1 must match the installed build.** Debug, release, and Play-signed APKs have
  different certificates; register each SHA-1 you actually use.
- **Keep the app in Testing** for personal use — no Google verification is needed as long as
  you sign in with a registered test user and only use the narrow `drive.appdata` scope.
