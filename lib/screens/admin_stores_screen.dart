import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shimmer/shimmer.dart';
import '../services/admin_api_service.dart';
import '../services/api_client.dart';
import '../services/stores_api_service.dart';
import '../widgets/app_motion.dart';
import '../widgets/sample_a.dart';

/// Màn hình Quản trị & Phê duyệt Cửa hàng đối tác dành riêng cho ADMIN / SUPER_ADMIN.
class AdminStoresScreen extends StatefulWidget {
  const AdminStoresScreen({super.key});

  @override
  State<AdminStoresScreen> createState() => _AdminStoresScreenState();
}

class _AdminStoresScreenState extends State<AdminStoresScreen> {
  final _adminApi = AdminApiService();
  final _storesApi = StoresApiService();
  List<Map<String, dynamic>> _stores = [];
  bool _loading = true;
  bool _limitedAccessNotice = false;
  String? _error;
  String _search = '';
  String _statusFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _limitedAccessNotice = false;
    });
    try {
      List<Map<String, dynamic>> list;
      try {
        list = await _adminApi.listStores(pageSize: 50);
      } on ApiException catch (e) {
        if (e.statusCode == 403) {
          // Non-SUPER_ADMIN fallback: vẫn hiển thị cửa hàng ACTIVE nhưng báo rõ giới hạn quyền
          final raw = await _storesApi.getStores();
          list = raw
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
          if (mounted) _limitedAccessNotice = true;
        } else {
          rethrow;
        }
      }
      if (!mounted) return;
      setState(() {
        _stores = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : 'Không thể tải danh sách cửa hàng đối tác.';
        _loading = false;
      });
    }
  }

  Future<void> _approveStore(String storeId, BuildContext sheetCtx) async {
    try {
      await _adminApi.approveStore(storeId);
      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
      _snack('Đã phê duyệt cửa hàng thành công!');
      _load();
    } catch (e) {
      _snack(e is ApiException ? e.message : 'Phê duyệt thất bại.', error: true);
    }
  }

  Future<void> _rejectStore(String storeId, BuildContext sheetCtx) async {
    final reasonCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Từ chối cửa hàng', style: TextStyle(fontWeight: FontWeight.w800)),
          content: TextField(
            controller: reasonCtrl,
            decoration: const InputDecoration(labelText: 'Lý do từ chối'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Từ chối'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await _adminApi.rejectStore(storeId, reason: reasonCtrl.text);
      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
      _snack('Đã từ chối cửa hàng.');
      _load();
    } catch (e) {
      _snack(e is ApiException ? e.message : 'Từ chối thất bại.', error: true);
    } finally {
      reasonCtrl.dispose();
    }
  }

  Future<void> _setStoreStatus(String storeId, String status, BuildContext sheetCtx) async {
    try {
      await _adminApi.updateStore(storeId, status: status);
      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
      _snack('Đã chuyển trạng thái cửa hàng sang $status');
      _load();
    } catch (e) {
      _snack(e is ApiException ? e.message : 'Cập nhật trạng thái thất bại.', error: true);
    }
  }

  void _showStoreDetail(Map<String, dynamic> store) {
    HapticFeedback.selectionClick();
    final storeId = (store['storeId'] ?? store['id'] ?? '').toString();
    final name = (store['name'] ?? 'Cửa hàng').toString();
    final code = (store['code'] ?? '—').toString();
    final status = (store['status'] ?? 'ACTIVE').toString().toUpperCase();
    final phone = (store['phone'] ?? 'Chưa cập nhật').toString();
    final email = (store['email'] ?? 'Chưa cập nhật').toString();
    final address = (store['address'] ?? 'Chưa cập nhật địa chỉ').toString();
    final commission = store['commissionRate']?.toString();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(LucideIcons.store, color: Color(0xFF4338CA), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Mã đại lý: $code · $status',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 14),
                _detailRow(LucideIcons.mapPin, 'Địa chỉ', address),
                _detailRow(LucideIcons.phone, 'Số điện thoại', phone),
                _detailRow(LucideIcons.mail, 'Email', email),
                if (commission != null && commission.isNotEmpty)
                  _detailRow(LucideIcons.percent, 'Chiết khấu sàn', '$commission%'),
                const SizedBox(height: 14),
                if (storeId.isNotEmpty && !_limitedAccessNotice) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (status == 'PENDING' || status == 'PENDING_APPROVAL') ...[
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                          onPressed: () => _approveStore(storeId, ctx),
                          icon: const Icon(LucideIcons.checkCircle2, size: 16),
                          label: const Text('Phê duyệt'),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                          onPressed: () => _rejectStore(storeId, ctx),
                          icon: const Icon(LucideIcons.xCircle, size: 16),
                          label: const Text('Từ chối'),
                        ),
                      ],
                      if (status == 'ACTIVE')
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                          onPressed: () => _setStoreStatus(storeId, 'SUSPENDED', ctx),
                          icon: const Icon(LucideIcons.pauseCircle, size: 16),
                          label: const Text('Tạm khóa cửa hàng'),
                        )
                      else if (status == 'SUSPENDED' || status == 'INACTIVE')
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4338CA)),
                          onPressed: () => _setStoreStatus(storeId, 'ACTIVE', ctx),
                          icon: const Icon(LucideIcons.playCircle, size: 16),
                          label: const Text('Kích hoạt lại'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                AButton(
                  label: 'Đóng',
                  kind: AButtonKind.secondary,
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF64748B)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _stores
        .where((s) => (s['status'] ?? 'ACTIVE').toString().toUpperCase() == 'ACTIVE')
        .length;
    final inactiveCount = _stores.length - activeCount;

    final filtered = _stores.where((s) {
      final st = (s['status'] ?? 'ACTIVE').toString().toUpperCase();
      if (_statusFilter == 'ACTIVE' && st != 'ACTIVE') return false;
      if (_statusFilter == 'OTHER' && st == 'ACTIVE') return false;
      if (_search.trim().isNotEmpty) {
        final q = _search.trim().toLowerCase();
        final name = (s['name'] ?? '').toString().toLowerCase();
        final code = (s['code'] ?? '').toString().toLowerCase();
        final email = (s['email'] ?? '').toString().toLowerCase();
        final addr = (s['address'] ?? '').toString().toLowerCase();
        return name.contains(q) || code.contains(q) || email.contains(q) || addr.contains(q);
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: AContent(
        maxWidth: SampleA.listWidth,
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _load,
            color: const Color(0xFF4338CA),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: 1 + (_loading || _error != null || filtered.isEmpty ? 1 : filtered.length),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Cửa hàng đối tác', style: SampleA.title),
                                SizedBox(height: 3),
                                Text(
                                  'Giám sát & phê duyệt đại lý trên toàn hệ thống',
                                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _loading ? null : _load,
                            tooltip: 'Làm mới',
                            icon: const Icon(LucideIcons.refreshCw, size: 19),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (_limitedAccessNotice) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: const Text(
                            'Tài khoản hiện tại chỉ có quyền xem danh sách công khai (cần quyền SUPER_ADMIN để xem & duyệt cửa hàng chờ duyệt).',
                            style: TextStyle(fontSize: 12.5, color: Color(0xFF92400E)),
                          ),
                        ),
                      ],
                      Row(
                        children: [
                          _kpiBox('Tổng đại lý', _stores.length, const Color(0xFF4338CA)),
                          const SizedBox(width: 10),
                          _kpiBox('Hoạt động', activeCount, const Color(0xFF059669)),
                          const SizedBox(width: 10),
                          _kpiBox('Khác', inactiveCount, const Color(0xFFD97706)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        onChanged: (v) => setState(() => _search = v),
                        decoration: InputDecoration(
                          hintText: 'Tìm tên cửa hàng, mã đại lý, email...',
                          prefixIcon: const Icon(LucideIcons.search, size: 18),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _filterChip('Tất cả', 'ALL'),
                            const SizedBox(width: 8),
                            _filterChip('Hoạt động', 'ACTIVE'),
                            const SizedBox(width: 8),
                            _filterChip('Chờ / Tạm dừng', 'OTHER'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  );
                }

                if (_loading) {
                  final skeleton = Column(
                    children: List.generate(
                      4,
                      (_) => Container(
                        height: 86,
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  );
                  return AppMotion.allowAmbient(context)
                      ? Shimmer.fromColors(
                          baseColor: const Color(0xFFE2E8F0),
                          highlightColor: Colors.white,
                          child: skeleton,
                        )
                      : skeleton;
                }

                if (_error != null) {
                  return ACard(
                    child: Column(
                      children: [
                        Text(_error!, style: SampleA.body),
                        const SizedBox(height: 12),
                        AButton(label: 'Thử lại', onPressed: _load),
                      ],
                    ),
                  );
                }

                if (filtered.isEmpty) {
                  return const ACard(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        children: [
                          Icon(LucideIcons.store, size: 36, color: Color(0xFF94A3B8)),
                          SizedBox(height: 8),
                          Text(
                            'Không tìm thấy cửa hàng phù hợp',
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final s = filtered[index - 1];
                final name = (s['name'] ?? 'Cửa hàng').toString();
                final code = (s['code'] ?? '').toString();
                final status = (s['status'] ?? 'ACTIVE').toString().toUpperCase();
                final active = status == 'ACTIVE';
                final address = (s['address'] ?? 'Chưa cập nhật địa chỉ').toString();
                final email = (s['email'] ?? '').toString();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TactilePress(
                    scaleDown: 0.985,
                    haptic: true,
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _showStoreDetail(s),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: AppMotion.cardShadow,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(LucideIcons.store, size: 20, color: Color(0xFF4338CA)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                      decoration: BoxDecoration(
                                        color: active ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        active ? 'Hoạt động' : status,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: active ? const Color(0xFF047857) : const Color(0xFFB45309),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  [
                                    if (code.isNotEmpty) code,
                                    if (email.isNotEmpty) email,
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF4338CA),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  address,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(LucideIcons.chevronRight, size: 17, color: Color(0xFF94A3B8)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _kpiBox(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: AppMotion.cardShadow,
        ),
        child: Column(
          children: [
            AnimatedCountText(
              value: value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final active = _statusFilter == value;
    return TactilePress(
      scaleDown: 0.95,
      haptic: true,
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        if (_statusFilter == value) return;
        setState(() => _statusFilter = value);
      },
      child: AnimatedContainer(
        duration: AppMotion.fastDuration,
        curve: AppMotion.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF4338CA) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? const Color(0xFF4338CA) : const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}
