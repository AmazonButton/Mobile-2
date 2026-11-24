import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/api_client.dart';
import '../services/auth_api_service.dart';

/// Màn hình Xác minh địa chỉ email (POST /auth/verify-email & /auth/resend-verification).
class VerifyEmailScreen extends StatefulWidget {
  final String initialEmail;

  const VerifyEmailScreen({super.key, this.initialEmail = ''});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _auth = AuthApiService();
  late final TextEditingController _emailCtrl = TextEditingController(
    text: widget.initialEmail,
  );
  final TextEditingController _tokenCtrl = TextEditingController();
  bool _sending = false;
  bool _verifying = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            error ? const Color(0xFFDC2626) : const Color(0xFF059669),
        content: Text(msg),
      ),
    );
  }

  Future<void> _resend() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _snack('Vui lòng nhập địa chỉ email hợp lệ.', error: true);
      return;
    }
    setState(() => _sending = true);
    try {
      await _auth.resendVerification(email);
      _snack('Đã gửi mã xác minh đến hộp thư của bạn.');
    } catch (e) {
      _snack(
        e is ApiException ? e.message : 'Không thể gửi lại mã xác minh.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verify() async {
    final email = _emailCtrl.text.trim();
    final token = _tokenCtrl.text.trim();
    if (email.isEmpty || token.isEmpty) {
      _snack('Vui lòng nhập đầy đủ email và mã xác minh.', error: true);
      return;
    }
    setState(() => _verifying = true);
    try {
      final res = await _auth.verifyEmail(email: email, token: token);
      if (!mounted) return;
      _snack(res['message']?.toString() ?? 'Xác minh email thành công!');
      Navigator.pop(context, true);
    } catch (e) {
      _snack(
        e is ApiException ? e.message : 'Mã xác minh không đúng hoặc đã hết hạn.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Xác minh email',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  LucideIcons.mailCheck,
                  size: 40,
                  color: Color(0xFF0E6BA8),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Bảo vệ tài khoản bằng email chính chủ',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Bấm gửi mã xác minh đến email của bạn rồi nhập mã nhận được để hoàn tất.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Địa chỉ email',
                    prefixIcon: Icon(LucideIcons.mail, size: 18),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _sending ? null : _resend,
                  icon: const Icon(LucideIcons.send, size: 16),
                  label: Text(
                    _sending ? 'Đang gửi mã...' : 'Gửi mã xác minh qua email',
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _tokenCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mã xác minh (Token)',
                    prefixIcon: Icon(LucideIcons.keyRound, size: 18),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _verifying ? null : _verify,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0E6BA8),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _verifying ? 'Đang xác minh...' : 'Xác minh email',
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
