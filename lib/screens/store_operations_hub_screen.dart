import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/user_provider.dart';
import '../services/api_client.dart';
import '../services/merchant_api_service.dart';
import '../services/stores_api_service.dart';
import '../utils/formatters.dart';
import '../widgets/sample_a.dart';
import 'system_staff/system_staff_returns_screen.dart';
import 'system_staff/system_staff_warranty_screen.dart';

/// Trung tâm Vận hành Cửa hàng (STORE_OWNER):
/// 1. Báo cáo doanh thu & cảnh báo
/// 2. Gói duy trì gian hàng (60.000đ/tháng & dùng thử)
/// 3. Nhân sự cửa hàng (Store Staff CRUD)
/// 4. Khách hàng CRM (ACTIVE / BLOCKED)
/// 5. Lối tắt Nhận nút trả & Phiếu bảo hành quán
class StoreOperationsHubScreen extends StatefulWidget {
  final int initialTab;
  const StoreOperationsHubScreen({super.key, this.initialTab = 0});

  @override
  State<StoreOperationsHubScreen> createState() => _StoreOperationsHubScreenState();
}

class _StoreOperationsHubScreenState extends State<StoreOperationsHubScreen>
    with SingleTickerProviderStateMixin {
  final _api = MerchantApiService();
  late final TabController _tabs = TabController(
    length: 4,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 3),
  );

  String _storeId = '';
  bool _loading = true;
  Map<String, dynamic> _analytics = {};
  Map<String, dynamic>? _currentSub;
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _customers = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? const Color(0xFFDC2626) : const Color(0xFF047857),
        content: Text(msg),
      ),
    );
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      var sid = context.read<UserProvider?>()?.storeId ?? '';
      if (sid.isEmpty) {
        try {
          final st = await StoresApiService().getMyStore();
          sid = (st['storeId'] ?? st['id'] ?? '').toString();
        } catch (_) {}
      }
      _storeId = sid;

      final results = await Future.wait([
        _api.getDashboardAnalytics().catchError((_) => <String, dynamic>{}),
        _api.getCurrentSubscription().catchError((_) => null),
        _api.listSubscriptionPlans().catchError((_) => <Map<String, dynamic>>[]),
        if (sid.isNotEmpty) _api.listStaff(sid).catchError((_) => <Map<String, dynamic>>[]),
        _api.listAssignableStaffRoles().catchError((_) => <Map<String, dynamic>>[]),
        if (sid.isNotEmpty) _api.listCustomers(sid).catchError((_) => <Map<String, dynamic>>[]),
      ]);

      if (!mounted) return;
      var idx = 0;
      setState(() {
        _analytics = (results[idx++] as Map<String, dynamic>?) ?? {};
        _currentSub = results[idx++] as Map<String, dynamic>?;
        _plans = (results[idx++] as List<Map<String, dynamic>>?) ?? [];
        _staff = sid.isNotEmpty
            ? ((results[idx++] as List<Map<String, dynamic>>?) ?? [])
            : [];
        _roles = (results[idx++] as List<Map<String, dynamic>>?) ?? [];
        _customers = sid.isNotEmpty
            ? ((results[idx++] as List<Map<String, dynamic>>?) ?? [])
            : [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  num _num(dynamic v) => v is num ? v : (num.tryParse(v?.toString() ?? '') ?? 0);

  Future<void> _addStaffDialog() async {
    if (_storeId.isEmpty) {
      _snack('Không tìm thấy mã cửa hàng.', error: true);
      return;
    }
    final identCtrl = TextEditingController();
    String selectedRole = _roles.isNotEmpty
        ? (_roles.first['roleCode'] ?? _roles.first['code'] ?? 'STAFF_ORDER').toString()
        : 'STAFF_ORDER';
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Thêm nhân viên cửa hàng', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: identCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email / SĐT / Username nhân viên *',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Vai trò'),
                  items: (_roles.isEmpty
                          ? const [
                              {'roleCode': 'STAFF_ORDER', 'name': 'Nhân viên đơn hàng'},
                              {'roleCode': 'STAFF_INVENTORY', 'name': 'Nhân viên kho'},
                              {'roleCode': 'STAFF_DELIVERY', 'name': 'Nhân viên giao hàng'},
                              {'roleCode': 'STORE_MANAGER', 'name': 'Quản lý cửa hàng'},
                            ]
                          : _roles)
                      .map((r) {
                    final code = (r['roleCode'] ?? r['code']).toString();
                    final label = (r['roleName'] ?? r['name'] ?? code).toString();
                    return DropdownMenuItem(value: code, child: Text(label, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (v) => setLocal(() => selectedRole = v ?? 'STAFF_ORDER'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Thêm')),
            ],
          ),
        ),
      );
      if (ok != true || identCtrl.text.trim().isEmpty) return;
      await _api.addStaff(
        _storeId,
        userIdentifier: identCtrl.text.trim(),
        roleCode: selectedRole,
      );
      _snack('Đã gửi lời mời / thêm nhân viên thành công!');
      await _loadAll();
    } catch (e) {
      _snack(e is ApiException ? e.message : 'Thêm nhân viên thất bại.', error: true);
    } finally {
      identCtrl.dispose();
    }
  }

  Future<void> _subscribePlan(Map<String, dynamic> plan, {required bool usePayos}) async {
    final planId = (plan['planId'] ?? plan['id'] ?? '').toString();
    if (planId.isEmpty) return;
    try {
      if (usePayos) {
        final res = await _api.createSubscriptionRenewCharge(planId);
        final url = (res['checkoutUrl'] ?? res['paymentUrl'] ?? '').toString().trim();
        if (url.isNotEmpty) {
          final uri = Uri.tryParse(url);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
        _snack('Đã khởi tạo thanh toán gói qua PayOS!');
      } else {
        await _api.subscribeWithWallet(planId);
        _snack('Đăng ký gói dịch vụ thành công!');
      }
      await _loadAll();
    } catch (e) {
      _snack(e is ApiException ? e.message : 'Đăng ký gói thất bại.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text(
          'Trung tâm vận hành cửa hàng',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(LucideIcons.refreshCw, size: 18),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: const Color(0xFF047857),
          indicatorColor: const Color(0xFF047857),
          tabs: const [
            Tab(text: 'Báo cáo'),
            Tab(text: 'Gói dịch vụ'),
            Tab(text: 'Nhân viên'),
            Tab(text: 'Khách hàng'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF047857)))
          : TabBarView(
              controller: _tabs,
              children: [
                _buildAnalyticsTab(),
                _buildSubscriptionsTab(),
                _buildStaffTab(),
                _buildCustomersTab(),
              ],
            ),
    );
  }

  Widget _buildAnalyticsTab() {
    final summary = _analytics['summary'] is Map
        ? Map<String, dynamic>.from(_analytics['summary'] as Map)
        : _analytics;
    final revenue = _num(summary['totalRevenue'] ?? summary['revenue']);
    final orders = _num(summary['totalOrders'] ?? summary['orderCount']).round();
    final completed = _num(summary['completedOrders'] ?? summary['deliveredOrders']).round();
    final customers = _num(summary['totalCustomers'] ?? summary['uniqueCustomers']).round();

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _kpi('Doanh thu', CurrencyFormatter.format(revenue), const Color(0xFF047857)),
              const SizedBox(width: 10),
              _kpi('Tổng đơn', '$orders', const Color(0xFF0E6BA8)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _kpi('Hoàn tất', '$completed', const Color(0xFF059669)),
              const SizedBox(width: 10),
              _kpi('Khách hàng', '$customers', const Color(0xFF7C3AED)),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Nghiệp vụ thiết bị tại quầy',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          _shortcutTile(
            icon: LucideIcons.rotateCcw,
            color: const Color(0xFFD97706),
            title: 'Tiếp nhận nút trả từ khách',
            subtitle: 'Kiểm tra ngoại quan & xác nhận hoàn kho (STORE_OWNER)',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const SystemStaffReturnsScreen()),
            ),
          ),
          const SizedBox(height: 8),
          _shortcutTile(
            icon: LucideIcons.shieldCheck,
            color: const Color(0xFF0E7490),
            title: 'Phiếu bảo hành thiết bị',
            subtitle: 'Theo dõi phiếu bảo hành & đổi nút 1-1 cho khách',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const SystemStaffWarrantyScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionsTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ACard(
            color: const Color(0xFFECFDF5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Gói duy trì gian hàng hiện tại',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF047857)),
                ),
                const SizedBox(height: 6),
                Text(
                  _currentSub == null
                      ? 'Chưa kích hoạt gói duy trì'
                      : '${_currentSub!['plan']?['planName'] ?? _currentSub!['planName'] ?? 'Gói gian hàng'} · ${_currentSub!['status'] ?? ''}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                if (_currentSub?['endDate'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Hết hạn: ${_currentSub!['endDate']}',
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Các gói dịch vụ khả dụng',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (_plans.isEmpty)
            const ACard(child: Text('Chưa có gói dịch vụ nào.', style: SampleA.caption))
          else
            for (final plan in _plans)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (plan['planName'] ?? plan['name'] ?? 'Gói dịch vụ').toString(),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${CurrencyFormatter.format(_num(plan['price']))} / ${plan['durationDays'] ?? 30} ngày • Tối đa ${plan['maxProducts'] ?? '∞'} SP',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF047857), fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857)),
                          onPressed: () => _subscribePlan(plan, usePayos: true),
                          child: const Text('Thanh toán PayOS'),
                        ),
                        OutlinedButton(
                          onPressed: () => _subscribePlan(plan, usePayos: false),
                          child: const Text('Dùng số dư ví'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildStaffTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Nhân viên cửa hàng (${_staff.length})',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857)),
                onPressed: _addStaffDialog,
                icon: const Icon(LucideIcons.userPlus, size: 15),
                label: const Text('Thêm NV'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_staff.isEmpty)
            const ACard(child: Text('Chưa có nhân viên nào được phân quyền.', style: SampleA.caption))
          else
            for (final s in _staff)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFECFDF5),
                    child: Icon(LucideIcons.user, color: Color(0xFF047857), size: 18),
                  ),
                  title: Text(
                    (s['user']?['fullName'] ?? s['fullName'] ?? s['user']?['email'] ?? 'Nhân viên').toString(),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  subtitle: Text(
                    '${s['roleCode'] ?? s['role'] ?? ''} • ${s['status'] ?? ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(LucideIcons.trash2, size: 17, color: Color(0xFFDC2626)),
                    onPressed: () async {
                      final id = (s['storeStaffId'] ?? s['id']).toString();
                      try {
                        await _api.removeStaff(id);
                        _snack('Đã xóa nhân viên khỏi cửa hàng.');
                        _loadAll();
                      } catch (e) {
                        _snack(e is ApiException ? e.message : 'Xóa nhân viên thất bại.', error: true);
                      }
                    },
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildCustomersTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Khách hàng của cửa hàng (${_customers.length})',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (_customers.isEmpty)
            const ACard(child: Text('Chưa có khách hàng nào.', style: SampleA.caption))
          else
            for (final c in _customers)
              Builder(
                builder: (_) {
                  final cid = (c['customerId'] ?? c['customerProfileId'] ?? c['id']).toString();
                  final status = (c['status'] ?? 'ACTIVE').toString().toUpperCase();
                  final isBlocked = status == 'BLOCKED';
                  final name = (c['customer']?['user']?['fullName'] ??
                          c['fullName'] ??
                          c['customerName'] ??
                          'Khách #$cid')
                      .toString();
                  final phone = (c['customer']?['user']?['phone'] ?? c['phone'] ?? '').toString();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: ListTile(
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      subtitle: Text(
                        '${phone.isNotEmpty ? '$phone • ' : ''}Trạng thái: $status',
                        style: TextStyle(
                          fontSize: 12,
                          color: isBlocked ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                        ),
                      ),
                      trailing: OutlinedButton(
                        onPressed: () async {
                          final next = isBlocked ? 'ACTIVE' : 'BLOCKED';
                          try {
                            await _api.updateCustomerStatus(_storeId, cid, next);
                            _snack('Đã chuyển khách hàng sang $next');
                            _loadAll();
                          } catch (e) {
                            _snack(e is ApiException ? e.message : 'Cập nhật thất bại.', error: true);
                          }
                        },
                        child: Text(isBlocked ? 'Mở khóa' : 'Chặn'),
                      ),
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shortcutTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(LucideIcons.chevronRight, size: 16),
        onTap: onTap,
      ),
    );
  }
}
