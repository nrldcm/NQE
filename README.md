# NQE

**Narrative · Quality · Execution**

*Funds managed by Willong Capital*

A dynamic, multi-account mobile trading ledger for Philippine stock trading funds. NQE tracks your books, cashflows, trade journal, dividends, holdings, and returns — all on-device, encrypted, and corruption-resistant.

---

> ### Credits
>
> **For John Rey Tampus · Willong Capital**
>
> **Developed by Norell Mantilla**

---

## Overview

NQE is a Flutter mobile app (Android) that acts as a personal/fund trading book. Every account, trade, and cashflow lives in a local, transactional SQLite database on your device. Nothing is sent to a server. Backups are encrypted and can be saved to Google Drive for free through the Android share sheet.

## Features

- **Branded Animated Splash** — A branded, animated splash screen on launch.
- **Accounts / Books** — Manage multiple accounts, each with its own broker, currency, and starting capital.
- **Deposits & Withdrawals** — Record cashflows per account.
- **Trade Journal** — Log each trade: stock, shares, buy/sell price, with **auto-calculated P/L**, holding period, setup, remarks, and win/loss tagging.
- **Dividends** — Track dividend income.
- **Holdings** — Track positions and goal shares.
- **Monthly Stats + TWR** — Monthly performance breakdown and **time-weighted return** so deposits/withdrawals don't distort your real performance.
- **AUM Dashboard** — Aggregate assets-under-management view across all accounts.
- **Visual Charts** — Equity curve, monthly P&L bars, win/loss donut, and allocation donut (powered by `fl_chart`).
- **App Lock** — Fingerprint, face unlock, device PIN, device pattern, and device password (all via the OS), plus an in-app 4–6 digit PIN fallback.
- **Day & Night Mode** — Light/dark theme with a manual toggle; your choice is persisted across launches (`shared_preferences`).
- **Polished Design** — Smooth animations and a professional, monochrome design matching the NQE / Willong "leaf" logo.
- **Encrypted Backups** — Export/import your entire ledger as an encrypted `.nqe` file.
- **Regression Tested** — A Flutter unit-test suite (crypto round-trip, calculations, import/export) runs in CI on every push.

## Screenshots

<!-- Add screenshots here -->

| Dashboard | Trade Journal | Charts |
| :---: | :---: | :---: |
| _(screenshot)_ | _(screenshot)_ | _(screenshot)_ |

## How to get the APK

**Option A — Download a prebuilt APK (recommended)**

1. Go to the [Releases](../../releases) page of this repository.
2. Download the latest `app-release.apk`.
3. On your Android device, open the file and allow installation from your browser/file manager if prompted.

Every push to `main` and every version tag (`v*`) triggers a GitHub Actions build that publishes a release APK automatically — building is free on GitHub Actions.

**Option B — Trigger a build yourself**

Fork or clone the repo, then push to `main` (or push a `v*` tag). The `.github/workflows/build-apk.yml` workflow builds the release APK and attaches it to a GitHub Release. CI regenerates the Android platform folder with `flutter create . --platforms=android` and then patches it via `tool/prepare_android.sh` (see [Continuous Integration](#continuous-integration)).

## Build locally

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart SDK `>=3.4.0 <4.0.0`).

```bash
flutter pub get          # install dependencies
flutter create .         # regenerate the android/ platform folder (not committed)
flutter run              # run on a connected device or emulator
```

To build a release APK locally:

```bash
flutter build apk --release
```

> The `android/` (and other platform) folders are intentionally **not** committed — they are regenerated on demand. See `.gitignore`.

## Security model

- **App lock** — The app is protected at launch by the device's own authentication: **fingerprint, face unlock, device PIN, device pattern, or device password** (all via `local_auth` / the OS), plus an **in-app 4–6 digit PIN fallback**.
- **PIN storage** — The in-app PIN is never stored in plaintext. Only a **salted SHA-256 hash** of the PIN is kept, so the PIN itself cannot be recovered from the device.
- **On-device only** — All ledger data stays in a local SQLite database. There is no account, no server, and no network dependency for normal use.

## Backups, export & import

- **Encrypted format** — Backups are exported as encrypted `.nqe` files using **AES-256-GCM**. The encryption key is derived via **PBKDF2** from an app-embedded secret, so **only the app can decrypt** a backup — there is no password for you to remember or lose.
- **Google Drive (free, no setup)** — Export triggers the Android system **share sheet**; tap **"Save to Drive"** to store the encrypted backup in Google Drive for free. No cloud project or API keys required.
- **Automatic Drive sync (optional, Phase 2)** — Fully automatic Google Drive sync is a documented option you can enable later. See [`docs/GOOGLE_DRIVE_AUTOSYNC.md`](docs/GOOGLE_DRIVE_AUTOSYNC.md).

## Corruption resistance

NQE is built to protect your data against corruption and tampering:

- **ACID storage** — The source of truth is a local **SQLite** database (via `sqflite`), which is transactional and resistant to corruption from crashes or interrupted writes.
- **Tamper detection on import** — The AES-256-**GCM** authentication tag detects any corruption or tampering in a `.nqe` file. A modified or damaged backup will fail to decrypt rather than load bad data.
- **Atomic restore** — On import, the file is validated and decrypted first, and the ledger is then **atomically replaced inside a single SQLite transaction**. If anything goes wrong, the existing data is left untouched — a bad file can never corrupt your current ledger.

## Tech stack

- **Framework:** Flutter (Dart)
- **Platform:** Android (APK)
- **Database:** SQLite via `sqflite` (with `path` / `path_provider`)
- **Auth / lock:** `local_auth` (+ `local_auth_android`)
- **Charts:** `fl_chart`
- **Crypto & backup:** `cryptography` (AES-256-GCM / PBKDF2), `share_plus`, `file_picker`
- **Settings / formatting:** `shared_preferences`, `intl`
- **CI/CD:** GitHub Actions

## Project structure

```
lib/
  models.dart               # data models
  calc.dart                 # P/L, TWR, monthly stats calculations
  format.dart               # number / date / currency formatting
  theme.dart                # app theme
  util.dart                 # shared helpers
  seed.dart                 # seed / sample data
  db/
    database.dart           # SQLite schema & data access
  services/
    crypto_service.dart     # AES-256-GCM + PBKDF2 encryption
    backup_service.dart     # encrypted .nqe export / import
    auth_service.dart       # biometric + PIN lock
  state/
    app_state.dart          # app state management
  widgets/
    charts.dart             # equity curve, P&L bars, donuts
    nqe_logo.dart           # branding
    common.dart             # shared UI widgets
  screens/                  # app screens

.github/workflows/
  build-apk.yml             # CI: build + publish release APK

tool/
  prepare_android.sh        # patches generated android/ folder in CI

docs/
  GOOGLE_DRIVE_AUTOSYNC.md  # optional automatic Drive sync guide
```

> Note: `android/`, `ios/`, and other platform folders are **not** committed. They are regenerated with `flutter create .` locally or in CI.

## Continuous integration

The GitHub Actions workflow `.github/workflows/build-apk.yml`:

1. Runs on every push to `main` and on version tags (`v*`).
2. Regenerates platform code with `flutter create . --platforms=android` (the `android/` folder is not committed).
3. Runs `tool/prepare_android.sh` to patch the Android project:
   - Sets `MainActivity` to extend `FlutterFragmentActivity` (required for biometrics).
   - Adds the `USE_BIOMETRIC` and `INTERNET` permissions to the manifest.
   - Sets `applicationId` to `com.willong.nqe` and configures `minSdk`.
4. Builds a release APK and publishes it to a **GitHub Release** automatically.

Building on GitHub Actions is free.

## Testing

NQE is regression tested. A Flutter unit-test suite covering the **crypto round-trip**
(encrypt → decrypt), **calculations** (P/L, TWR, monthly stats), and **import/export** runs
in CI on **every push**, so core financial math and backup integrity stay correct as the app
evolves. Run the suite locally with:

```bash
flutter test
```

---

### Credits

**For John Rey Tampus · Willong Capital**

**Developed by Norell Mantilla**

---

*NQE — Narrative · Quality · Execution. Funds managed by Willong Capital.*
