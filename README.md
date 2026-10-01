# Zaam EPOS

Cross-platform point of sale for Zaam ERP (iOS, iPadOS, Android, macOS, Windows, web), built with Flutter.
Feature status and research notes: [docs/FEATURES.md](docs/FEATURES.md).

## Requirements

- Flutter 3.41+ / Dart 3.11+
- Zaam API with the `/api/pos` module and migration 019 applied

## Backend setup (zaam-api)

```bash
cd ../zaam-api
npm run migrate:019     # POS tables: registers, shifts, cash movements, staff PINs, clock, availability, modifiers
npm run build           # then deploy as usual (deploy_api.sh)
```

Users need one of the till roles (`POS_CASHIER`, `SALES_REP`, `CUSTOMER_SERVICE`, `WAREHOUSE_MANAGER`, `POS_MANAGER`, `ADMIN`, `SUPER_ADMIN`).
Managers set staff PINs and till roles in **Options → Settings → Staff PINs & roles**.

## Run

The API URL defaults to `https://erp-api.zaamaitech.co.uk` and can be changed on the login screen or at build time:

```bash
flutter pub get
flutter run -d chrome  --dart-define=API_BASE_URL=http://localhost:4000
flutter run -d macos
flutter run -d windows
flutter run -d <ios-or-android-device-id>
```

Release builds: `flutter build web | macos | windows | apk | appbundle | ipa`.

Customer display (web): **Options → Connect Display** opens `?display=1` in a new window; drag it to the second screen.

## Payments & printers

- **Card:** standalone terminal (confirm manually) or SumUp Solo – enter API key, merchant code and reader id in **Settings → Card provider**.
- **Printers:** ESC/POS network printers (IP, port 9100) with cash drawer kick, or PDF via the system print dialog.

## Checks

```bash
dart analyze
flutter test
```
