import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../models/button_product_model.dart';
import '../models/order_model.dart';
import '../providers/address_provider.dart';
import '../providers/device_provider.dart';
import '../providers/order_provider.dart';
import '../providers/user_provider.dart';
import '../services/api_client.dart';
import '../services/orders_api_service.dart';
import '../services/products_api_service.dart';
import '../widgets/sample_a.dart';
import '../widgets/smart_order_tour.dart';
import 'orders/widgets/payos_qr_payment_sheet.dart';
import 'store_product_assignment.dart';

class StoreCatalogScreen extends StatefulWidget {
  final Map<String, dynamic> store;
  final SmartOrderTour? tour;
  const StoreCatalogScreen({super.key, required this.store, this.tour});
  @override
  State<StoreCatalogScreen> createState() => _StoreCatalogScreenState();
}

class _StoreCatalogScreenState extends State<StoreCatalogScreen> {
  static final Map<String, ({List<Map<String, dynamic>> rows, DateTime at})>
      _discountCache = {};
  static const Duration _discountTtl = Duration(minutes: 5);

  late Future<List<Map<String, dynamic>>> _products;
  String _query = '';
  bool _assigning = false;
  bool _checkingOut = false;
  final Map<String, int> _cartQty = {};
  final Map<String, Map<String, dynamic>> _cartItems = {};
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounceTimer;

  int get _totalCartCount => _cartQty.values.fold(0, (a, b) => a + b);

  num _unitPrice(Map<String, dynamic> raw) {
    final discounted = raw['_discountedPrice'] as num?;
    if (discounted != null && discounted > 0) return discounted;
    return num.tryParse('${raw['basePrice'] ?? raw['price'] ?? 0}') ?? 0;
  }

  num get _totalCartAmount {
    num total = 0;
    for (final entry in _cartQty.entries) {
      final raw = _cartItems[entry.key];
      if (raw != null && entry.value > 0) {
        total += _unitPrice(raw) * entry.value;
      }
    }
    return total;
  }

  void _addToCart(Map<String, dynamic> raw) {
    final pid = (raw['productId'] ?? raw['id'] ?? '').toString();
    if (pid.isEmpty) return;
    setState(() {
      _cartItems[pid] = raw;
      _cartQty[pid] = (_cartQty[pid] ?? 0) + 1;
    });
  }

  void _changeCartQty(String pid, int delta) {
    final next = (_cartQty[pid] ?? 0) + delta;
    setState(() {
      if (next <= 0) {
        _cartQty.remove(pid);
        _cartItems.remove(pid);
      } else {
        _cartQty[pid] = next;
      }
    });
  }

  Future<void> _openCheckoutSheet() async {
    if (_cartQty.isEmpty || _checkingOut) return;
    final userProv = context.read<UserProvider?>();
    final addrProv = context.read<AddressProvider?>();
    final nameCtrl = TextEditingController(text: userProv?.name ?? '');
    final phoneCtrl = TextEditingController(text: userProv?.phone ?? '');
    final addressCtrl = TextEditingController(
      text: addrProv?.currentAddressDisplay.isNotEmpty == true
          ? addrProv!.currentAddressDisplay
          : (userProv?.address ?? ''),
    );
    final noteCtrl = TextEditingController();
    String paymentMethod = 'COD';

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheetState) {
            final entries = _cartQty.entries
                .where((e) => e.value > 0 && _cartItems[e.key] != null)
                .toList();
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Giỏ hàng & Đặt mua ngay',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(LucideIcons.x, size: 18),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    for (final entry in entries) ...[
                      Builder(
                        builder: (_) {
                          final raw = _cartItems[entry.key]!;
                          final title =
                              (raw['productName'] ?? raw['name'] ?? 'Sản phẩm')
                                  .toString();
                          final price = _unitPrice(raw);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                      Text(
                                        _formatVnd(price),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF2563EB),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    _changeCartQty(entry.key, -1);
                                    if (_cartQty.isEmpty) {
                                      Navigator.pop(ctx);
                                    } else {
                                      setSheetState(() {});
                                    }
                                  },
                                  icon: const Icon(
                                    LucideIcons.minusCircle,
                                    size: 18,
                                  ),
                                ),
                                Text(
                                  '${entry.value}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    _changeCartQty(entry.key, 1);
                                    setSheetState(() {});
                                  },
                                  icon: const Icon(
                                    LucideIcons.plusCircle,
                                    size: 18,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                    const Divider(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên người nhận *',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Số điện thoại nhận hàng *',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: addressCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Địa chỉ giao hàng *',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ghi chú cho cửa hàng (tuỳ chọn)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Phương thức thanh toán',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Tiền mặt (COD)'),
                            selected: paymentMethod == 'COD',
                            onSelected: (_) =>
                                setSheetState(() => paymentMethod = 'COD'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Chuyển khoản PayOS'),
                            selected: paymentMethod == 'PAYOS',
                            onSelected: (_) =>
                                setSheetState(() => paymentMethod = 'PAYOS'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Tổng tạm tính',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          _formatVnd(_totalCartAmount),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _checkingOut
                          ? null
                          : () async {
                              final cName = nameCtrl.text.trim();
                              final cPhone = phoneCtrl.text.trim();
                              final cAddr = addressCtrl.text.trim();
                              if (cName.isEmpty ||
                                  cPhone.isEmpty ||
                                  cAddr.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: Color(0xFFDC2626),
                                    content: Text(
                                      'Vui lòng nhập đầy đủ tên, SĐT và địa chỉ nhận hàng.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              setSheetState(() => _checkingOut = true);
                              setState(() => _checkingOut = true);
                              try {
                                final orderItems = _cartQty.entries
                                    .where((e) => e.value > 0)
                                    .map(
                                      (e) => {
                                        'productId':
                                            int.tryParse(e.key) ?? e.key,
                                        'quantity': e.value,
                                      },
                                    )
                                    .toList();
                                final body = <String, dynamic>{
                                  'storeId': int.tryParse(_storeId) ?? _storeId,
                                  'items': orderItems,
                                  'customerName': cName,
                                  'customerPhone': cPhone,
                                  'deliveryAddress': cAddr,
                                  'paymentMethod': paymentMethod,
                                  if (noteCtrl.text.trim().isNotEmpty)
                                    'orderNote': noteCtrl.text.trim(),
                                };
                                final res = await OrdersApiService()
                                    .createStorefrontOrder(body: body);
                                if (!mounted) return;
                                final orderData = res['order'] is Map
                                    ? Map<String, dynamic>.from(
                                        res['order'] as Map,
                                      )
                                    : res;
                                setState(() {
                                  _cartQty.clear();
                                  _cartItems.clear();
                                });
                                context.read<OrderProvider?>()?.loadOrders();
                                if (ctx.mounted) Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: Color(0xFF059669),
                                    content: Text(
                                      'Đặt hàng trực tiếp thành công!',
                                    ),
                                  ),
                                );
                                if (paymentMethod == 'PAYOS' &&
                                    (orderData['orderId'] ?? orderData['id']) !=
                                        null) {
                                  await PayosQrPaymentSheet.show(
                                    context,
                                    order: OrderModel.fromJson(orderData),
                                  );
                                }
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: const Color(0xFFDC2626),
                                    content: Text(
                                      e is ApiException
                                          ? e.message
                                          : 'Đặt hàng thất bại. Vui lòng thử lại.',
                                    ),
                                  ),
                                );
                              } finally {
                                if (mounted) {
                                  setState(() => _checkingOut = false);
                                }
                                if (ctx.mounted) {
                                  setSheetState(() => _checkingOut = false);
                                }
                              }
                            },
                      icon: const Icon(LucideIcons.shoppingBag, size: 17),
                      label: Text(
                        _checkingOut ? 'Đang gửi đơn...' : 'Xác nhận đặt hàng',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    } finally {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      addressCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  String get _storeId =>
      (widget.store['storeId'] ?? widget.store['id']).toString();
  @override
  void initState() {
    super.initState();
    _products = _load();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    if (mounted) {
      setState(() => _query = value.trim().toLowerCase());
    }
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final id = (widget.store['storeId'] ?? widget.store['id'])?.toString();
    if (id == null || id.isEmpty) throw StateError('Thiếu mã cửa hàng');
    final rows = await ProductsApiService().getProducts(storeId: id);
    var products = rows
        .whereType<Map>()
        .where((p) => p['status'] == 'ACTIVE' && p['storeId']?.toString() == id)
        .map((p) => Map<String, dynamic>.from(p))
        .toList();
    if (products.isEmpty) {
      // Fallback: Nếu cửa hàng chưa đăng sản phẩm riêng, hiển thị danh mục sản phẩm đang mở bán
      final allRows = await ProductsApiService().getProducts();
      products = allRows
          .whereType<Map>()
          .where((p) => p['status'] == 'ACTIVE')
          .map((p) => Map<String, dynamic>.from(p))
          .toList();
    }

    // Đồng bộ ưu đãi giảm giá có cache 5 phút & giới hạn đồng thời tránh bão N+1
    final now = DateTime.now();
    final discountTargets = products.take(15).toList();
    const batchSize = 5;
    for (var i = 0; i < discountTargets.length; i += batchSize) {
      final slice = discountTargets.skip(i).take(batchSize).toList();
      await Future.wait(
        slice.map((p) async {
          final pid = (p['productId'] ?? p['id'] ?? '').toString();
          if (pid.isEmpty) return;
          final cached = _discountCache[pid];
          List<Map<String, dynamic>> discounts;
          if (cached != null && now.difference(cached.at) < _discountTtl) {
            discounts = cached.rows;
          } else {
            discounts = await ProductsApiService()
                .getProductDiscounts(pid)
                .timeout(
                  const Duration(milliseconds: 1200),
                  onTimeout: () => const [],
                );
            _discountCache[pid] = (rows: discounts, at: now);
          }
          for (final d in discounts) {
            if (d['status'] != 'ACTIVE') continue;
            final start = DateTime.tryParse(d['startAt']?.toString() ?? '');
            final end = DateTime.tryParse(d['endAt']?.toString() ?? '');
            if (start != null &&
                end != null &&
                !now.isBefore(start) &&
                !now.isAfter(end)) {
              final basePrice =
                  num.tryParse('${p['basePrice'] ?? p['price'] ?? 0}') ?? 0;
              final pct = num.tryParse('${d['discountPercent'] ?? ''}');
              final amt = num.tryParse('${d['discountAmount'] ?? ''}');
              final reduction = pct != null
                  ? (basePrice * pct / 100).round()
                  : (amt ?? 0).round();
              final finalPrice = (basePrice - reduction).clamp(0, basePrice);
              if (finalPrice < basePrice) {
                p['_discountedPrice'] = finalPrice;
                p['_discountBadge'] =
                    pct != null ? '-${pct.round()}%' : '-$reduction ₫';
              }
              break;
            }
          }
        }),
      );
    }

    return products;
  }

  String? _image(Map p) {
    final images = p['images'];
    final candidates = [
      p['imageUrl'],
      p['thumbnailUrl'],
      if (images is List) ...[
        ...images
            .whereType<Map>()
            .where((i) => i['isThumbnail'] == true)
            .map((i) => i['imageUrl'] ?? i['url']),
        ...images.map((i) => i is Map ? i['imageUrl'] ?? i['url'] : i),
      ],
    ];
    for (final value in candidates) {
      final uri = Uri.tryParse(value?.toString() ?? '');
      if (uri != null &&
          ['https', 'http'].contains(uri.scheme) &&
          uri.host.isNotEmpty) {
        return uri.toString();
      }
    }
    return null;
  }

  Future<void> _assign(Map<String, dynamic> raw) async {
    if (_assigning) return;
    setState(() => _assigning = true);
    try {
      final provider = context.read<DeviceProvider>();
      final product = ButtonProductModel.fromJson(raw);
      final saved = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        builder: (_) => StoreProductAssignment(
          provider: provider,
          storeId: _storeId,
          storeName: widget.store['name']?.toString() ?? 'Cửa hàng',
          product: product,
          imageUrl: _image(raw),
        ),
      );
      if (saved != true || !mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Đã gán ${product.name} vào nút')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể thêm sản phẩm vào nút. Vui lòng thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final distance = widget.store['distanceKm'] as num?;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          widget.store['name']?.toString() ?? 'Cửa hàng',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          if (_totalCartCount > 0)
            IconButton(
              tooltip: 'Giỏ hàng',
              onPressed: _openCheckoutSheet,
              icon: Badge(
                label: Text('$_totalCartCount'),
                child: const Icon(LucideIcons.shoppingCart),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _totalCartCount > 0
          ? SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_totalCartCount sản phẩm trong giỏ',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _formatVnd(_totalCartAmount),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _openCheckoutSheet,
                      icon: const Icon(LucideIcons.shoppingBag, size: 16),
                      label: const Text('Đặt mua ngay'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: AContent(
        maxWidth: SampleA.listWidth,
        child: RefreshIndicator(
          onRefresh: () async {
            final future = _load();
            setState(() => _products = future);
            await future;
          },
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 140,
                  child:
                      (widget.store['coverImageUrl'] ??
                              widget.store['imageUrl']) !=
                          null
                      ? CachedNetworkImage(
                          imageUrl: (widget.store['coverImageUrl'] ??
                                  widget.store['imageUrl'])
                              .toString(),
                          fit: BoxFit.cover,
                          memCacheWidth: 720,
                          errorWidget: (_, _, _) => _storePlaceholder(),
                        )
                      : _storePlaceholder(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Sản phẩm của cửa hàng',
                key: widget.tour?.key(TourStep.catalog),
                style: SampleA.section,
              ),
              if (distance != null)
                Text(
                  '${distance.toStringAsFixed(1)} km đường thẳng từ địa chỉ của bạn',
                  style: SampleA.caption,
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Tìm trong cửa hàng',
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18, color: Color(0xFF94A3B8)),
                          onPressed: () {
                            _searchCtrl.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE0E8F5)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _products,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Shimmer.fromColors(
                      baseColor: const Color(0xFFE2E8F0),
                      highlightColor: const Color(0xFFF1F5F9),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: List.generate(
                          4,
                          (index) => Container(
                            width: 160,
                            height: 200,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Column(
                      children: [
                        const Text('Không thể tải sản phẩm của cửa hàng.'),
                        TextButton(
                          onPressed: () => setState(() => _products = _load()),
                          child: const Text('Thử lại'),
                        ),
                      ],
                    );
                  }
                  final products = (snapshot.data ?? [])
                      .where(
                        (p) =>
                            '${p['productName'] ?? p['name'] ?? ''} ${p['description'] ?? ''}'
                                .toLowerCase()
                                .contains(_query),
                      )
                      .toList();
                  return Column(
                    children: [
                      ASectionHeader(
                        title: 'Sản phẩm',
                        action: Text('${products.length} sản phẩm'),
                      ),
                      const SizedBox(height: 12),
                      if (products.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Không có sản phẩm phù hợp.'),
                        )
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final width =
                                MediaQuery.textScalerOf(context).scale(14) >
                                        21 ||
                                    constraints.maxWidth < 300
                                ? constraints.maxWidth
                                : (constraints.maxWidth -
                                          12 *
                                              ((constraints.maxWidth / 220)
                                                      .floor()
                                                      .clamp(2, 4) -
                                                  1)) /
                                      (constraints.maxWidth / 220)
                                          .floor()
                                          .clamp(2, 4);
                            return Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: products
                                  .map(
                                    (raw) => SizedBox(
                                      width: width,
                                      child: _productRow(raw),
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _storePlaceholder() => Container(
    color: SampleA.pale,
    alignment: Alignment.center,
    child: const Icon(Icons.storefront, size: 64, color: SampleA.primary),
  );

  String _formatVnd(num amount) {
    final s = amount.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '$bufđ';
  }

  Widget _productRow(Map<String, dynamic> raw) {
    final product = ButtonProductModel.fromJson(raw);
    final url = _image(raw);
    final discounted = raw['_discountedPrice'] as num?;
    final discountBadge = raw['_discountBadge'] as String?;
    final inv = raw['inventory'];
    final hasStockField = (inv is Map && inv['quantityOnHand'] != null) ||
        raw['stockQuantity'] != null ||
        raw['stock'] != null;
    final onHand = int.tryParse(
          ((inv is Map ? inv['quantityOnHand'] : null) ??
                  raw['stockQuantity'] ??
                  raw['stock'] ??
                  99)
              .toString(),
        ) ??
        99;
    final reserved = int.tryParse(
          ((inv is Map ? inv['quantityReserved'] : null) ??
                  raw['reservedStock'] ??
                  0)
              .toString(),
        ) ??
        0;
    final isOutOfStock = (hasStockField && (onHand - reserved) <= 0) ||
        (raw['status'] != null &&
            raw['status'].toString().toUpperCase() != 'ACTIVE');

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isOutOfStock ? const Color(0xFFFAFAFA) : Colors.white,
        border: Border.all(
          color: isOutOfStock ? const Color(0xFFFECACA) : SampleA.border,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Opacity(
                opacity: isOutOfStock ? 0.45 : 1.0,
                child: SizedBox(
                  height: 105,
                  width: double.infinity,
                  child: url == null
                      ? const Icon(
                          Icons.inventory_2_outlined,
                          size: 48,
                          color: SampleA.muted,
                        )
                      : CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.contain,
                          memCacheWidth: 320,
                          errorWidget: (_, _, _) =>
                              const Icon(Icons.inventory_2_outlined, size: 48),
                        ),
                ),
              ),
              if (isOutOfStock)
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Hết hàng',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              if (discountBadge != null && !isOutOfStock)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      discountBadge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(product.name, style: SampleA.body.copyWith(fontSize: 14)),
          const SizedBox(height: 4),
          if (discounted != null)
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _formatVnd(discounted),
                  style: SampleA.body.copyWith(
                    color: SampleA.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  product.priceFormatted,
                  style: SampleA.caption.copyWith(
                    decoration: TextDecoration.lineThrough,
                    color: const Color(0xFF94A3B8),
                    fontSize: 11,
                  ),
                ),
              ],
            )
          else
            Text(
              product.priceFormatted,
              style: SampleA.body.copyWith(
                color: SampleA.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          const SizedBox(height: 6),
          Builder(
            builder: (_) {
              final pid = (raw['productId'] ?? raw['id'] ?? '').toString();
              final inCart = _cartQty[pid] ?? 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: isOutOfStock ? null : () => _addToCart(raw),
                    icon: const Icon(LucideIcons.shoppingCart, size: 13),
                    label: Text(
                      isOutOfStock
                          ? 'Hết hàng'
                          : (inCart > 0 ? 'Thêm ($inCart)' : 'Mua ngay'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: SampleA.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      minimumSize: const Size(double.infinity, 34),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  OutlinedButton(
                    onPressed: (_assigning || isOutOfStock) ? null : () => _assign(raw),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          isOutOfStock ? const Color(0xFF94A3B8) : SampleA.primary,
                      side: BorderSide(
                        color: isOutOfStock
                            ? const Color(0xFFCBD5E1)
                            : SampleA.primary,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      minimumSize: const Size(double.infinity, 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    child: Text(
                      isOutOfStock ? 'Tạm hết hàng' : 'Gán vào nút',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
