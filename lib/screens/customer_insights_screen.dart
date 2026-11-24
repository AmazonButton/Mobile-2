import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';
import '../utils/formatters.dart';
import '../widgets/sample_a.dart';
import 'store_catalog_screen.dart';

/// Màn hình Thống kê tiêu dùng & Cửa hàng của khách hàng (GET /customers/me/dashboard, analytics/orders, me/stores).
class CustomerInsightsScreen extends StatefulWidget {
  const CustomerInsightsScreen({super.key});

  @override
  State<CustomerInsightsScreen> createState() => _CustomerInsightsScreenState();
}

class _CustomerInsightsScreenState extends State<CustomerInsightsScreen> {
  final _client = ApiClient();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _dashboard = {};
  Map<String, dynamic> _orderAnalytics = {};
  List<Map<String, dynamic>> _stores = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _client.get(ApiConfig.customerDashboard).catchError((_) => <String, dynamic>{}),
        _client.get(ApiConfig.customerAnalyticsOrders).catchError((_) => <String, dynamic>{}),
        _client.get(ApiConfig.customerStores).catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;
      final dash = results[0];
      final ord = results[1];
      final st = results[2];
      final rawStores = st is Map
          ? (st['data'] is List
                ? st['data'] as List
                : (st['items'] is List ? st['items'] as List : const []))
          : (st is List ? st : const []);
      setState(() {
        _dashboard = dash is Map && dash['data'] is Map
            ? Map<String, dynamic>.from(dash['data'] as Map)
            : (dash is Map ? Map<String, dynamic>.from(dash) : {});
        _orderAnalytics = ord is Map && ord['data'] is Map
            ? Map<String, dynamic>.from(ord['data'] as Map)
            : (ord is Map ? Map<String, dynamic>.from(ord) : {});
        _stores = rawStores
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : 'Không thể tải dữ liệu thống kê.';
      });
    }
  }

  num _num(dynamic v) => v is num ? v : (num.tryParse(v?.toString() ?? '') ?? 0);

  @override
  Widget build(BuildContext context) {
    final totalOrders = _num(
      _dashboard['totalOrders'] ?? _orderAnalytics['totalOrders'],
    ).round();
    final totalSpent = _num(
      _dashboard['totalSpent'] ??
          _dashboard['totalSpending'] ??
          _orderAnalytics['totalSpent'] ??
          _orderAnalytics['totalRevenue'],
    );
    final activeButtons = _num(
      _dashboard['activeDevices'] ?? _dashboard['activeButtons'],
    ).round();
    final activeRentals = _num(_dashboard['activeRentals']).round();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text(
          'Thống kê & Cửa hàng của tôi',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(LucideIcons.refreshCw, size: 18),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _load, child: const Text('Thử lại')),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Tổng quan hoạt động',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _statCard('Tổng đơn hàng', '$totalOrders', const Color(0xFF0E6BA8)),
                      const SizedBox(width: 10),
                      _statCard(
                        'Tổng chi tiêu',
                        CurrencyFormatter.format(totalSpent),
                        const Color(0xFF059669),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _statCard('Nút đang hoạt động', '$activeButtons', const Color(0xFF2563EB)),
                      const SizedBox(width: 10),
                      _statCard('Hợp đồng thuê', '$activeRentals', const Color(0xFF7C3AED)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Cửa hàng quen dùng (${_stores.length})',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  if (_stores.isEmpty)
                    const ACard(
                      child: Text(
                        'Bạn chưa có lịch sử giao dịch tại cửa hàng nào.',
                        style: SampleA.caption,
                      ),
                    )
                  else
                    for (final item in _stores) ...[
                      Builder(
                        builder: (_) {
                          final store = item['store'] is Map
                              ? Map<String, dynamic>.from(item['store'] as Map)
                              : item;
                          final sName = (store['name'] ?? store['storeName'] ?? 'Cửa hàng').toString();
                          final sAddr = (store['address'] ?? '').toString();
                          final ordersCount = item['totalOrders'] ?? item['orderCount'];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: ListTile(
                              leading: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(LucideIcons.store, color: Color(0xFF2563EB)),
                              ),
                              title: Text(
                                sName,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                              subtitle: Text(
                                [
                                  if (sAddr.isNotEmpty) sAddr,
                                  if (ordersCount != null) '$ordersCount đơn đã đặt',
                                ].join(' • '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: const Icon(LucideIcons.chevronRight, size: 16),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => StoreCatalogScreen(store: store),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                ],
              ),
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
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
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
