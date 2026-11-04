/// Cross-platform BLE bridge interface (initial scaffold before Web Bluetooth interop).
class BleScannedDevice {
  final String deviceId;
  final String name;
  final String rawPayload;

  const BleScannedDevice({
    required this.deviceId,
    required this.name,
    this.rawPayload = '',
  });
}

bool get isWebBluetoothSupported => false;

Future<BleScannedDevice?> scanSmartOrderBleWeb() async {
  throw UnsupportedError('Web Bluetooth interop not configured yet.');
}

Future<bool> sendWifiOverBleWeb({
  required String expectedDeviceId,
  required String ssid,
  required String password,
}) async {
  return false;
}

Future<void> disconnectSmartOrderBleWeb() async {}
