import '../sample_a.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Thẻ Nút Thông Minh nhỏ gọn, hiện đại với Logo sản phẩm nhỏ tinh tế chuẩn Grab Blue.
class SmartButtonCard extends StatelessWidget {
  final String id;
  final String name;
  final String? room;
  final String? storeName;
  final String product;
  final String price;
  final int battery;
  final String? imageUrl;
  final String badgeText;
  final String state; // 'idle', 'ordering', 'ordered'
  final VoidCallback? onOrder;
  final VoidCallback? onSettings;

  const SmartButtonCard({
    super.key,
    required this.id,
    required this.name,
    this.room,
    this.storeName,
    required this.product,
    required this.price,
    required this.battery,
    this.imageUrl,
    this.badgeText = '20L',
    this.state = 'idle',
    this.onOrder,
    this.onSettings,
  });

  String _formatPrice(String raw) {
    final clean = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final numVal = int.tryParse(clean);
    if (numVal != null && numVal > 0) {
      final s = numVal.toString();
      final buffer = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
        buffer.write(s[i]);
      }
      return '${buffer.toString()} ₫';
    }
    return raw.isNotEmpty ? raw : '0 ₫';
  }

  @override
  Widget build(BuildContext context) {
    final ordering = state == 'ordering';
    final ordered = state == 'ordered';
    final url = imageUrl?.trim();
    final displayPrice = _formatPrice(price);
    final clampedBattery = battery.clamp(0, 100);
    final isLowBattery = clampedBattery <= 20;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── HÀNG ĐẦU: Tên nút & Nút cài đặt ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFDBEAFE)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E40AF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onSettings?.call();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    LucideIcons.slidersHorizontal,
                    size: 15,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── HÀNG GIỮA: Logo nhỏ + Tên món sản phẩm ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo sản phẩm nhỏ gọn (50x50) bo góc đẹp mắt
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: url != null && url.isNotEmpty
                      ? Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(
                              LucideIcons.packageCheck,
                              size: 24,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        )
                      : const Center(
                          child: Icon(
                            LucideIcons.packageCheck,
                            size: 24,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                ),
              ),

              const SizedBox(width: 10),

              // Tên sản phẩm & Cửa hàng
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      storeName?.trim().isNotEmpty == true
                          ? storeName!
                          : 'Đại lý Nước & Gas Gia Định',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── GIÁ TIỀN & THÔNG SỐ PIN ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                displayPrice,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF2563EB),
                  letterSpacing: -0.3,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isLowBattery ? LucideIcons.batteryLow : LucideIcons.batteryMedium,
                    size: 13,
                    color: isLowBattery ? const Color(0xFFEF4444) : const Color(0xFF16A34A),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '$clampedBattery%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isLowBattery ? const Color(0xFFEF4444) : const Color(0xFF059669),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 5),

          // Mini progress bar pin
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: clampedBattery / 100,
              minHeight: 4,
              backgroundColor: const Color(0xFFF1F5F9),
              color: isLowBattery ? const Color(0xFFEF4444) : const Color(0xFF10B981),
            ),
          ),

          const SizedBox(height: 10),

          // ── NÚT BẤM ĐẶT HÀNG: LUÔN SẴN SÀNG, BẤM 1 CHẠM ──
          ElevatedButton(
            onPressed: ordering
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    onOrder?.call();
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size.fromHeight(38),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (ordering)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else ...[
                  const Icon(LucideIcons.zap, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    ordered ? 'Đã đặt ⚡' : 'Đặt 1 chạm',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
