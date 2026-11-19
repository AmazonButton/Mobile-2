import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Premium curved ocean-blue top header banner for HomeScreen.
/// Displays location picker pill, notification bell, user avatar, greeting, and live device count.
class HomeHeaderCard extends StatelessWidget {
  final File? userAvatar;
  final String? userAvatarUrl;
  final String userInitials;
  final String userShortName;
  final String userAddress;
  final int deviceCount;
  final String role;
  final String? storeName;
  final String? storeAddress;
  final VoidCallback onAccountTap;
  final VoidCallback? onNotificationTap;
  final VoidCallback onLocationTap;
  final int unreadNotificationCount;

  const HomeHeaderCard({
    super.key,
    this.userAvatar,
    this.userAvatarUrl,
    required this.userInitials,
    required this.userShortName,
    required this.userAddress,
    this.deviceCount = 0,
    this.role = 'CUSTOMER',
    this.storeName,
    this.storeAddress,
    required this.onAccountTap,
    this.onNotificationTap,
    required this.onLocationTap,
    this.unreadNotificationCount = 0,
  });

  Widget _buildAvatar() {
    ImageProvider? image;
    if (userAvatar != null) {
      image = FileImage(userAvatar!);
    } else if (userAvatarUrl != null && userAvatarUrl!.trim().isNotEmpty) {
      image = NetworkImage(userAvatarUrl!.trim());
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.2),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: image != null
          ? Image(image: image, fit: BoxFit.cover)
          : Center(
              child: Text(
                userInitials.isNotEmpty ? userInitials : 'U',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final isAdmin =
        role == 'SUPER_ADMIN' || role == 'SYSTEM_ADMIN' || role == 'ADMIN';
    final isSystemStaff = role == 'SYSTEM_STAFF';
    final isStoreOwner =
        role == 'STORE_OWNER' ||
        role == 'STORE_MANAGER' ||
        role == 'STORE_STAFF' ||
        role == 'STAFF_ORDER';

    final gradientColors = isAdmin
        ? const [
            Color(0xFF1E1B4B),
            Color(0xFF312E81),
            Color(0xFF1D4ED8),
          ]
        : isSystemStaff
            ? const [
                Color(0xFF0F172A),
                Color(0xFF155E75),
                Color(0xFF0E6BA8),
              ]
            : isStoreOwner
                ? const [
                    Color(0xFF0F172A),
                    Color(0xFF0F4C75),
                    Color(0xFF0E7490),
                  ]
                : const [
                    Color(0xFF0E6BA8),
                    Color(0xFF287DA8),
                    Color(0xFF3894C4),
                  ];

    final pillIcon = isAdmin
        ? LucideIcons.shieldCheck
        : isSystemStaff
            ? LucideIcons.wrench
            : isStoreOwner
                ? LucideIcons.store
                : LucideIcons.mapPin;
    final pillEyebrow = isAdmin
        ? 'Cổng quản trị'
        : isSystemStaff
            ? 'Nhân viên hệ thống'
            : isStoreOwner
                ? 'Đại lý đang hoạt động'
                : 'Giao đến';
    final pillTitle = isAdmin
        ? 'Hệ thống SmartOrder IoT'
        : isSystemStaff
            ? 'Kho nút & Bảo hành kỹ thuật'
            : isStoreOwner
                ? (storeAddress?.trim().isNotEmpty == true
                    ? storeAddress!.trim()
                    : (storeName?.trim().isNotEmpty == true
                        ? storeName!.trim()
                        : 'Quản lý đại lý'))
                : (userAddress.trim().isEmpty
                    ? 'Chọn địa chỉ giao hàng'
                    : userAddress);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Stack(
        children: [
          // Subtle decorative soft glow circles
          Positioned(
            top: -36,
            right: -28,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            left: -40,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, topPadding + 14, 20, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Role Context Pill + Notification + Avatar
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          onLocationTap();
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                pillIcon,
                                color: Colors.white,
                                size: 17,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pillEyebrow,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white.withValues(alpha: 0.8),
                                      ),
                                    ),
                                    Text(
                                      pillTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                LucideIcons.chevronRight,
                                size: 16,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Notification Button
                    InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onNotificationTap?.call();
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Center(
                          child: Badge(
                            isLabelVisible: unreadNotificationCount > 0,
                            backgroundColor: const Color(0xFFEF4444),
                            child: const Icon(
                              LucideIcons.bell,
                              color: Colors.white,
                              size: 19,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // User Avatar
                    InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onAccountTap();
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: _buildAvatar(),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // Greeting & Headline (Role-aware)
                Text(
                  'Chào ${userShortName.trim().isEmpty ? 'bạn' : userShortName} 👋',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isAdmin
                      ? 'Trung tâm điều hành'
                      : isSystemStaff
                          ? 'Vận hành thiết bị IoT'
                          : isStoreOwner
                              ? (storeName?.isNotEmpty == true
                                  ? storeName!
                                  : 'Quản lý cửa hàng')
                              : 'Hôm nay nhà mình cần gì?',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4ADE80),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        isAdmin
                            ? 'Quản trị hệ thống • $deviceCount thiết bị'
                            : isSystemStaff
                                ? 'Nhân viên hệ thống • $deviceCount nút bấm'
                                : isStoreOwner
                                    ? 'Chủ cửa hàng • $deviceCount nút đang hoạt động'
                                    : (deviceCount > 0
                                        ? '$deviceCount nút bấm sẵn sàng • Đặt hàng 1 chạm'
                                        : 'Đặt hàng nhu yếu phẩm 1 chạm siêu tốc'),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
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
