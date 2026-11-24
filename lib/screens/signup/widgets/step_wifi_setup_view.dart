import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../services/api_client.dart';
import '../../../services/ble_pairing_bridge.dart';
import '../../../services/devices_api_service.dart';
import '../../../services/provisioning_api_service.dart';
import '../../../widgets/auth_guide.dart';
import 'signup_theme.dart';
import 'signup_ui_components.dart';

/// Step 4: Real WiFi provisioning view (auto-detects current phone SSID + manual 2.4GHz input + real BLE/Backend write).
class StepWifiSetupView extends StatefulWidget {
  final String deviceId;
  final String selectedDeviceName;
  final BluetoothDevice? bleDevice;
  final String? sessionId;
  final VoidCallback onWifiConnected;
  final ValueChanged<String>? onWifiProvisioned;
  final VoidCallback? onSkip;

  const StepWifiSetupView({
    super.key,
    this.deviceId = '',
    this.selectedDeviceName = 'Nút nhấn SmartOrder',
    this.bleDevice,
    this.sessionId,
    required this.onWifiConnected,
    this.onWifiProvisioned,
    this.onSkip,
  });

  @override
  State<StepWifiSetupView> createState() => StepWifiSetupViewState();
}

class StepWifiSetupViewState extends State<StepWifiSetupView> {
  int _step4SubPhase = 0; // 0: Select/Enter WiFi, 1: Password, 2: Real 3-stage provisioning
  String? _detectedSsid;
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _wifiPasswordController = TextEditingController();
  final FocusNode _ssidFocusNode = FocusNode();
  bool _isWifiPasswordObscured = true;
  int _wifiConnectProgressStage = 0; // 0: Sending, 1: Verifying Cloud, 2: Binding, 3: Done
  String? _error;

  @override
  void initState() {
    super.initState();
    _ssidController.addListener(() => setState(() {}));
    _wifiPasswordController.addListener(() => setState(() {}));
    _detectCurrentWifi();
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _wifiPasswordController.dispose();
    _ssidFocusNode.dispose();
    super.dispose();
  }

  Future<void> _detectCurrentWifi() async {
    if (kIsWeb) return;
    try {
      final status = await Permission.locationWhenInUse.status;
      if (!status.isGranted) {
        await Permission.locationWhenInUse.request();
      }
      final raw = await NetworkInfo().getWifiName();
      if (!mounted || raw == null) return;
      final clean =
          raw.startsWith('"') && raw.endsWith('"') && raw.length >= 2
              ? raw.substring(1, raw.length - 1)
              : raw;
      if (clean.trim().isNotEmpty &&
          clean.trim().toLowerCase() != '<unknown ssid>') {
        setState(() {
          _detectedSsid = clean.trim();
          if (_ssidController.text.trim().isEmpty) {
            _ssidController.text = _detectedSsid!;
          }
        });
      }
    } catch (_) {
      // Simulators/tests without Wi-Fi plugin fall back cleanly to manual input
    }
  }

  bool _looksLike5Ghz(String ssid) {
    final upper = ssid.trim().toUpperCase();
    return upper.endsWith('_5G') ||
        upper.endsWith('-5G') ||
        upper.endsWith(' 5G') ||
        upper.contains('5GHZ');
  }

  /// Allows parent orchestrator to handle back navigation across subphases
  bool handleBack() {
    if (_step4SubPhase > 0) {
      setState(() {
        _step4SubPhase--;
        _error = null;
      });
      return true;
    }
    return false;
  }

  void _submitWifiNetwork() {
    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập tên mạng Wi-Fi 2.4GHz của bạn.'),
          backgroundColor: SignupTheme.figmaDanger,
        ),
      );
      return;
    }
    if (_looksLike5Ghz(ssid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nút bấm chỉ hỗ trợ Wi-Fi băng tần 2.4GHz!'),
          backgroundColor: SignupTheme.figmaDanger,
        ),
      );
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _error = null;
      _step4SubPhase = 1;
    });
  }

  Future<void> _showManualSsidDialog() async {
    final ctrl = TextEditingController(text: _ssidController.text);
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(
            'Nhập tên mạng Wi-Fi',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Tên mạng (SSID 2.4GHz)',
              hintText: 'VD: Nha_Minh_2.4G',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Chọn mạng'),
            ),
          ],
        ),
      );
      if (result != null && result.isNotEmpty && mounted) {
        if (_looksLike5Ghz(result)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nút bấm chỉ hỗ trợ Wi-Fi băng tần 2.4GHz!'),
              backgroundColor: SignupTheme.figmaDanger,
            ),
          );
          return;
        }
        setState(() => _ssidController.text = result);
      }
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _startWifiProvisioning() async {
    final ssid = _ssidController.text.trim();
    final password = _wifiPasswordController.text;
    if (ssid.isEmpty || password.isEmpty) return;

    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _step4SubPhase = 2;
      _wifiConnectProgressStage = 0;
    });

    try {
      // Stage 0 -> 1: Gửi SSID & password thật qua BLE GATT FFF2 hoặc Backend API
      if (kIsWeb) {
        await sendWebBleWifi(widget.deviceId, ssid, password);
      } else if (widget.bleDevice != null) {
        final dev = widget.bleDevice!;
        try {
          await dev.connect(timeout: const Duration(seconds: 5));
        } catch (_) {}
        final services = await dev.discoverServices();
        var wrote = false;
        for (final s in services) {
          if (s.uuid.toString().toLowerCase().contains('fff0')) {
            for (final c in s.characteristics) {
              if (c.uuid.toString().toLowerCase().contains('fff2')) {
                await c.write(
                  utf8.encode('$ssid:$password'),
                  withoutResponse: false,
                );
                wrote = true;
              }
            }
          }
        }
        if (!wrote && widget.deviceId.trim().isNotEmpty) {
          await ProvisioningApiService().changeWifi(
            deviceId: widget.deviceId.trim(),
            ssid: ssid,
            password: password,
          );
        }
      } else if (widget.deviceId.trim().isNotEmpty) {
        await ProvisioningApiService().changeWifi(
          deviceId: widget.deviceId.trim(),
          ssid: ssid,
          password: password,
        );
      } else {
        throw StateError('Không có mã thiết bị hoặc kết nối Bluetooth để nạp Wi-Fi.');
      }

      if (!mounted) return;
      setState(() => _wifiConnectProgressStage = 1);

      // Stage 1 -> 2: Xác thực phiên & gắn thiết bị lên hệ thống Backend
      if (ApiClient().isAuthenticated && widget.deviceId.trim().isNotEmpty) {
        if (widget.sessionId != null && widget.sessionId!.isNotEmpty) {
          try {
            await ProvisioningApiService().verifySession(
              sessionId: widget.sessionId!,
              deviceId: widget.deviceId.trim(),
            );
          } catch (_) {}
        }
        if (!mounted) return;
        setState(() => _wifiConnectProgressStage = 2);

        try {
          await DevicesApiService().configureByCode({
            'code': widget.deviceId.trim(),
          });
        } catch (_) {
          // Nếu nút đã claim trước đó thì bỏ qua bước claim lại
        }
      } else {
        if (!mounted) return;
        setState(() => _wifiConnectProgressStage = 2);
      }

      if (!mounted) return;
      setState(() => _wifiConnectProgressStage = 3);
      HapticFeedback.heavyImpact();
      widget.onWifiProvisioned?.call(ssid);
      widget.onWifiConnected();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step4SubPhase = 1;
        _error = e is ApiException
            ? e.message
            : 'Nạp Wi-Fi thất bại: ${e.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '')}';
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
    final currentSsid = _ssidController.text.trim();

    if (_step4SubPhase == 0) {
      final is5g = _detectedSsid != null && _looksLike5Ghz(_detectedSsid!);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const AuthGuide(
            message: 'Cùng kết nối nút bấm với Wi-Fi 2.4GHz nhà bạn nhé!',
            mood: GuideMood.guiding,
          ),
          const SizedBox(height: 24),
          const Text(
            'Chọn WiFi cho thiết bị',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: SignupTheme.figmaDark,
              fontFamily: SignupTheme.fontFamily,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Chọn hoặc nhập mạng Wi-Fi băng tần 2.4GHz bạn muốn dùng.',
            style: TextStyle(
              fontSize: 15,
              color: SignupTheme.figmaMuted,
              fontFamily: SignupTheme.fontFamily,
            ),
          ),
          const SizedBox(height: 16),

          // 2.4GHz warning banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.alertTriangle, size: 18, color: Color(0xFFEA580C)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Nút bấm chỉ hỗ trợ Wi-Fi băng tần 2.4GHz (không hỗ trợ mạng 5GHz).',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFFC2410C), height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_detectedSsid != null) ...[
            _buildWifiItem(
              ssid: _detectedSsid!,
              desc: is5g
                  ? '5GHz · Không được hỗ trợ'
                  : '2.4GHz · Điện thoại đang dùng',
              isSelected: !is5g && currentSsid == _detectedSsid,
              isSupported: !is5g,
              onTap: () {
                if (is5g) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Nút bấm chỉ hỗ trợ Wi-Fi băng tần 2.4GHz!'),
                      backgroundColor: SignupTheme.figmaDanger,
                    ),
                  );
                  return;
                }
                setState(() => _ssidController.text = _detectedSsid!);
              },
            ),
            const SizedBox(height: 14),
          ],

          const Text(
            'Tên mạng Wi-Fi (SSID)',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: SignupTheme.figmaDark,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ssidController,
            focusNode: _ssidFocusNode,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: 'Nhập đúng tên Wi-Fi 2.4GHz nhà bạn',
              prefixIcon: const Icon(LucideIcons.wifi, size: 18),
              filled: true,
              fillColor: SignupTheme.figmaInputBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: SignupTheme.figmaBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: SignupTheme.figmaBorder),
              ),
            ),
          ),

          const Spacer(),
          const SizedBox(height: 16),

          SignupPrimaryButton(
            label: 'Tiếp tục',
            isEnabled: currentSsid.isNotEmpty,
            onTap: _submitWifiNetwork,
          ),
          const SizedBox(height: 8),
          SignupSecondaryButton(
            label: 'Nhập tên mạng thủ công',
            onTap: _showManualSsidDialog,
          ),
          if (widget.onSkip != null) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: widget.onSkip,
                child: const Text(
                  'Bỏ qua, cài đặt Wi-Fi sau',
                  style: TextStyle(fontSize: 13, color: SignupTheme.figmaMuted),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      );
    } else if (_step4SubPhase == 1) {
      // 4B: Nhập mật khẩu WiFi
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const AuthGuide(
            message: 'Nhập mật khẩu Wi-Fi để nút bấm kết nối internet nhé!',
            mood: GuideMood.guiding,
          ),
          const SizedBox(height: 24),
          const Text(
            'Nhập mật khẩu WiFi',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: SignupTheme.figmaDark,
              fontFamily: SignupTheme.fontFamily,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Kết nối nút nhấn với mạng nhà bạn.',
            style: TextStyle(
              fontSize: 15,
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

          // Network header card with "Đổi" button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: SignupTheme.figmaInputBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: SignupTheme.figmaBorder),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.wifi, color: SignupTheme.figmaBlue, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentSsid,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: SignupTheme.figmaDark,
                          fontFamily: SignupTheme.fontFamily,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        '2.4GHz',
                        style: TextStyle(fontSize: 12, color: SignupTheme.figmaMuted),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _step4SubPhase = 0),
                  child: const Text(
                    'Đổi',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: SignupTheme.figmaBlue,
                      fontFamily: SignupTheme.fontFamily,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          const Text(
            'Mật khẩu WiFi',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SignupTheme.figmaMuted,
              fontFamily: SignupTheme.fontFamily,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _wifiPasswordController,
            obscureText: _isWifiPasswordObscured,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: SignupTheme.figmaDark,
              fontFamily: SignupTheme.fontFamily,
            ),
            decoration: InputDecoration(
              hintText: 'Nhập mật khẩu WiFi',
              hintStyle: const TextStyle(color: SignupTheme.figmaMuted, fontSize: 15),
              filled: true,
              fillColor: SignupTheme.figmaInputBg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              suffixIcon: IconButton(
                icon: Icon(
                  _isWifiPasswordObscured ? LucideIcons.eyeOff : LucideIcons.eye,
                  color: SignupTheme.figmaMuted,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _isWifiPasswordObscured = !_isWifiPasswordObscured),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: SignupTheme.figmaBorder, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: SignupTheme.figmaBorder, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: SignupTheme.figmaBlue, width: 2),
              ),
            ),
          ),

          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SignupTheme.figmaInputBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SignupTheme.figmaBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LucideIcons.keyRound, color: SignupTheme.figmaMuted, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Nhập mật khẩu của mạng $currentSsid, không phải mật khẩu tài khoản.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: SignupTheme.figmaMuted,
                      height: 1.4,
                      fontFamily: SignupTheme.fontFamily,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 36),
          SignupPrimaryButton(
            label: 'Kết nối WiFi',
            isEnabled: _wifiPasswordController.text.isNotEmpty,
            onTap: _startWifiProvisioning,
          ),
          const SizedBox(height: 8),
          SignupSecondaryButton(
            label: 'Cần giúp đỡ',
            onTap: () => showSignupHelpBottomSheet(context),
          ),
          const SizedBox(height: 24),
        ],
      );
    } else {
      // 4C: Tiến trình thực tế 3 giai đoạn kết nối WiFi
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const AuthGuide(
            message: 'Đang nạp Wi-Fi và đồng bộ thiết bị lên hệ thống…',
            mood: GuideMood.waiting,
          ),
          const SizedBox(height: 24),
          const Text(
            'Đang kết nối WiFi...',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: SignupTheme.figmaDark,
              fontFamily: SignupTheme.fontFamily,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${widget.selectedDeviceName} → $currentSsid',
            style: const TextStyle(
              fontSize: 15,
              color: SignupTheme.figmaMuted,
              fontFamily: SignupTheme.fontFamily,
            ),
          ),
          const SizedBox(height: 28),

          _buildConnectionStageItem(
            title: 'Gửi thông tin WiFi tới thiết bị',
            subtitle: _wifiConnectProgressStage >= 1 ? 'Đã gửi' : 'Đang xử lý',
            isCompleted: _wifiConnectProgressStage >= 1,
            isInProgress: _wifiConnectProgressStage == 0,
          ),
          const SizedBox(height: 12),
          _buildConnectionStageItem(
            title: 'Xác thực phiên thiết bị',
            subtitle: _wifiConnectProgressStage >= 2
                ? 'Đã xác thực'
                : (_wifiConnectProgressStage == 1 ? 'Đang xử lý' : 'Chờ gửi WiFi'),
            isCompleted: _wifiConnectProgressStage >= 2,
            isInProgress: _wifiConnectProgressStage == 1,
          ),
          const SizedBox(height: 12),
          _buildConnectionStageItem(
            title: 'Đăng ký nút với tài khoản',
            subtitle: _wifiConnectProgressStage >= 3
                ? 'Thành công'
                : (_wifiConnectProgressStage == 2 ? 'Đang xử lý' : 'Chờ xác thực'),
            isCompleted: _wifiConnectProgressStage >= 3,
            isInProgress: _wifiConnectProgressStage == 2,
          ),

          const Spacer(),
          Container(
            height: 56,
            width: double.infinity,
            decoration: BoxDecoration(
              color: SignupTheme.figmaBlue,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.2,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Đang kết nối',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: SignupTheme.fontFamily,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SignupSecondaryButton(
            label: 'Cần giúp đỡ',
            onTap: () => showSignupHelpBottomSheet(context),
          ),
          const SizedBox(height: 16),
        ],
      );
    }
  }

  Widget _buildWifiItem({
    required String ssid,
    required String desc,
    required bool isSelected,
    required bool isSupported,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? SignupTheme.figmaBlueLight
              : (isSupported ? SignupTheme.figmaInputBg : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? SignupTheme.figmaBlue : SignupTheme.figmaBorder,
            width: isSelected ? 2 : 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.wifi,
              color: isSupported
                  ? (isSelected ? SignupTheme.figmaBlue : SignupTheme.figmaDark)
                  : SignupTheme.figmaMuted,
              size: 20,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ssid,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isSupported ? SignupTheme.figmaDark : SignupTheme.figmaMuted,
                      fontFamily: SignupTheme.fontFamily,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 13,
                      color: isSupported ? SignupTheme.figmaMuted : SignupTheme.figmaDanger,
                      fontFamily: SignupTheme.fontFamily,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.lock, color: SignupTheme.figmaMuted, size: 16),
            if (isSelected) ...[
              const SizedBox(width: 10),
              const Icon(LucideIcons.checkCircle2, color: SignupTheme.figmaBlue, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStageItem({
    required String title,
    required String subtitle,
    required bool isCompleted,
    required bool isInProgress,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isInProgress ? SignupTheme.figmaBlueLight : SignupTheme.figmaInputBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isInProgress ? SignupTheme.figmaBlueBorder : SignupTheme.figmaBorder,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          if (isCompleted)
            const Icon(LucideIcons.checkCircle2, color: SignupTheme.figmaSuccess, size: 24)
          else if (isInProgress)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: SignupTheme.figmaBlue, strokeWidth: 2.2),
            )
          else
            const Icon(LucideIcons.circleDashed, color: SignupTheme.figmaMuted, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: SignupTheme.figmaDark,
                    fontFamily: SignupTheme.fontFamily,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: isCompleted
                        ? SignupTheme.figmaSuccess
                        : (isInProgress ? SignupTheme.figmaBlue : SignupTheme.figmaMuted),
                    fontWeight: isCompleted || isInProgress ? FontWeight.w600 : FontWeight.normal,
                    fontFamily: SignupTheme.fontFamily,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
