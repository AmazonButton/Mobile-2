import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../services/api_client.dart';
import '../../../services/ble_pairing_bridge.dart';
import '../../../services/devices_api_service.dart';
import '../../../services/provisioning_api_service.dart';
import '../../../widgets/auth_guide.dart';
import 'signup_theme.dart';
import 'signup_ui_components.dart';

/// Step 3: Real Bluetooth (BLE) discovery & Device ID lookup pairing view.
class StepBlePairingView extends StatefulWidget {
  final VoidCallback onPairingComplete;
  final void Function({
    required String deviceId,
    required String deviceName,
    BluetoothDevice? bleDevice,
    String? sessionId,
  })? onDevicePaired;
  final VoidCallback? onSkip;

  const StepBlePairingView({
    super.key,
    required this.onPairingComplete,
    this.onDevicePaired,
    this.onSkip,
  });

  @override
  State<StepBlePairingView> createState() => StepBlePairingViewState();
}

class StepBlePairingViewState extends State<StepBlePairingView> {
  int _step3SubPhase = 0; // 0: Wake device, 1: Real BLE Scan / Manual Code, 2: Connecting
  bool _isScanningBle = false;
  String? _error;
  String? _statusMessage;

  final TextEditingController _manualCodeCtrl = TextEditingController();
  final List<Map<String, dynamic>> _discoveredDevices = [];
  int _selectedIndex = -1;
  StreamSubscription<List<ScanResult>>? _scanSub;

  @override
  void dispose() {
    _scanSub?.cancel();
    if (!kIsWeb) {
      try {
        FlutterBluePlus.stopScan();
      } catch (_) {}
    }
    _manualCodeCtrl.dispose();
    super.dispose();
  }

  /// Allows parent orchestrator to handle back navigation across subphases
  bool handleBack() {
    if (_step3SubPhase > 0) {
      _stopScanQuietly();
      setState(() {
        _step3SubPhase--;
        _error = null;
      });
      return true;
    }
    return false;
  }

  void _stopScanQuietly() {
    _scanSub?.cancel();
    _scanSub = null;
    if (!kIsWeb) {
      try {
        FlutterBluePlus.stopScan();
      } catch (_) {}
    }
  }

  Future<void> _startBleDiscovery() async {
    HapticFeedback.lightImpact();
    _stopScanQuietly();
    setState(() {
      _step3SubPhase = 1;
      _isScanningBle = true;
      _error = null;
      _statusMessage = null;
      _discoveredDevices.clear();
      _selectedIndex = -1;
    });

    try {
      if (kIsWeb) {
        final foundId = await scanWebBleDevice();
        if (!mounted) return;
        setState(() => _isScanningBle = false);
        if (foundId != null && foundId.trim().isNotEmpty) {
          setState(() {
            _discoveredDevices.add({
              'deviceId': foundId.trim(),
              'name': foundId.trim(),
              'rssi': null,
              'bleDevice': null,
            });
            _selectedIndex = 0;
          });
        } else {
          setState(() {
            _error = 'Chưa chọn thiết bị Bluetooth nào. Bạn có thể quét lại hoặc nhập mã nút bên dưới.';
          });
        }
        return;
      }

      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        if (!mounted) return;
        setState(() {
          _isScanningBle = false;
          _error = 'Thiết bị không hỗ trợ Bluetooth LE. Hãy nhập mã nút in trên thân thiết bị.';
        });
        return;
      }

      final seen = <String, Map<String, dynamic>>{};
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        var changed = false;
        for (final r in results) {
          final advName = r.advertisementData.advName.trim();
          final pName = r.device.platformName.trim();
          final name = advName.isNotEmpty ? advName : pName;
          final upper = name.toUpperCase();
          final hasPrefix = upper.startsWith('BTN') ||
              upper.startsWith('SMARTORDER') ||
              upper.startsWith('SMARTBUTTON') ||
              upper.startsWith('ESP') ||
              upper.startsWith('SOB');
          final hasService = r.advertisementData.serviceUuids.any(
            (u) => u.toString().toLowerCase().contains('fff0'),
          );
          if (hasPrefix || hasService) {
            final key = r.device.remoteId.str;
            seen[key] = {
              'deviceId': name.isNotEmpty ? name : key,
              'name': name.isNotEmpty ? name : 'SmartOrder Button ($key)',
              'rssi': r.rssi,
              'bleDevice': r.device,
            };
            changed = true;
          }
        }
        if (changed && mounted) {
          setState(() {
            _discoveredDevices
              ..clear()
              ..addAll(seen.values);
            if (_selectedIndex < 0 && _discoveredDevices.isNotEmpty) {
              _selectedIndex = 0;
            }
          });
        }
      });

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
      if (!mounted) return;
      setState(() {
        _isScanningBle = false;
        if (_discoveredDevices.isEmpty) {
          _error = 'Không tìm thấy nút bấm Bluetooth quanh đây. Đảm bảo đã bật Bluetooth & đèn nút nhấp nháy xanh, hoặc nhập mã nút bên dưới.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanningBle = false;
        _error = 'Lỗi quét Bluetooth: ${e.toString().replaceFirst('Exception: ', '')}. Bạn có thể nhập mã nút thủ công bên dưới.';
      });
    }
  }

  Future<void> _connectSelectedOrManual() async {
    final manualCode = _manualCodeCtrl.text.trim();
    final hasSelected =
        _selectedIndex >= 0 && _selectedIndex < _discoveredDevices.length;

    if (!hasSelected && manualCode.isEmpty) {
      setState(() {
        _error = 'Vui lòng chọn 1 thiết bị Bluetooth hoặc nhập mã nút bấm (VD: SOB-000001).';
      });
      return;
    }

    HapticFeedback.mediumImpact();
    _stopScanQuietly();
    setState(() {
      _step3SubPhase = 2;
      _error = null;
      _statusMessage = hasSelected
          ? 'Đang kết nối Bluetooth và xác thực mã nút trên hệ thống...'
          : 'Đang đối chiếu mã nút $manualCode với hệ thống...';
    });

    try {
      String resolvedDeviceId = manualCode;
      String resolvedName = manualCode;
      BluetoothDevice? connectedBle;

      if (hasSelected) {
        final item = _discoveredDevices[_selectedIndex];
        resolvedDeviceId = item['deviceId'].toString();
        resolvedName = item['name'].toString();
        final bleDev = item['bleDevice'] as BluetoothDevice?;

        if (!kIsWeb && bleDev != null) {
          await bleDev.connect(timeout: const Duration(seconds: 6));
          connectedBle = bleDev;
          final services = await bleDev.discoverServices();
          for (final s in services) {
            if (s.uuid.toString().toLowerCase().contains('fff0')) {
              for (final c in s.characteristics) {
                if (c.uuid.toString().toLowerCase().contains('fff1')) {
                  final bytes = await c.read();
                  final text = utf8.decode(bytes).trim();
                  if (text.isNotEmpty) {
                    try {
                      final decoded = json.decode(text);
                      if (decoded is Map && decoded['deviceId'] != null) {
                        resolvedDeviceId = decoded['deviceId'].toString().trim();
                      } else {
                        resolvedDeviceId = text;
                      }
                    } catch (_) {
                      resolvedDeviceId = text;
                    }
                  }
                }
              }
            }
          }
        }
      }

      // Đối chiếu mã nút trên Backend nếu đã đăng nhập
      String? sessionId;
      if (ApiClient().isAuthenticated) {
        try {
          final lookup = await DevicesApiService().lookupCode(resolvedDeviceId);
          final serverId = lookup['deviceId']?.toString().trim();
          if (serverId != null && serverId.isNotEmpty) {
            resolvedDeviceId = serverId;
          }
          final serverName = (lookup['buttonName'] ?? lookup['customName'])?.toString().trim();
          if (serverName != null && serverName.isNotEmpty) {
            resolvedName = serverName;
          }
        } catch (e) {
          // Nếu nhập thủ công (không có phần cứng BLE), phải báo lỗi thật từ BE
          if (!hasSelected) {
            rethrow;
          }
        }

        try {
          final session = await ProvisioningApiService().createSession();
          sessionId = (session['sessionId'] ?? session['id'])?.toString();
        } catch (_) {}
      }

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      widget.onDevicePaired?.call(
        deviceId: resolvedDeviceId,
        deviceName: resolvedName.isNotEmpty ? resolvedName : resolvedDeviceId,
        bleDevice: connectedBle,
        sessionId: sessionId,
      );
      widget.onPairingComplete();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step3SubPhase = 1;
        _error = e is ApiException
            ? e.message
            : 'Ghép nối thất bại: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(child: _buildSubPhaseContent()),
          ),
        );
      },
    );
  }

  Widget _buildSubPhaseContent() {
    if (_step3SubPhase == 0) {
      // 3A: Đánh thức thiết bị
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const AuthGuide(
            message: 'Đặt nút bấm ở gần điện thoại để cùng kết nối nhé!',
            mood: GuideMood.guiding,
          ),
          const SizedBox(height: 24),
          const Text(
            'Đánh thức thiết bị của bạn',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: SignupTheme.figmaDark,
              fontFamily: SignupTheme.fontFamily,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Nhấn giữ nút khoảng 6 giây (hoặc bấm nhanh 5 lần) đến khi đèn xanh nhấp nháy.',
            style: TextStyle(
              fontSize: 15,
              color: SignupTheme.figmaMuted,
              fontFamily: SignupTheme.fontFamily,
            ),
          ),
          const SizedBox(height: 24),

          // Signal Info Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SignupTheme.figmaBlueLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: SignupTheme.figmaBlueBorder),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    LucideIcons.radio,
                    color: SignupTheme.figmaBlue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Xanh dương nhấp nháy',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: SignupTheme.figmaDark,
                          fontFamily: SignupTheme.fontFamily,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Thiết bị đã sẵn sàng để tìm thấy qua Bluetooth.',
                        style: TextStyle(
                          fontSize: 13,
                          color: SignupTheme.figmaMuted,
                          fontFamily: SignupTheme.fontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          SignupPrimaryButton(
            label: 'Đèn đã nhấp nháy xanh',
            onTap: _startBleDiscovery,
          ),
          const SizedBox(height: 8),
          SignupSecondaryButton(
            label: 'Không thấy đèn?',
            onTap: () => showSignupHelpBottomSheet(context),
          ),
          if (widget.onSkip != null) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: widget.onSkip,
                child: const Text(
                  'Bỏ qua, cài đặt nút sau',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: SignupTheme.figmaMuted,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      );
    } else if (_step3SubPhase == 1) {
      // 3B: Quét BLE thật + fallback nhập mã nút thủ công
      final hasSelection =
          _selectedIndex >= 0 && _selectedIndex < _discoveredDevices.length;
      final canConnect =
          !_isScanningBle && (hasSelection || _manualCodeCtrl.text.trim().isNotEmpty);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          AuthGuide(
            mood: _isScanningBle
                ? GuideMood.waiting
                : (_discoveredDevices.isNotEmpty ? GuideMood.happy : GuideMood.guiding),
            message: _isScanningBle
                ? 'Mình đang quét sóng Bluetooth quanh bạn…'
                : _discoveredDevices.isNotEmpty
                    ? 'Tìm thấy nút rồi! Chọn nút bấm của bạn nhé.'
                    : 'Bạn có thể quét lại Bluetooth hoặc nhập mã nút in trên thiết bị.',
          ),
          const SizedBox(height: 20),
          Text(
            _isScanningBle
                ? 'Đang tìm thiết bị...'
                : (_discoveredDevices.isNotEmpty
                    ? 'Tìm thấy thiết bị rồi!'
                    : 'Chọn hoặc nhập mã nút'),
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              color: SignupTheme.figmaDark,
              fontFamily: SignupTheme.fontFamily,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isScanningBle
                ? 'Xin vui lòng đưa nút bấm lại gần điện thoại.'
                : 'Chọn nút phát hiện qua Bluetooth hoặc nhập mã thiết bị để xác thực.',
            style: const TextStyle(
              fontSize: 14.5,
              color: SignupTheme.figmaMuted,
              fontFamily: SignupTheme.fontFamily,
            ),
          ),
          const SizedBox(height: 16),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(LucideIcons.alertCircle, size: 18, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFFDC2626), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          if (_isScanningBle)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: CircularProgressIndicator(color: SignupTheme.figmaBlue),
              ),
            )
          else ...[
            ...List.generate(_discoveredDevices.length, (index) {
              final dev = _discoveredDevices[index];
              final isSelected = index == _selectedIndex;
              final rssi = dev['rssi'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () => setState(() {
                    _selectedIndex = index;
                    _error = null;
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected ? SignupTheme.figmaBlueLight : SignupTheme.figmaInputBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? SignupTheme.figmaBlue : SignupTheme.figmaBorder,
                        width: isSelected ? 2 : 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: SignupTheme.figmaBlueBorder),
                          ),
                          child: const Icon(LucideIcons.disc, color: SignupTheme.figmaBlue, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dev['name'].toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  color: SignupTheme.figmaDark,
                                  fontFamily: SignupTheme.fontFamily,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                rssi != null ? 'Bluetooth LE · Sóng $rssi dBm' : 'Bluetooth LE · Sẵn sàng ghép nối',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: SignupTheme.figmaMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          const Icon(LucideIcons.checkCircle2, color: SignupTheme.figmaBlue, size: 22),
                      ],
                    ),
                  ),
                ),
              );
            }),

            // Manual Device ID Input fallback
            const SizedBox(height: 4),
            const Text(
              'Hoặc nhập mã nút thủ công',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: SignupTheme.figmaDark,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _manualCodeCtrl,
              onChanged: (_) => setState(() {
                if (_manualCodeCtrl.text.trim().isNotEmpty) {
                  _selectedIndex = -1;
                }
              }),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'VD: SOB-000001 hoặc PIN 6 số',
                prefixIcon: const Icon(LucideIcons.qrCode, size: 18),
                filled: true,
                fillColor: SignupTheme.figmaInputBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: SignupTheme.figmaBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: SignupTheme.figmaBorder),
                ),
              ),
            ),
          ],

          const Spacer(),
          const SizedBox(height: 16),

          SignupPrimaryButton(
            label: 'Kết nối',
            isEnabled: canConnect,
            onTap: _connectSelectedOrManual,
          ),
          const SizedBox(height: 8),
          SignupSecondaryButton(
            label: 'Tìm lại thiết bị',
            onTap: _startBleDiscovery,
          ),
          if (widget.onSkip != null) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: widget.onSkip,
                child: const Text(
                  'Bỏ qua, cài đặt nút sau',
                  style: TextStyle(fontSize: 13, color: SignupTheme.figmaMuted),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      );
    } else {
      // 3C: Đang ghép nối
      return Column(
        children: [
          const Spacer(flex: 1),
          Image.asset(
            'assets/illustrations/step3_pairing.png',
            height: 200,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const SignupFallbackIllustration(icon: LucideIcons.bluetooth),
          ),
          const SizedBox(height: 32),
          const Text(
            'Đang ghép nối...',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: SignupTheme.figmaDark,
              fontFamily: SignupTheme.fontFamily,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _statusMessage ?? 'Đang thiết lập kênh giao tiếp an toàn qua Bluetooth.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: SignupTheme.figmaMuted,
              fontFamily: SignupTheme.fontFamily,
            ),
          ),
          const SizedBox(height: 32),
          const CircularProgressIndicator(color: SignupTheme.figmaBlue),
          const Spacer(flex: 2),
        ],
      );
    }
  }
}
