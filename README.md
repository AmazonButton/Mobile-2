# SmartOrder Button Mobile

Cross-platform Flutter app (Android / iOS / Web PWA) for the SmartOrder Button IoT ecosystem.

## Core Features
- Role-based dashboards for Customer, Store Owner, and Admin
- Goong Maps geocoding and 5km free-delivery estimation
- PayOS QR payment integration
- ESP32 BLE GATT pairing (`0000FFF0` / `0000FFF1` / `0000FFF2`)

## Development

```bash
flutter pub get
flutter analyze
flutter build web --release
```
