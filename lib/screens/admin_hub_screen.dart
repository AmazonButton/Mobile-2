import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/admin_api_service.dart';
import '../services/api_client.dart';
import '../utils/formatters.dart';
import '../widgets/sample_a.dart';

/// Trung tâm Quản trị Sàn toàn diện dành cho ADMIN / SYSTEM_ADMIN / SUPER_ADMIN:
/// 1. Tổng quan & Audit Logs
/// 2. Người dùng & Phân quyền RBAC
/// 3. Rút tiền PayOS & Nghĩa vụ hoàn tiền
/// 4. Hợp đồng thuê nút & Duyệt hoàn cọc
/// 5. Gói thuê nút & Gói cước gian hàng (CRUD)
/// 6. Kiểm duyệt phiên eKYC Didit
class AdminHubScreen extends StatefulWidget {
  final int initialTab;
  const AdminHubScreen({super.key, this.initialTab = 0});

  @override
  State<AdminHubScreen> createState() => _AdminHubScreenState();
}

class _AdminHubScreenState extends State<AdminHubScreen>
    with SingleTickerProviderStateMixin {
  final _api = AdminApiService();
  late final TabController _tabs = TabController(
    length: 6,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 5),
  );

  bool _loading = true;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _auditLogs = [];
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _withdrawals = [];
  List<Map<String, dynamic>> _obligations = [];
  List<Map<String, dynamic>> _rentals = [];
  List<Map<String, dynamic>> _packages = [];
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _ekycSessions = [];
  List<Map<String, dynamic>> _stores = [];

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
        backgroundColor: error ? const Color(0xFFDC2626) : const Color(0xFF4338CA),
        content: Text(msg),
      ),
    );
  }

  num _num(dynamic v) => v is num ? v : (num.tryParse(v?.toString() ?? '') ?? 0);

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getStats().catchError((_) => <String, dynamic>{}),
        _api.listAuditLogs().catchError((_) => <Map<String, dynamic>>[]),
        _api.listUsers().catchError((_) => <Map<String, dynamic>>[]),
        _api.listWithdrawals().catchError((_) => <Map<String, dynamic>>[]),
        _api.listRefundObligations().catchError((_) => <Map<String, dynamic>>[]),
        _api.listRentals().catchError((_) => <Map<String, dynamic>>[]),
        _api.listRentalPackages().catchError((_) => <Map<String, dynamic>>[]),
        _api.listPlans().catchError((_) => <Map<String, dynamic>>[]),
        _api.listIdentitySessions().catchError((_) => <Map<String, dynamic>>[]),
        _api.listStores().catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as Map<String, dynamic>;
        _auditLogs = results[1] as List<Map<String, dynamic>>;
        _users = results[2] as List<Map<String, dynamic>>;
        _withdrawals = results[3] as List<Map<String, dynamic>>;
        _obligations = results[4] as List<Map<String, dynamic>>;
        _rentals = results[5] as List<Map<String, dynamic>>;
        _packages = results[6] as List<Map<String, dynamic>>;
        _plans = results[7] as List<Map<String, dynamic>>;
        _ekycSessions = results[8] as List<Map<String, dynamic>>;
        _stores = results[9] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showRoleDialog(Map<String, dynamic> user) async {
    final uid = (user['userId'] ?? user['id'] ?? '').toString();
    String role = (user['role'] ?? 'CUSTOMER').toString().toUpperCase();
    const roles = ['CUSTOMER', 'STORE_OWNER', 'SYSTEM_STAFF', 'ADMIN', 'SYSTEM_ADMIN', 'SUPER_ADMIN'];
    if (!roles.contains(role)) role = 'CUSTOMER';
    final reasonCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Phân quyền tài khoản (RBAC)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Vai trò mới'),
                  items: roles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) => setLocal(() => role = v ?? 'CUSTOMER'),
                ),
                const SizedBox(height: 10),
                TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Lý do thay đổi')),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cập nhật')),
            ],
          ),
        ),
      );
      if (ok != true) return;
      await _api.updateUserRole(uid, role: role, reason: reasonCtrl.text);
      _snack('Đã cập nhật vai trò → $role');
      _loadAll();
    } catch (e) {
      _snack(e is ApiException ? e.message : 'Cập nhật vai trò thất bại.', error: true);
    } finally {
      reasonCtrl.dispose();
    }
  }

  Future<void> _showAssignFulfillmentDialog(Map<String, dynamic> rental) async {
    final rid = (rental['rentalId'] ?? rental['id'] ?? '').toString();
    String storeId = _stores.isNotEmpty ? (_stores.first['storeId'] ?? _stores.first['id']).toString() : '';
    final buttonsCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text('Bàn giao thiết bị · HĐ #$rid', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: storeId.isEmpty ? null : storeId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Cửa hàng bàn giao'),
                    items: _stores.map((s) {
                      final sid = (s['storeId'] ?? s['id']).toString();
                      return DropdownMenuItem(value: sid, child: Text((s['name'] ?? 'CH #$sid').toString(), overflow: TextOverflow.ellipsis));
                    }).toList(),
                    onChanged: (v) => setLocal(() => storeId = v ?? ''),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: buttonsCtrl,
                    decoration: const InputDecoration(labelText: 'Mã nút (phân cách dấu phẩy) *', hintText: 'SOB-000001'),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Ghi chú')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Gán ngay')),
            ],
          ),
        ),
      );
      if (ok != true) return;
      final ids = buttonsCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (storeId.isEmpty || ids.isEmpty) {
        _snack('Vui lòng chọn cửa hàng và nhập ít nhất 1 mã nút.', error: true);
        return;
      }
      await _api.assignFulfillment(rid, fulfillmentStoreId: storeId, buttonIds: ids, notes: notesCtrl.text);
      _snack('Đã gán thiết bị & cửa hàng bàn giao thành công!');
      _loadAll();
    } catch (e) {
      _snack(e is ApiException ? e.message : 'Gán bàn giao thất bại.', error: true);
    } finally {
      buttonsCtrl.dispose();
      notesCtrl.dispose();
    }
  }

  Future<void> _showPackageFormDialog({Map<String, dynamic>? editing}) async {
    final isEdit = editing != null;
    final id = editing != null ? (editing['packageId'] ?? editing['id']).toString() : '';
    final codeCtrl = TextEditingController(text: (editing?['packageCode'] ?? '').toString());
    final nameCtrl = TextEditingController(text: (editing?['packageName'] ?? '').toString());
    final qtyCtrl = TextEditingController(text: (editing?['buttonQuantity'] ?? 1).toString());
    final priceCtrl = TextEditingController(text: (editing?['monthlyPrice'] ?? 30000).toString());
    final depCtrl = TextEditingController(text: (editing?['depositFee'] ?? 200000).toString());
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(isEdit ? 'Sửa gói thuê nút' : 'Tạo gói thuê nút mới', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isEdit)
                  TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Mã gói (VD: PKG_1BTN) *')),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên gói *')),
                TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Số lượng nút')),
                TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Giá thuê/tháng (VNĐ)')),
                TextField(controller: depCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tiền cọc (VNĐ)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lưu')),
          ],
        ),
      );
      if (ok != true || nameCtrl.text.trim().isEmpty) return;
      final body = <String, dynamic>{
        if (!isEdit) 'packageCode': codeCtrl.text.trim(),
        'packageName': nameCtrl.text.trim(),
        'buttonQuantity': int.tryParse(qtyCtrl.text.trim()) ?? 1,
        'monthlyPrice': num.tryParse(priceCtrl.text.trim()) ?? 30000,
        'depositFee': num.tryParse(depCtrl.text.trim()) ?? 0,
      };
      if (isEdit) {
        await _api.updateRentalPackage(id, body);
        _snack('Đã cập nhật gói thuê nút!');
      } else {
        await _api.createRentalPackage(body);
        _snack('Đã tạo gói thuê nút mới!');
      }
      _loadAll();
    } catch (e) {
      _snack(e is ApiException ? e.message : 'Lưu gói thuê thất bại.', error: true);
    } finally {
      codeCtrl.dispose();
      nameCtrl.dispose();
      qtyCtrl.dispose();
      priceCtrl.dispose();
      depCtrl.dispose();
    }
  }

  Future<void> _showPlanFormDialog({Map<String, dynamic>? editing}) async {
    final isEdit = editing != null;
    final id = editing != null ? (editing['planId'] ?? editing['id']).toString() : '';
    final codeCtrl = TextEditingController(text: (editing?['planCode'] ?? '').toString());
    final nameCtrl = TextEditingController(text: (editing?['planName'] ?? '').toString());
    final priceCtrl = TextEditingController(text: (editing?['price'] ?? 60000).toString());
    final daysCtrl = TextEditingController(text: (editing?['durationDays'] ?? 30).toString());
    final maxProdCtrl = TextEditingController(text: (editing?['maxProducts'] ?? 100).toString());
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(isEdit ? 'Sửa gói cước gian hàng' : 'Tạo gói cước gian hàng', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isEdit)
                  TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Mã gói (VD: PRO_30D) *')),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên gói *')),
                TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Giá cước (VNĐ)')),
                TextField(controller: daysCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Số ngày hiệu lực')),
                TextField(controller: maxProdCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Số sản phẩm tối đa')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lưu')),
          ],
        ),
      );
      if (ok != true || nameCtrl.text.trim().isEmpty) return;
      final body = <String, dynamic>{
        if (!isEdit) 'planCode': codeCtrl.text.trim(),
        'planName': nameCtrl.text.trim(),
        'price': num.tryParse(priceCtrl.text.trim()) ?? 60000,
        'durationDays': int.tryParse(daysCtrl.text.trim()) ?? 30,
        'maxProducts': int.tryParse(maxProdCtrl.text.trim()) ?? 100,
      };
      if (isEdit) {
        await _api.updatePlan(id, body);
        _snack('Đã cập nhật gói cước!');
      } else {
        await _api.createPlan(body);
        _snack('Đã tạo gói cước mới!');
      }
      _loadAll();
    } catch (e) {
      _snack(e is ApiException ? e.message : 'Lưu gói cước thất bại.', error: true);
    } finally {
      codeCtrl.dispose();
      nameCtrl.dispose();
      priceCtrl.dispose();
      daysCtrl.dispose();
      maxProdCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text(
          'Trung tâm quản trị sàn',
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
          labelColor: const Color(0xFF4338CA),
          indicatorColor: const Color(0xFF4338CA),
          tabs: const [
            Tab(text: 'Tổng quan'),
            Tab(text: 'Người dùng'),
            Tab(text: 'Rút tiền PayOS'),
            Tab(text: 'HĐ thuê & Cọc'),
            Tab(text: 'Gói & Cước'),
            Tab(text: 'eKYC'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4338CA)))
          : TabBarView(
              controller: _tabs,
              children: [
                _buildOverviewTab(),
                _buildUsersTab(),
                _buildWithdrawalsTab(),
                _buildRentalsTab(),
                _buildPackagesAndPlansTab(),
                _buildEkycTab(),
              ],
            ),
    );
  }

  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _kpi('Người dùng', '${_stats['totalUsers'] ?? _users.length}', const Color(0xFF4338CA)),
              const SizedBox(width: 10),
              _kpi('Cửa hàng', '${_stats['totalStores'] ?? _stores.length}', const Color(0xFF059669)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _kpi('Hợp đồng thuê', '${_stats['totalRentals'] ?? _rentals.length}', const Color(0xFF0E6BA8)),
              const SizedBox(width: 10),
              _kpi('Lệnh rút tiền', '${_withdrawals.length}', const Color(0xFFD97706)),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Nhật ký kiểm toán hệ thống (${_auditLogs.length})',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (_auditLogs.isEmpty)
            const ACard(child: Text('Chưa có nhật ký kiểm toán.', style: SampleA.caption))
          else
            for (final log in _auditLogs.take(30))
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (log['action'] ?? log['eventType'] ?? 'AUDIT').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    if (log['description'] != null || log['entityType'] != null)
                      Text(
                        '${log['entityType'] ?? ''} ${log['entityId'] ?? ''} ${log['description'] ?? ''}'.trim(),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                      ),
                    if (log['createdAt'] != null)
                      Text(
                        log['createdAt'].toString(),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildUsersTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _users.isEmpty ? 1 : _users.length,
        itemBuilder: (_, idx) {
          if (_users.isEmpty) {
            return const ACard(child: Text('Không có người dùng hoặc cần quyền SUPER_ADMIN.', style: SampleA.caption));
          }
          final u = _users[idx];
          final uid = (u['userId'] ?? u['id'] ?? '').toString();
          final name = (u['fullName'] ?? u['username'] ?? u['email'] ?? 'User #$uid').toString();
          final email = (u['email'] ?? u['phone'] ?? '').toString();
          final role = (u['role'] ?? 'CUSTOMER').toString();
          final active = u['isActive'] != false && (u['status']?.toString().toUpperCase() != 'INACTIVE');
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(role, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF4338CA))),
                    ),
                  ],
                ),
                if (email.isNotEmpty)
                  Text(email, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => _showRoleDialog(u),
                      child: const Text('Đổi vai trò'),
                    ),
                    TextButton(
                      onPressed: () async {
                        try {
                          await _api.toggleUserStatus(uid);
                          _snack('Đã đổi trạng thái tài khoản.');
                          _loadAll();
                        } catch (e) {
                          _snack(e is ApiException ? e.message : 'Thao tác thất bại.', error: true);
                        }
                      },
                      child: Text(active ? 'Khóa tài khoản' : 'Mở khóa'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildWithdrawalsTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Yêu cầu rút tiền cửa hàng (${_withdrawals.length})',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (_withdrawals.isEmpty)
            const ACard(child: Text('Chưa có yêu cầu rút tiền nào.', style: SampleA.caption))
          else
            for (final w in _withdrawals)
              Builder(
                builder: (_) {
                  final id = (w['withdrawalId'] ?? w['id'] ?? '').toString();
                  final status = (w['status'] ?? 'PENDING').toString().toUpperCase();
                  final amount = _num(w['amount']);
                  final storeName = (w['store']?['name'] ?? w['storeName'] ?? 'CH #${w['storeId'] ?? ''}').toString();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(storeName, style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                            Text(
                              CurrencyFormatter.format(amount),
                              style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF4338CA)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Trạng thái: $status', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (status == 'PENDING')
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                                onPressed: () async {
                                  try {
                                    await _api.payoutWithdrawal(id);
                                    _snack('Đã gửi lệnh chi tiền PayOS!');
                                    _loadAll();
                                  } catch (e) {
                                    _snack(e is ApiException ? e.message : 'Chi tiền thất bại.', error: true);
                                  }
                                },
                                child: const Text('Chi PayOS'),
                              ),
                            if (status != 'COMPLETED' && status != 'REJECTED') ...[
                              OutlinedButton(
                                onPressed: () async {
                                  try {
                                    await _api.syncWithdrawalPayout(id);
                                    _snack('Đã đồng bộ trạng thái PayOS!');
                                    _loadAll();
                                  } catch (e) {
                                    _snack(e is ApiException ? e.message : 'Đồng bộ thất bại.', error: true);
                                  }
                                },
                                child: const Text('Đồng bộ'),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                                onPressed: () async {
                                  try {
                                    await _api.rejectWithdrawal(id, reason: 'Admin từ chối lệnh rút tiền');
                                    _snack('Đã từ chối & hoàn số dư về ví cửa hàng.');
                                    _loadAll();
                                  } catch (e) {
                                    _snack(e is ApiException ? e.message : 'Từ chối thất bại.', error: true);
                                  }
                                },
                                child: const Text('Từ chối'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          if (_obligations.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Nghĩa vụ hoàn tiền PayOS (${_obligations.length})',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            for (final ob in _obligations)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HĐ/Đơn #${ob['obligationId'] ?? ob['id']} · ${CurrencyFormatter.format(_num(ob['amount']))}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text('Trạng thái: ${ob['status']}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        final oid = (ob['obligationId'] ?? ob['id']).toString();
                        try {
                          await _api.syncRefundObligation(oid);
                          _snack('Đã đồng bộ nghĩa vụ hoàn tiền.');
                          _loadAll();
                        } catch (e) {
                          _snack(e is ApiException ? e.message : 'Đồng bộ thất bại.', error: true);
                        }
                      },
                      child: const Text('Đồng bộ'),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildRentalsTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _rentals.isEmpty ? 1 : _rentals.length,
        itemBuilder: (_, idx) {
          if (_rentals.isEmpty) {
            return const ACard(child: Text('Chưa có hợp đồng thuê nút nào.', style: SampleA.caption));
          }
          final r = _rentals[idx];
          final rid = (r['rentalId'] ?? r['id'] ?? '').toString();
          final code = (r['rentalCode'] ?? 'HĐ #$rid').toString();
          final status = (r['status'] ?? '').toString().toUpperCase();
          final deposit = _num(r['depositAmount']);
          final refundId = (r['depositRefund']?['refundId'] ?? r['depositRefund']?['id'] ?? r['refundId'])?.toString();
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(code, style: const TextStyle(fontWeight: FontWeight.w800))),
                    Text(status, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF4338CA))),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Tiền cọc: ${CurrencyFormatter.format(deposit)}', style: const TextStyle(fontSize: 12.5)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (status == 'PENDING_HANDOVER' || status == 'PAID')
                      FilledButton(
                        onPressed: () => _showAssignFulfillmentDialog(r),
                        child: const Text('Gán nút bàn giao'),
                      ),
                    if (status == 'PENDING_HANDOVER')
                      OutlinedButton(
                        onPressed: () async {
                          try {
                            await _api.handoverRental(rid);
                            _snack('Đã xác nhận bàn giao & kích hoạt hợp đồng!');
                            _loadAll();
                          } catch (e) {
                            _snack(e is ApiException ? e.message : 'Bàn giao thất bại.', error: true);
                          }
                        },
                        child: const Text('Xác nhận bàn giao'),
                      ),
                    if (refundId != null && refundId.isNotEmpty) ...[
                      OutlinedButton(
                        onPressed: () async {
                          try {
                            await _api.approveDepositRefund(refundId);
                            _snack('Đã duyệt hoàn tiền cọc!');
                            _loadAll();
                          } catch (e) {
                            _snack(e is ApiException ? e.message : 'Duyệt hoàn cọc thất bại.', error: true);
                          }
                        },
                        child: const Text('Duyệt hoàn cọc'),
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            await _api.confirmDepositRefundPayout(refundId);
                            _snack('Đã xác nhận chi trả hoàn cọc!');
                            _loadAll();
                          } catch (e) {
                            _snack(e is ApiException ? e.message : 'Xác nhận chi trả thất bại.', error: true);
                          }
                        },
                        child: const Text('Xác nhận Payout'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPackagesAndPlansTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Gói thuê nút IoT', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              FilledButton.icon(
                onPressed: () => _showPackageFormDialog(),
                icon: const Icon(LucideIcons.plus, size: 15),
                label: const Text('Tạo gói'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final p in _packages)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: ListTile(
                title: Text((p['packageName'] ?? p['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${p['buttonQuantity'] ?? 1} nút · ${CurrencyFormatter.format(_num(p['monthlyPrice']))}/tháng · Cọc ${CurrencyFormatter.format(_num(p['depositFee']))}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(LucideIcons.pencil, size: 17),
                  onPressed: () => _showPackageFormDialog(editing: p),
                ),
              ),
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text('Gói cước gian hàng', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              FilledButton.icon(
                onPressed: () => _showPlanFormDialog(),
                icon: const Icon(LucideIcons.plus, size: 15),
                label: const Text('Tạo cước'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final pl in _plans)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: ListTile(
                title: Text((pl['planName'] ?? pl['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${CurrencyFormatter.format(_num(pl['price']))} / ${pl['durationDays'] ?? 30} ngày · Tối đa ${pl['maxProducts'] ?? '∞'} SP',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(LucideIcons.pencil, size: 17),
                  onPressed: () => _showPlanFormDialog(editing: pl),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEkycTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _ekycSessions.isEmpty ? 1 : _ekycSessions.length,
        itemBuilder: (_, idx) {
          if (_ekycSessions.isEmpty) {
            return const ACard(child: Text('Chưa có phiên xác minh danh tính Didit nào.', style: SampleA.caption));
          }
          final s = _ekycSessions[idx];
          final sid = (s['sessionId'] ?? s['id'] ?? '').toString();
          final status = (s['status'] ?? s['decision'] ?? 'PENDING').toString();
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: ListTile(
              title: Text('Phiên eKYC #$sid', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Trạng thái: $status · User: ${s['userId'] ?? ''}'),
              trailing: IconButton(
                icon: const Icon(LucideIcons.trash2, size: 17, color: Color(0xFFDC2626)),
                onPressed: () async {
                  try {
                    await _api.deleteIdentitySession(sid);
                    _snack('Đã xóa phiên eKYC #$sid');
                    _loadAll();
                  } catch (e) {
                    _snack(e is ApiException ? e.message : 'Xóa phiên thất bại.', error: true);
                  }
                },
              ),
            ),
          );
        },
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
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
