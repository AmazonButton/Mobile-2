import '../widgets/sample_a.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import 'main_layout.dart';
import 'shop_stores_screen.dart';
import '../widgets/smart_order_tour.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/device_model.dart';
import '../providers/device_provider.dart';
import '../providers/order_provider.dart';
import '../providers/user_provider.dart';
import '../providers/address_provider.dart';
import '../providers/notification_provider.dart';
import '../services/system_staff_api_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/modals/notification_sheet.dart';
import '../widgets/modals/connect_device_sheet.dart';
import '../widgets/address_picker_sheet.dart';
import 'home/widgets/widgets.dart';

typedef HomePage = HomeScreen;

/// Màn hình Trang chủ - Orchestrator quản lý luồng dữ liệu, làm mới và điều hướng.
class HomeScreen extends StatefulWidget {
  final bool showBottomNav;
  final SmartOrderTour? tour;

  const HomeScreen({super.key, this.showBottomNav = false, this.tour});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final UserProfileService _userService = UserProfileService();

  UserProvider? get _userProvider {
    try {
      return Provider.of<UserProvider>(context);
    } catch (_) {
      return null;
    }
  }

  String get _userName => _userProvider?.name ?? _userService.name;
  String get _userShortName =>
      _userProvider?.shortName ?? _userService.shortName;
  String get _userEmail => _userProvider?.email ?? _userService.email;
  String get _userAddress {
    final address = context.read<AddressProvider>().currentAddressDisplay;
    return address.isEmpty ? 'Thêm địa chỉ giao hàng' : address;
  }

  String get _userInitials => _userProvider?.initials ?? _userService.initials;
  String? get _userAvatarUrl =>
      _userProvider?.avatarUrl ?? _userService.avatarUrl;
  File? get _userAvatar => _userProvider?.avatarFile ?? _userService.avatarFile;

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  late AnimationController _toastController;
  late Animation<Offset> _toastSlideAnimation;
  late Animation<double> _toastFadeAnimation;
  late Animation<double> _toastScaleAnimation;
  String? _toastMessage;
  VoidCallback? _toastOnUndo;
  Timer? _toastTimer;
  final _homeScrollController = ScrollController();
  final _storesSectionKey = GlobalKey();
  bool _showCompactHeader = false;
  Map<String, dynamic>? _staffFleetStats;

  Future<void> _loadStaffFleetStats() async {
    try {
      final stats = await SystemStaffApiService().getFleetStats();
      if (mounted) {
        setState(() => _staffFleetStats = stats);
      }
    } catch (_) {}
  }

  int _readIntStat(Map<String, dynamic>? m, List<String> keys, int fallback) {
    if (m == null) return fallback;
    for (final k in keys) {
      final v = m[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final parsed = int.tryParse(v);
        if (parsed != null) return parsed;
      }
    }
    return fallback;
  }

  void _onHomeScroll() {
    final compact = _homeScrollController.offset > 170;
    if (compact != _showCompactHeader) {
      setState(() => _showCompactHeader = compact);
    }
  }

  void _openShopStores() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShopStoresScreen(tour: widget.tour),
      ),
    );
  }

  Widget _buildStoreOverview(List<DeviceModel> devices) {
    final orders = context.watch<OrderProvider?>()?.orders ?? const [];
    final pendingCount = orders
        .where((o) => o.rawStatus.toUpperCase() == 'PENDING')
        .length;
    final activeCount = orders
        .where((o) => [
              'CONFIRMED',
              'PROCESSING',
              'PREPARING',
              'READY_FOR_DELIVERY',
              'SHIPPING',
              'OUT_FOR_DELIVERY',
              'DELIVERING',
            ].contains(o.rawStatus.toUpperCase()))
        .length;
    final completedCount = orders
        .where((o) => ['COMPLETED', 'DELIVERED']
            .contains(o.rawStatus.toUpperCase()))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Store Operations Hero Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F172A), Color(0xFF0E6BA8)],
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(LucideIcons.store, size: 16, color: Color(0xFF7DD3FC)),
                  SizedBox(width: 6),
                  Text(
                    'Bảng điều phối đại lý',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFBAE6FD),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _userProvider?.storeName?.isNotEmpty == true
                    ? _userProvider!.storeName!
                    : 'Không gian quản lý cửa hàng',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tiếp nhận đơn hàng một chạm từ khách hàng, kiểm tra thiết bị IoT và quản lý giao hàng.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => MainLayout.switchToTab(context, 3),
                      icon: const Icon(LucideIcons.shoppingBag, size: 15),
                      label: const Text(
                        'Đơn trực tiếp',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0E6BA8),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => MainLayout.switchToTab(context, 1),
                      icon: const Icon(LucideIcons.package, size: 15),
                      label: const Text(
                        'Sản phẩm & kho',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Tổng quan vận hành đơn hàng',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildTrustPill(
              icon: LucideIcons.clock,
              title: '$pendingCount đơn',
              subtitle: 'Chờ tiếp nhận',
              color: const Color(0xFFD97706),
            ),
            const SizedBox(width: 10),
            _buildTrustPill(
              icon: LucideIcons.truck,
              title: '$activeCount đơn',
              subtitle: 'Đang xử lý',
              color: const Color(0xFF0E6BA8),
            ),
            const SizedBox(width: 10),
            _buildTrustPill(
              icon: LucideIcons.checkCircle2,
              title: '$completedCount đơn',
              subtitle: 'Đã hoàn tất',
              color: const Color(0xFF059669),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildLandingStepCard(
          step: 'KHO',
          icon: LucideIcons.package,
          title: 'Sản phẩm & tồn kho của đại lý',
          subtitle: 'Xem toàn bộ mặt hàng, giá bán và tồn kho đồng bộ trực tiếp với Web.',
          onTap: () => MainLayout.switchToTab(context, 1),
        ),
        const SizedBox(height: 10),
        _buildLandingStepCard(
          step: 'IoT',
          icon: LucideIcons.cpu,
          title: 'Danh sách nút bấm (${devices.length} thiết bị)',
          subtitle: 'Kiểm tra trạng thái kết nối, pin và sản phẩm gán của từng nút tại đại lý.',
          onTap: () => MainLayout.switchToTab(context, 2),
        ),
        const SizedBox(height: 10),
        _buildLandingStepCard(
          step: 'ĐƠN',
          icon: LucideIcons.receiptText,
          title: 'Quản lý đơn hàng trực tiếp (${orders.length} đơn)',
          subtitle: 'Tiếp nhận, chuẩn bị hàng và cập nhật trạng thái giao cho khách.',
          onTap: () => MainLayout.switchToTab(context, 3),
        ),
      ],
    );
  }

  Widget _buildSystemStaffOverview(List<DeviceModel> devices) {
    final totalDevices = _readIntStat(
      _staffFleetStats,
      ['total', 'totalDevices', 'totalButtons'],
      devices.length,
    );
    final onlineCount = _readIntStat(
      _staffFleetStats,
      ['online', 'active', 'onlineDevices'],
      devices.where((d) => d.isOnline).length,
    );
    final lowBatteryCount = _readIntStat(
      _staffFleetStats,
      ['lowBattery', 'lowBatteryCount'],
      devices.where((d) => d.battery <= 20).length,
    );
    final unassignedCount = _readIntStat(
      _staffFleetStats,
      ['unassigned', 'inWarehouse', 'available'],
      0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F172A), Color(0xFF155E75), Color(0xFF0E6BA8)],
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(LucideIcons.wrench, size: 16, color: Color(0xFF67E8F9)),
                  SizedBox(width: 6),
                  Text(
                    'System Staff • Trung tâm kỹ thuật IoT',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFA5F3FC),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Kho nút bấm, Bảo hành & Thu hồi',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Nhập kho, cấp phát nút cho đại lý, triển khai mẫu hàng loạt, xử lý bảo hành 1-1 và kiểm tra nút khách trả.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => MainLayout.switchToTab(context, 1),
                      icon: const Icon(LucideIcons.cpu, size: 15),
                      label: const Text(
                        'Kho nút bấm',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0E6BA8),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => MainLayout.switchToTab(context, 2),
                      icon: const Icon(LucideIcons.shieldCheck, size: 15),
                      label: const Text(
                        'Bảo hành',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Tình trạng đội nút bấm toàn sàn',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildTrustPill(
              icon: LucideIcons.cpu,
              title: '$totalDevices nút',
              subtitle: unassignedCount > 0
                  ? '$unassignedCount trong kho'
                  : 'Tổng kho IoT',
              color: const Color(0xFF0E6BA8),
            ),
            const SizedBox(width: 10),
            _buildTrustPill(
              icon: LucideIcons.wifi,
              title: '$onlineCount online',
              subtitle: 'Đang hoạt động',
              color: const Color(0xFF059669),
            ),
            const SizedBox(width: 10),
            _buildTrustPill(
              icon: LucideIcons.batteryLow,
              title: '$lowBatteryCount pin yếu',
              subtitle: 'Cần kiểm tra',
              color: const Color(0xFFD97706),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildLandingStepCard(
          step: 'KHO',
          icon: LucideIcons.cpu,
          title: 'Kho nút & Vận hành thiết bị',
          subtitle:
              'Đăng ký nút mới, sinh lô, nhập CSV, ghép nối, đổi WiFi, bật/tắt, cấu hình hành vi, telemetry & reset.',
          onTap: () => MainLayout.switchToTab(context, 1),
        ),
        const SizedBox(height: 10),
        _buildLandingStepCard(
          step: 'MẪU',
          icon: LucideIcons.layers,
          title: 'Cấp phát cửa hàng & Mẫu cấu hình',
          subtitle:
              'Chuyển nút về custodyStoreId của cửa hàng, xem tồn kho đại lý và triển khai mẫu tối đa 100 nút/lần.',
          onTap: () => MainLayout.switchToTab(context, 1),
        ),
        const SizedBox(height: 10),
        _buildLandingStepCard(
          step: 'BH',
          icon: LucideIcons.shieldCheck,
          title: 'Bảo hành kỹ thuật (Đổi 1-1 & Khóa nút)',
          subtitle:
              'Xử lý phiếu bảo hành, đổi nút kế thừa hợp đồng thuê, khóa nút lỗi gửi Admin duyệt hoàn cọc.',
          onTap: () => MainLayout.switchToTab(context, 2),
        ),
        const SizedBox(height: 10),
        _buildLandingStepCard(
          step: 'THU',
          icon: LucideIcons.rotateCcw,
          title: 'Thu hồi nút thuê & Xác nhận nhận lại',
          subtitle:
              'Kiểm tra tình trạng vật lý nút khách trả và xác nhận nhập lại kho trung tâm.',
          onTap: () => MainLayout.switchToTab(context, 3),
        ),
      ],
    );
  }

  Widget _buildAdminOverview(List<DeviceModel> devices) {
    final orders = context.watch<OrderProvider?>()?.orders ?? const [];
    final pendingOrders = orders
        .where((o) => o.rawStatus.toUpperCase() == 'PENDING')
        .length;
    final completedOrders = orders
        .where((o) => ['COMPLETED', 'DELIVERED']
            .contains(o.rawStatus.toUpperCase()))
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E1B4B), Color(0xFF1D4ED8)],
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(LucideIcons.shieldCheck, size: 16, color: Color(0xFF93C5FD)),
                  SizedBox(width: 6),
                  Text(
                    'Admin Hub • Toàn hệ thống',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFBFDBFE),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Trung tâm điều hành SmartOrder',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Giám sát cửa hàng đối tác, kho thiết bị nút bấm IoT và luồng đơn hàng thời gian thực.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _buildTrustPill(
              icon: LucideIcons.cpu,
              title: '${devices.length} nút',
              subtitle: 'Kho thiết bị',
              color: const Color(0xFF4338CA),
            ),
            const SizedBox(width: 10),
            _buildTrustPill(
              icon: LucideIcons.clock,
              title: '$pendingOrders chờ',
              subtitle: '${orders.length} tổng đơn',
              color: const Color(0xFFD97706),
            ),
            const SizedBox(width: 10),
            _buildTrustPill(
              icon: LucideIcons.checkCircle2,
              title: '$completedOrders xong',
              subtitle: 'Đã hoàn tất',
              color: const Color(0xFF059669),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildLandingStepCard(
          step: '01',
          icon: LucideIcons.store,
          title: 'Danh sách cửa hàng hoạt động',
          subtitle: 'Xem các đại lý đang mở bán và danh mục sản phẩm.',
          onTap: _openShopStores,
        ),
        const SizedBox(height: 10),
        _buildLandingStepCard(
          step: '02',
          icon: LucideIcons.cpu,
          title: 'Kho nút bấm toàn hệ thống (${devices.length} thiết bị)',
          subtitle: 'Kiểm tra thiết bị, trạng thái hoạt động và ghép nối.',
          onTap: () => MainLayout.switchToTab(context, 1),
        ),
        const SizedBox(height: 10),
        _buildLandingStepCard(
          step: '03',
          icon: LucideIcons.receiptText,
          title: 'Giám sát đơn hàng toàn sàn (${orders.length} đơn)',
          subtitle: 'Theo dõi trạng thái xử lý, giao vận và lịch sử thanh toán.',
          onTap: () => MainLayout.switchToTab(context, 2),
        ),
      ],
    );
  }

  Widget _buildLandingShowcase() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Hero Showcase Banner (Landing Page style)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F172A), Color(0xFF0E6BA8)],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0E6BA8).withValues(alpha: 0.2),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.sparkles, size: 13, color: Color(0xFF7DD3FC)),
                    SizedBox(width: 6),
                    Text(
                      'SmartOrder IoT • Đặt hàng 1 chạm',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Hết nước, hết gas?\nBấm 1 chạm — Giao tận cửa!',
                style: TextStyle(
                  fontSize: 20,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Kết nối nút bấm thông minh SmartOrder với đại lý uy tín quanh nhà. Không cần mở app, chỉ 1 lần nhấn là giao trong 15–25 phút.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _openShopStores,
                      icon: const Icon(LucideIcons.shoppingBag, size: 16),
                      label: const Text(
                        'Mua sắm ngay',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0E6BA8),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => ConnectDeviceSheet.showAndRefresh(context),
                      icon: const Icon(LucideIcons.bluetooth, size: 16),
                      label: const Text(
                        'Ghép nút BLE',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 2. Trust / Value Highlights Strip
        Row(
          children: [
            _buildTrustPill(
              icon: LucideIcons.zap,
              title: '15–25 phút',
              subtitle: 'Giao siêu tốc',
              color: const Color(0xFF0E6BA8),
            ),
            const SizedBox(width: 10),
            _buildTrustPill(
              icon: LucideIcons.truck,
              title: 'Freeship 5km',
              subtitle: 'Đại lý gần nhà',
              color: const Color(0xFF059669),
            ),
            const SizedBox(width: 10),
            _buildTrustPill(
              icon: LucideIcons.shieldCheck,
              title: 'Bảo mật IoT',
              subtitle: 'HMAC-SHA256',
              color: const Color(0xFF4F46E5),
            ),
          ],
        ),

        const SizedBox(height: 22),

        // 3. Cách hoạt động (3 bước Landing)
        const Text(
          'Cách hoạt động siêu đơn giản',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Chỉ 3 bước để tự động hóa nhu yếu phẩm trong nhà',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 14),
        _buildLandingStepCard(
          step: '01',
          icon: LucideIcons.store,
          title: 'Chọn cửa hàng & sản phẩm quen dùng',
          subtitle: 'Nước uống 20L, bình gas, gạo ST25 từ đại lý chính hãng quanh khu vực.',
          onTap: _openShopStores,
        ),
        const SizedBox(height: 10),
        _buildLandingStepCard(
          step: '02',
          icon: LucideIcons.bluetoothConnected,
          title: 'Ghép nối nút bấm qua Bluetooth',
          subtitle: 'Bấm nhanh 5 lần vào nút vật lý, quét BLE và nạp Wi-Fi 2.4GHz trong 30 giây.',
          onTap: () => ConnectDeviceSheet.showAndRefresh(context),
        ),
        const SizedBox(height: 10),
        _buildLandingStepCard(
          step: '03',
          icon: LucideIcons.pointer,
          title: 'Bấm 1 chạm — Giao tận cửa',
          subtitle: 'Nhấn nhẹ nút bấm trên tường hoặc trong mục "Nút của tôi", đơn tạo tự động tức thì.',
          onTap: () => MainLayout.switchToTab(context, 1),
        ),
      ],
    );
  }

  Widget _buildTrustPill({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandingStepCard({
    required String step,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 20, color: const Color(0xFF0E6BA8)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0E6BA8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          step,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(LucideIcons.chevronRight, size: 17, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  final Map<String, String> _buttonStateMap = {
    'btn-1': 'idle',
    'btn-2': 'idle',
    'btn-3': 'idle',
  };
  late final List<DeviceModel> _fallbackDevices = List.from(
    DeviceModel.sampleDevices,
  );

  @override
  void initState() {
    super.initState();
    _homeScrollController.addListener(_onHomeScroll);
    _userService.addListener(_onProfileChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      UserProvider? userProv;
      try {
        userProv = Provider.of<UserProvider>(context, listen: false);
        await userProv.loadProfile();
      } catch (_) {}
      if (!mounted) return;
      final isStaff = userProv?.isSystemStaff ?? false;
      final isCustomer = userProv?.isCustomer ?? false;

      if (isStaff) {
        _loadStaffFleetStats();
      }
      try {
        Provider.of<DeviceProvider>(context, listen: false).loadDevices();
      } catch (_) {}
      if (!isStaff) {
        try {
          final orderProv = Provider.of<OrderProvider>(context, listen: false);
          orderProv.loadOrders().then((_) {
            try {
              if (mounted) {
                Provider.of<NotificationProvider>(
                  context,
                  listen: false,
                ).syncOrders(orderProv.orders);
              }
            } catch (_) {}
          });
        } catch (_) {}
      }
      if (isCustomer) {
        try {
          Provider.of<AddressProvider>(context, listen: false).loadAddresses();
        } catch (_) {}
      }
      try {
        Provider.of<NotificationProvider>(
          context,
          listen: false,
        ).loadNotifications();
      } catch (_) {}
    });

    _toastController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      reverseDuration: const Duration(milliseconds: 280),
    );
    _toastSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 1.5), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _toastController,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeIn,
          ),
        );
    _toastFadeAnimation = CurvedAnimation(
      parent: _toastController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _toastScaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _toastController,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      ),
    );
  }

  @override
  void dispose() {
    _userService.removeListener(_onProfileChanged);
    _toastController.dispose();
    _homeScrollController.dispose();
    _toastTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    HapticFeedback.lightImpact();
    final deviceProv = Provider.of<DeviceProvider>(context, listen: false);
    final orderProv = Provider.of<OrderProvider>(context, listen: false);
    final isStaff =
        Provider.of<UserProvider>(context, listen: false).isSystemStaff;
    try {
      await deviceProv.refreshDevices();
      if (isStaff) {
        await _loadStaffFleetStats();
      } else {
        await orderProv.refreshOrders();
      }
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 600));
    }
    if (mounted) {
      _showToast('Đã làm mới dữ liệu nút bấm');
    }
  }

  void _showFloatingToast({
    required String message,
    VoidCallback? onUndo,
    Duration duration = const Duration(seconds: 4),
  }) {
    _toastTimer?.cancel();
    setState(() {
      _toastMessage = message;
      _toastOnUndo = onUndo;
    });
    _toastController.forward(from: 0.0);
    _toastTimer = Timer(duration, _dismissToast);
  }

  void _dismissToast() {
    _toastTimer?.cancel();
    if (_toastController.isAnimating || _toastController.isCompleted) {
      _toastController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _toastMessage = null;
            _toastOnUndo = null;
          });
        }
      });
    }
  }

  void _showToast(String message) => _showFloatingToast(message: message);

  void _showAccountSheet() {
    final isFiveTab =
        (_userProvider?.isStoreOwner == true) ||
        (_userProvider?.isSystemStaff == true);
    MainLayout.switchToTab(context, isFiveTab ? 4 : 3);
  }

  void _showLocationPicker() {
    AddressPickerSheet.show(
      context,
      onAddressSelected: (addr) => _showToast('Đã chuyển sang: $addr'),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AddressProvider>();
    List<DeviceModel> displayDevices = _fallbackDevices;
    bool isDevLoading = false;
    try {
      final provider = Provider.of<DeviceProvider>(context);
      displayDevices = provider.devices;
      isDevLoading = provider.isLoading;
    } catch (_) {}

    NotificationProvider? notifProvider;
    try {
      notifProvider = Provider.of<NotificationProvider>(context);
    } catch (_) {}

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: AContent(
        maxWidth: SampleA.listWidth,
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _handleRefresh,
              color: const Color(0xFF287DA8),
              child: SingleChildScrollView(
                controller: _homeScrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HomeHeaderCard(
                      userAvatar: _userAvatar,
                      userAvatarUrl: _userAvatarUrl,
                      userInitials: _userInitials,
                      userShortName: _userShortName,
                      userAddress: _userAddress,
                      deviceCount: (_userProvider?.isSystemStaff == true)
                          ? _readIntStat(
                              _staffFleetStats,
                              ['total', 'totalDevices', 'totalButtons'],
                              displayDevices.length,
                            )
                          : displayDevices.length,
                      role: _userProvider?.role ?? 'CUSTOMER',
                      storeName: _userProvider?.storeName,
                      storeAddress: _userProvider?.storeAddress,
                      unreadNotificationCount: notifProvider?.unreadCount ?? 0,
                      onAccountTap: _showAccountSheet,
                      onNotificationTap: () => NotificationSheet.show(context),
                      onLocationTap: () {
                        if (_userProvider?.isStoreOwner == true ||
                            _userProvider?.isAdmin == true ||
                            _userProvider?.isSystemStaff == true) {
                          MainLayout.switchToTab(context, 1);
                        } else {
                          _showLocationPicker();
                        }
                      },
                    ),
                    Transform.translate(
                      offset: const Offset(0, -28),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            HomeGrabServicesGrid(
                              role: _userProvider?.role ?? 'CUSTOMER',
                              onScrollToStores: _openShopStores,
                            ),
                            const SizedBox(height: 20),
                            ((_userProvider?.isAdmin ?? false)
                                    ? _buildAdminOverview(displayDevices)
                                    : (_userProvider?.isSystemStaff ?? false)
                                        ? _buildSystemStaffOverview(
                                            displayDevices,
                                          )
                                        : (_userProvider?.isStoreOwner ?? false)
                                            ? _buildStoreOverview(displayDevices)
                                            : _buildLandingShowcase())
                                .animate()
                                .fade(duration: 320.ms),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_showCompactHeader)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Material(
                  color: Colors.white,
                  elevation: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'SmartOrder',
                              style: TextStyle(
                                color: Color(0xFF0E6BA8),
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Thông báo',
                            onPressed: () => NotificationSheet.show(context),
                            icon: Badge(
                              isLabelVisible:
                                  (notifProvider?.unreadCount ?? 0) > 0,
                              backgroundColor: const Color(0xFFEF4444),
                              child: const Icon(
                                Icons.notifications_none_rounded,
                                size: 25,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_toastMessage != null)
              HomeFloatingToast(
                slideAnimation: _toastSlideAnimation,
                fadeAnimation: _toastFadeAnimation,
                scaleAnimation: _toastScaleAnimation,
                message: _toastMessage!,
                onUndo: _toastOnUndo,
              ),
          ],
        ),
      ),
    );
  }
}
