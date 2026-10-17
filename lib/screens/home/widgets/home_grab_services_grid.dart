import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../main_layout.dart';
import '../../../widgets/modals/connect_device_sheet.dart';
import '../../customer_buttons_screen.dart';

/// Floating Quick-Action Dock (2 rows x 3 columns) synced 100% with Web Customer navigation + BLE Pairing.
class HomeGrabServicesGrid extends StatelessWidget {
  final VoidCallback? onScrollToStores;
  final String role;

  const HomeGrabServicesGrid({
    super.key,
    this.onScrollToStores,
    this.role = 'CUSTOMER',
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin =
        role == 'SUPER_ADMIN' || role == 'SYSTEM_ADMIN' || role == 'ADMIN';
    final isSystemStaff = role == 'SYSTEM_STAFF';
    final isStoreOwner =
        role == 'STORE_OWNER' ||
        role == 'STORE_MANAGER' ||
        role == 'STORE_STAFF' ||
        role == 'STAFF_ORDER';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: isSystemStaff
          ? Row(
              children: [
                Expanded(
                  child: _GrabServiceItem(
                    icon: LucideIcons.cpu,
                    label: 'Kho nút',
                    iconColor: const Color(0xFF0E6BA8),
                    bgColor: const Color(0xFFE0F2FE),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      MainLayout.switchToTab(context, 1);
                    },
                  ),
                ),
                Expanded(
                  child: _GrabServiceItem(
                    icon: LucideIcons.shieldCheck,
                    label: 'Bảo hành',
                    iconColor: const Color(0xFF0E7490),
                    bgColor: const Color(0xFFECFEFF),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      MainLayout.switchToTab(context, 2);
                    },
                  ),
                ),
                Expanded(
                  child: _GrabServiceItem(
                    icon: LucideIcons.rotateCcw,
                    label: 'Thu hồi',
                    iconColor: const Color(0xFFD97706),
                    bgColor: const Color(0xFFFFFBEB),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      MainLayout.switchToTab(context, 3);
                    },
                  ),
                ),
                Expanded(
                  child: _GrabServiceItem(
                    icon: LucideIcons.bluetooth,
                    label: 'Quét BLE',
                    iconColor: const Color(0xFF2563EB),
                    bgColor: const Color(0xFFEFF6FF),
                    badgeText: 'BLE',
                    badgeColor: const Color(0xFF2563EB),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ConnectDeviceSheet.showAndRefresh(context);
                    },
                  ),
                ),
              ],
            )
          : isAdmin
          ? Row(
              children: [
                Expanded(
                  child: _GrabServiceItem(
                    icon: LucideIcons.store,
                    label: 'Cửa hàng',
                    iconColor: const Color(0xFF287DA8),
                    bgColor: const Color(0xFFF0F9FF),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onScrollToStores?.call();
                    },
                  ),
                ),
                Expanded(
                  child: _GrabServiceItem(
                    icon: LucideIcons.cpu,
                    label: 'Kho nút',
                    iconColor: const Color(0xFF0E6BA8),
                    bgColor: const Color(0xFFE0F2FE),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      MainLayout.switchToTab(context, 1);
                    },
                  ),
                ),
                Expanded(
                  child: _GrabServiceItem(
                    icon: LucideIcons.receiptText,
                    label: 'Đơn hàng',
                    iconColor: const Color(0xFFD97706),
                    bgColor: const Color(0xFFFFFBEB),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      MainLayout.switchToTab(context, 2);
                    },
                  ),
                ),
                Expanded(
                  child: _GrabServiceItem(
                    icon: LucideIcons.userRound,
                    label: 'Tài khoản',
                    iconColor: const Color(0xFF4F46E5),
                    bgColor: const Color(0xFFEEF2FF),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      MainLayout.switchToTab(context, 3);
                    },
                  ),
                ),
              ],
            )
          : isStoreOwner
              ? Row(
                  children: [
                    Expanded(
                      child: _GrabServiceItem(
                        icon: LucideIcons.receiptText,
                        label: 'Đơn hàng',
                        iconColor: const Color(0xFFD97706),
                        bgColor: const Color(0xFFFFFBEB),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          MainLayout.switchToTab(context, 3);
                        },
                      ),
                    ),
                    Expanded(
                      child: _GrabServiceItem(
                        icon: LucideIcons.package,
                        label: 'Sản phẩm',
                        iconColor: const Color(0xFF059669),
                        bgColor: const Color(0xFFECFDF5),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          MainLayout.switchToTab(context, 1);
                        },
                      ),
                    ),
                    Expanded(
                      child: _GrabServiceItem(
                        icon: LucideIcons.cpu,
                        label: 'Nút IoT',
                        iconColor: const Color(0xFF0E6BA8),
                        bgColor: const Color(0xFFE0F2FE),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          MainLayout.switchToTab(context, 2);
                        },
                      ),
                    ),
                    Expanded(
                      child: _GrabServiceItem(
                        icon: LucideIcons.bluetooth,
                        label: 'Ghép BLE',
                        iconColor: const Color(0xFF2563EB),
                        bgColor: const Color(0xFFEFF6FF),
                        badgeText: 'BLE',
                        badgeColor: const Color(0xFF2563EB),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          ConnectDeviceSheet.showAndRefresh(context);
                        },
                      ),
                    ),
                  ],
                )
              : Column(
        children: [
          // ── HÀNG 1: Mua sắm | Nút của tôi | Thuê nút bấm ──
          Row(
            children: [
              Expanded(
                child: _GrabServiceItem(
                  icon: LucideIcons.shoppingCart,
                  label: 'Mua sắm',
                  iconColor: const Color(0xFF287DA8),
                  bgColor: const Color(0xFFF0F9FF),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onScrollToStores?.call();
                  },
                ),
              ),
              Expanded(
                child: _GrabServiceItem(
                  icon: LucideIcons.smartphone,
                  label: 'Nút của tôi',
                  iconColor: const Color(0xFF0E6BA8),
                  bgColor: const Color(0xFFE0F2FE),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    MainLayout.switchToTab(context, 1);
                  },
                ),
              ),
              Expanded(
                child: _GrabServiceItem(
                  icon: LucideIcons.cpu,
                  label: 'Thuê nút bấm',
                  iconColor: const Color(0xFF059669),
                  bgColor: const Color(0xFFECFDF5),
                  badgeText: 'Hot',
                  badgeColor: const Color(0xFF059669),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CustomerButtonsScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── HÀNG 2: Quét Bluetooth | Đơn hàng | Hồ sơ ──
          Row(
            children: [
              Expanded(
                child: _GrabServiceItem(
                  icon: LucideIcons.bluetooth,
                  label: 'Quét Bluetooth',
                  iconColor: const Color(0xFF2563EB),
                  bgColor: const Color(0xFFEFF6FF),
                  badgeText: 'BLE',
                  badgeColor: const Color(0xFF2563EB),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ConnectDeviceSheet.showAndRefresh(context);
                  },
                ),
              ),
              Expanded(
                child: _GrabServiceItem(
                  icon: LucideIcons.receiptText,
                  label: 'Đơn hàng',
                  iconColor: const Color(0xFFD97706),
                  bgColor: const Color(0xFFFFFBEB),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    MainLayout.switchToTab(context, 2);
                  },
                ),
              ),
              Expanded(
                child: _GrabServiceItem(
                  icon: LucideIcons.userRound,
                  label: 'Tài khoản',
                  iconColor: const Color(0xFF4F46E5),
                  bgColor: const Color(0xFFEEF2FF),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    MainLayout.switchToTab(context, 3);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GrabServiceItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color bgColor;
  final String? badgeText;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _GrabServiceItem({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.bgColor,
    this.badgeText,
    this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: iconColor.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Center(
                    child: Icon(icon, color: iconColor, size: 23),
                  ),
                ),
                if (badgeText != null)
                  Positioned(
                    top: -5,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5.5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor ?? const Color(0xFF287DA8),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        badgeText!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
