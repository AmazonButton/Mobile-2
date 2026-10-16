import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../widgets/smart_order_tour.dart';
import 'home_screen.dart';
import 'devices_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';
import 'store_products_screen.dart';
import 'system_staff/system_staff_devices_screen.dart';
import 'system_staff/system_staff_warranty_screen.dart';
import 'system_staff/system_staff_returns_screen.dart';
import '../widgets/sample_a.dart';

/// App Shell Architecture with persistent bottom navigation using IndexedStack
class MainLayout extends StatefulWidget {
  final int initialIndex;

  const MainLayout({super.key, this.initialIndex = 0});

  /// Allows child widgets to programmatically switch tabs without pushing new routes
  static void switchToTab(BuildContext context, int index) {
    final state = context.findAncestorStateOfType<_MainLayoutState>();
    state?.changeTab(index);
  }

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  late int _currentIndex;
  late final SmartOrderTour _tour;

  @override
  void dispose() {
    _tour.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _tour = SmartOrderTour(context: context, changeTab: changeTab);
  }

  void changeTab(int index) {
    final userProv = context.read<UserProvider?>();
    final maxTabs =
        (userProv?.isStoreOwner == true || userProv?.isSystemStaff == true)
            ? 5
            : 4;
    if (index >= 0 && index < maxTabs && index != _currentIndex) {
      HapticFeedback.selectionClick();
      setState(() {
        _currentIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProv = context.watch<UserProvider?>();
    final account = userProv?.accountId;
    final isAdmin = userProv?.isAdmin ?? false;
    final isSystemStaff = userProv?.isSystemStaff ?? false;
    final isStoreOwner = userProv?.isStoreOwner ?? false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !isAdmin && !isStoreOwner && !isSystemStaff) {
        _tour.accountChanged(account);
      } else if (mounted) {
        _tour.dismiss();
      }
    });

    final screens = isSystemStaff
        ? [
            HomePage(tour: _tour),
            const SystemStaffDevicesScreen(),
            const SystemStaffWarrantyScreen(),
            const SystemStaffReturnsScreen(),
            ProfileScreen(showBackButton: false, tour: _tour),
          ]
        : isStoreOwner
            ? [
                HomePage(tour: _tour),
                const StoreProductsScreen(),
                DevicesScreen(tour: _tour),
                OrdersScreen(showBackButton: false, tour: _tour),
                ProfileScreen(showBackButton: false, tour: _tour),
              ]
            : [
                HomePage(tour: _tour),
                DevicesScreen(tour: _tour),
                OrdersScreen(showBackButton: false, tour: _tour),
                ProfileScreen(showBackButton: false, tour: _tour),
              ];

    final safeIndex = _currentIndex.clamp(0, screens.length - 1);

    final destinations = isSystemStaff
        ? const [
            NavigationDestination(
              icon: Icon(LucideIcons.layoutDashboard),
              label: 'Tổng quan',
              tooltip: '',
            ),
            NavigationDestination(
              icon: Icon(LucideIcons.cpu),
              label: 'Kho nút',
              tooltip: '',
            ),
            NavigationDestination(
              icon: Icon(LucideIcons.shieldCheck),
              label: 'Bảo hành',
              tooltip: '',
            ),
            NavigationDestination(
              icon: Icon(LucideIcons.rotateCcw),
              label: 'Thu hồi',
              tooltip: '',
            ),
            NavigationDestination(
              icon: Icon(LucideIcons.userRound),
              label: 'Tài khoản',
              tooltip: '',
            ),
          ]
        : isAdmin
            ? const [
            NavigationDestination(
              icon: Icon(LucideIcons.layoutDashboard),
              label: 'Tổng quan',
              tooltip: '',
            ),
            NavigationDestination(
              icon: Icon(LucideIcons.cpu),
              label: 'Kho nút',
              tooltip: '',
            ),
            NavigationDestination(
              icon: Icon(LucideIcons.receiptText),
              label: 'Đơn hàng',
              tooltip: '',
            ),
            NavigationDestination(
              icon: Icon(LucideIcons.userRound),
              label: 'Tài khoản',
              tooltip: '',
            ),
          ]
        : isStoreOwner
            ? const [
                NavigationDestination(
                  icon: Icon(LucideIcons.store),
                  label: 'Tổng quan',
                  tooltip: '',
                ),
                NavigationDestination(
                  icon: Icon(LucideIcons.package),
                  label: 'Sản phẩm',
                  tooltip: '',
                ),
                NavigationDestination(
                  icon: Icon(LucideIcons.cpu),
                  label: 'Nút IoT',
                  tooltip: '',
                ),
                NavigationDestination(
                  icon: Icon(LucideIcons.receiptText),
                  label: 'Đơn hàng',
                  tooltip: '',
                ),
                NavigationDestination(
                  icon: Icon(LucideIcons.userRound),
                  label: 'Tài khoản',
                  tooltip: '',
                ),
              ]
            : const [
                NavigationDestination(
                  icon: Icon(LucideIcons.home),
                  label: 'Trang chủ',
                  tooltip: '',
                ),
                NavigationDestination(
                  icon: Icon(LucideIcons.smartphone),
                  label: 'Nút của tôi',
                  tooltip: '',
                ),
                NavigationDestination(
                  icon: Icon(LucideIcons.receiptText),
                  label: 'Đơn hàng',
                  tooltip: '',
                ),
                NavigationDestination(
                  icon: Icon(LucideIcons.userRound),
                  label: 'Tài khoản',
                  tooltip: '',
                ),
              ];

    return PopScope(
      onPopInvokedWithResult: (_, _) => _tour.dismiss(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7FB),
        body: IndexedStack(
          index: safeIndex,
          children: screens,
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Color(0xFFE2E8F0), width: 1),
            ),
          ),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return TextStyle(
                  fontSize: (isStoreOwner || isSystemStaff) ? 10.5 : 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? const Color(0xFF0E6BA8)
                      : const Color(0xFF64748B),
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith(
                (states) => IconThemeData(
                  size: 20,
                  color: states.contains(WidgetState.selected)
                      ? const Color(0xFF0E6BA8)
                      : const Color(0xFF64748B),
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: safeIndex,
              onDestinationSelected: changeTab,
              backgroundColor: Colors.white,
              indicatorColor: const Color(0xFFE0F2FE),
              elevation: 0,
              height: 64,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: destinations,
            ),
          ),
        ),
      ),
    );
  }
}
