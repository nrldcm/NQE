# NQE

**Narrative · Quality · Execution**

*Funds managed by Willong Capital*

A dynamic, multi-account trading ledger for Philippine stock trading funds — on **Android** and **Windows desktop**. NQE tracks your books, cashflows, trade journal, dividends, holdings, and returns — all on-device, encrypted, and corruption-resistant.

---

> ### Credits
>
> **For John Rey Tampus · Willong Capital**
>
> **Developed by Norell Mantilla**

---

## Overview

NQE is a Flutter app that acts as a personal/fund trading book. Every account, trade, and cashflow lives in a local, transactional SQLite database on your device. Nothing is sent to a server. Backups are encrypted and can be saved to Google Drive for free through the Android share sheet.

The **Windows desktop app** mirrors the phone one-for-one and stays in sync with it over your local network — your **phone is always the source of truth**.

> **Versioning:** NQE stays on **version 1**. The major version is fixed at `1`; only the minor version auto-increments (1.1 → 1.2 → 1.3 …) as features land.

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
- **Live tab** — Embedded TradingView chart for any symbol (e.g. `NASDAQ:AAPL`, `PSE:SPNEC`).
- **Developer Mode** — Optional integrations panel for API keys. Keys are **AES-256-GCM encrypted in SQLite**, shown only as a masked hint, and **cannot be viewed again once saved** (delete + re-add to change). No app rebuild needed.
- **App Lock** — Fingerprint, face unlock, device PIN, device pattern, and device password (all via the OS), plus an in-app 4–6 digit PIN fallback.
- **Day & Night Mode** — Light/dark theme with a manual toggle; your choice is persisted across launches (`shared_preferences`).
- **Polished Design** — Smooth animations and a professional, monochrome design matching the NQE / Willong "leaf" logo.
- **Encrypted Backups** — Export/import your entire ledger as an encrypted `.nqe` file.
- **Desktop app + secure device sync** — see below.
- **Regression & security tested** — A Flutter unit-test suite (crypto round-trip, calculations, PIN lockout, sync merge, and the pairing handshake) runs in CI on every push.

## Desktop app (Windows)

The Windows build is the **same app in client mode** — full parity with the phone: **Home / Books / Live / Stats / Settings**, the same theme, the same data model.

- **Single-file `.exe`** — distributed as one self-contained executable (packaged with warp-packer), alongside a portable zip.
- **Single instance** — launching again just focuses the existing window.
- **Phone is the source of truth** — the desktop keeps its local SQLite copy in sync with the phone over the LAN. Edits on either device converge automatically (idempotent, tombstone-aware merge — no duplicates, deletes propagate, restorable).
- **Same PIN** — after pairing, the desktop unlocks with the **same PIN you set on your phone**.
- **Connection watcher** — a live glyph shows Connected / Connecting / Reconnecting / Disconnected, with automatic backoff-retry and a manual reconnect.

### Secure pairing (QR + 6-digit code)

Pairing is designed to resist LAN eavesdroppers and man-in-the-middle attackers:

1. On the **desktop**, first run shows a **QR code** (and a copyable link).
2. On the **phone**: **Settings ▸ Device Sync**, turn on **LAN Sync Server**, then tap **Pair Desktop Device** — the camera opens and you **scan the desktop's QR**.
3. Both devices perform an **X25519 (ECDH) key exchange**. The phone shows a **6-digit code** — a *Short Authentication String* computed from **both** public keys.
4. You type that code into the desktop.

Why it's safe: the sync credentials and PIN are sealed with **AES-256-GCM under the full-entropy ECDH key** — the 6-digit code is an *integrity check of the key exchange*, never the encryption key. A passive sniffer can't decrypt anything, and an active attacker who swaps keys changes the 6-digit code, so the human comparison catches the tampering. Keys are ephemeral (forward secrecy) and bound to the pairing session.

## Screenshots

<!-- Add screenshots here -->

| Dashboard | Trade Journal | Charts | Desktop |
| :---: | :---: | :---: | :---: |
| _(screenshot)_ | _(screenshot)_ | _(screenshot)_ | _(screenshot)_ |

## How to get the app

Go to the [Releases](../../releases) page:

- **Android** — download the latest `NQE-v1.x.apk`, open it on your device, and allow installation from your browser/file manager if prompted.
- **Windows** — download the single-file `NQE-v1.x.exe` (or the portable zip) and run it.

Every push to `main` and every version tag (`v*`) triggers a GitHub Actions build that publishes the APK and the Windows `.exe` automatically — building is free on GitHub Actions. The feature branch also publishes to a **`preview`** channel (still version 1, marked unstable) for testing before merge.

## Build locally

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart SDK `>=3.4.0 <4.0.0`).

```bash
flutter pub get          # install dependencies
flutter create .         # regenerate the platform folders (not committed)
flutter run              # run on a connected device / emulator
```

Release builds:

```bash
flutter build apk --release        # Android
flutter build windows --release    # Windows desktop
```

> The `android/`, `windows/`, and other platform folders are intentionally **not** committed — they are regenerated on demand. See `.gitignore`.

## Security model

- **App lock** — The app is protected at launch by the device's own authentication: **fingerprint, face unlock, device PIN, device pattern, or device password** (via `local_auth` / the OS), plus an **in-app 4–6 digit PIN fallback**. The desktop uses a **PIN or password** (no biometric), mirrored from the phone at pairing.
- **PIN storage** — The in-app PIN is never stored in plaintext. Only a **salted PBKDF2-HMAC-SHA256 hash** (100k iterations, constant-time compare) is kept, with an escalating lockout after repeated wrong attempts.
- **Encrypted integration keys** — Developer-Mode API keys are AES-256-GCM encrypted in SQLite and never shown again after saving.
- **Secure pairing** — SAS-authenticated X25519 key exchange; payloads sealed with AES-256-GCM (see *Secure pairing* above).
- **On-device only** — All ledger data stays in local SQLite. There is no account and no cloud dependency; device sync is peer-to-peer over your own LAN.

## Backups, export & import

- **Encrypted format** — Backups are exported as encrypted `.nqe` files using **AES-256-GCM**. The key is derived via **PBKDF2** from an app-embedded secret, so **only the app can decrypt** a backup — no password to remember. An **optional passphrase** can be set for real confidentiality even for files saved to Drive.
- **Google Drive (free, no setup)** — Export triggers the system **share sheet**; tap **"Save to Drive"** to store the encrypted backup for free. No cloud project or API keys required.

## Corruption resistance

- **ACID storage** — The source of truth is a local **SQLite** database (via `sqflite`), transactional and resistant to corruption from crashes or interrupted writes.
- **Tamper detection on import** — The AES-256-**GCM** authentication tag detects any corruption or tampering in a `.nqe` file; a modified or damaged backup fails to decrypt rather than loading bad data.
- **Atomic restore** — On import the file is validated and decrypted first, then the ledger is **atomically replaced inside a single SQLite transaction**. A bad file can never corrupt your current ledger.

## Tech stack

- **Framework:** Flutter (Dart)
- **Platforms:** Android (APK) + Windows desktop (single-file `.exe`)
- **Database:** SQLite via `sqflite` (mobile) / `sqflite_common_ffi` + `sqlite3_flutter_libs` (desktop)
- **Auth / lock:** `local_auth` (+ `local_auth_android`), PBKDF2 PIN
- **Charts:** `fl_chart`
- **Live charts:** `webview_flutter` (mobile) / `webview_windows` (desktop)
- **Device sync & pairing:** `shelf` + `shelf_web_socket`, `web_socket_channel`, `network_info_plus`, `qr_flutter`, `mobile_scanner` (camera), `flutter_foreground_task`; `cryptography` (X25519 / HKDF / AES-256-GCM)
- **Crypto & backup:** `cryptography` (AES-256-GCM / PBKDF2), `share_plus`, `file_picker`
- **Desktop shell:** `window_manager`, `windows_single_instance`, `url_launcher`
- **CI/CD:** GitHub Actions

## Project structure

```
lib/
  models.dart               # data models
  calc.dart                 # P/L, TWR, monthly stats calculations
  format.dart               # number / date / currency formatting
  theme.dart                # app theme
  main.dart                 # entrypoint (mobile + desktop bootstrap)
  db/
    database.dart           # SQLite schema & data access
  services/
    crypto_service.dart     # AES-256-GCM + PBKDF2 encryption
    backup_service.dart     # encrypted .nqe export / import
    auth_service.dart       # biometric + PIN lock (+ PIN mirror for pairing)
  state/
    app_state.dart          # app state management
  sync/
    pairing.dart            # SAS-authenticated X25519 pairing crypto
    pairing_host.dart       # desktop: QR + pairing listener
    pairing_client.dart     # phone: scan + sealed handoff
    sync_engine.dart        # deterministic, idempotent merge
    sync_repo.dart          # snapshot build / apply
    sync_server.dart        # phone LAN server (source of truth)
    sync_client.dart        # desktop LAN client
  widgets/
    charts.dart             # equity curve, P&L bars, donuts
    connection_watcher.dart # live sync-status glyph
    nqe_logo.dart           # branding
  screens/                  # mobile screens
    desktop/                # desktop shell, lock, live, pairing

.github/workflows/
  build-apk.yml             # CI: build + publish release APK
  build-desktop.yml         # CI: build + publish Windows .exe
  cleanup-legacy-tag.yml    # one-off maintenance

tool/
  prepare_android.sh        # patches generated android/ folder in CI
```

> Note: `android/`, `windows/`, and other platform folders are **not** committed. They are regenerated with `flutter create .` locally or in CI.

## Continuous integration

- **`build-apk.yml`** — on every push to `main` and version tags: regenerates the Android platform, patches it via `tool/prepare_android.sh` (FlutterFragmentActivity for biometrics; `USE_BIOMETRIC` / `INTERNET` / `CAMERA` and sync permissions; `com.willong.nqe`; `minSdk 23`; `allowBackup=false`; FLAG_SECURE), builds a signed release APK, and publishes it.
- **`build-desktop.yml`** — on `windows-2022`: enables the Windows platform, applies the app icon, builds the release, packages a **single-file `.exe`** (warp-packer) plus a portable zip, and publishes them.
- **Intelligent versioning** — the major version stays `1`; the minor auto-increments from the highest existing `v1.N.0` release.

Building on GitHub Actions is free.

## Testing

NQE is regression **and** security tested. The Flutter unit-test suite covers the **crypto round-trip** (encrypt → decrypt), **calculations** (P/L, TWR, monthly stats), **PIN lockout**, **sync merge** (idempotency + tombstones), and the **pairing handshake** (shared-key agreement, eavesdropper rejection, MITM detection). It runs in CI on **every push**. Run it locally with:

```bash
flutter test
```

---

### Credits

**For John Rey Tampus · Willong Capital**

**Developed by Norell Mantilla**

---

*NQE — Narrative · Quality · Execution. Funds managed by Willong Capital.*
