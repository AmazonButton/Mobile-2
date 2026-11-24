import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../providers/notification_provider.dart';
import '../providers/user_provider.dart';
import '../services/api_client.dart';
import '../services/media_api_service.dart';
import '../services/merchant_api_service.dart';
import '../services/products_api_service.dart';
import '../services/stores_api_service.dart';
import '../widgets/app_motion.dart';
import '../widgets/sample_a.dart';

/// Màn hình Sản phẩm & tồn kho full CRUD dành riêng cho Chủ cửa hàng.
class StoreProductsScreen extends StatefulWidget {
  const StoreProductsScreen({super.key});

  @override
  State<StoreProductsScreen> createState() => _StoreProductsScreenState();
}

class _StoreProductsScreenState extends State<StoreProductsScreen> {
  final _merchantApi = MerchantApiService();
  final _picker = ImagePicker();

  String? _storeId;
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  String _stockFilter = 'ALL'; // ALL, IN_STOCK, LOW, OUT

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProducts());
  }

  Future<String?> _resolveStoreId() async {
    if (_storeId != null && _storeId!.isNotEmpty) return _storeId;
    String? storeId = context.read<UserProvider?>()?.storeId;
    if (storeId == null || storeId.isEmpty) {
      try {
        final myStore = await StoresApiService().getMyStore();
        storeId = (myStore['storeId'] ?? myStore['id'])?.toString();
      } catch (_) {}
    }
    _storeId = storeId;
    return storeId;
  }

  Future<void> _loadProducts() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final storeId = await _resolveStoreId();
      final results = await Future.wait([
        ProductsApiService().getProducts(storeId: storeId),
        if (storeId != null && storeId.isNotEmpty)
          _merchantApi.listCategories(storeId).catchError((_) => <Map<String, dynamic>>[]),
      ]);
      final raw = results[0];
      final list = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final cats = results.length > 1
          ? results[1]
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : _categories;
      if (!mounted) return;
      context.read<NotificationProvider?>()?.syncInventoryAlerts(list);
      setState(() {
        _products = list;
        _categories = cats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : 'Không thể tải danh sách sản phẩm của cửa hàng.';
        _loading = false;
      });
    }
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

  String _formatVnd(dynamic value) {
    final numVal = num.tryParse(value?.toString() ?? '') ?? 0;
    final str = numVal.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      final pos = str.length - i;
      buf.write(str[i]);
      if (pos > 1 && pos % 3 == 1) buf.write('.');
    }
    return '${buf.toString()} ₫';
  }

  int _availableStock(Map<String, dynamic> p) {
    final inv = p['inventory'];
    final onHand =
        int.tryParse(
          ((inv is Map ? inv['quantityOnHand'] : null) ??
                  p['stockQuantity'] ??
                  p['stock'] ??
                  p['availableQuantity'] ??
                  0)
              .toString(),
        ) ??
        0;
    final reserved =
        int.tryParse(
          ((inv is Map
                      ? (inv['reservedQuantity'] ?? inv['quantityReserved'])
                      : null) ??
                  p['reservedQuantity'] ??
                  p['reservedStock'] ??
                  0)
              .toString(),
        ) ??
        0;
    return (onHand - reserved) < 0 ? 0 : (onHand - reserved);
  }

  int _minStockAlert(Map<String, dynamic> p) {
    final inv = p['inventory'];
    return int.tryParse(
          ((inv is Map ? inv['minStockAlert'] : null) ??
                  p['minStockAlert'] ??
                  p['lowStockThreshold'] ??
                  5)
              .toString(),
        ) ??
        5;
  }

  Future<void> _openProductForm({Map<String, dynamic>? editing}) async {
    final isEdit = editing != null;
    final productId = editing != null ? (editing['productId'] ?? editing['id']).toString() : '';
    final nameCtrl = TextEditingController(
      text: (editing?['productName'] ?? editing?['name'] ?? '').toString(),
    );
    final skuCtrl = TextEditingController(
      text: (editing?['sku'] ?? editing?['productCode'] ?? '').toString(),
    );
    final priceCtrl = TextEditingController(
      text: (editing?['basePrice'] ?? editing?['price'] ?? '').toString(),
    );
    final stockCtrl = TextEditingController(
      text: isEdit ? _availableStock(editing).toString() : '20',
    );
    final unitCtrl = TextEditingController(
      text: (editing?['unit'] ?? 'Bình').toString(),
    );
    final descCtrl = TextEditingController(
      text: (editing?['description'] ?? '').toString(),
    );
    String imageUrl = (editing?['thumbnailUrl'] ?? editing?['imageUrl'] ?? '').toString();
    String selectedCatId = (editing?['categoryId'] ?? '').toString();
    if (selectedCatId.isNotEmpty &&
        !_categories.any((c) => (c['categoryId'] ?? c['id']).toString() == selectedCatId)) {
      selectedCatId = '';
    }
    bool uploadingImg = false;
    bool saving = false;

    try {
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
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
                      Expanded(
                        child: Text(
                          isEdit ? 'Chỉnh sửa sản phẩm' : 'Thêm sản phẩm mới',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        icon: const Icon(LucideIcons.x, size: 18),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: imageUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: 160,
                                errorWidget: (_, _, _) => const Icon(LucideIcons.image, color: Color(0xFF047857)),
                              )
                            : const Icon(LucideIcons.image, color: Color(0xFF047857)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: uploadingImg
                              ? null
                              : () async {
                                  final picked = await _picker.pickImage(
                                    source: ImageSource.gallery,
                                    maxWidth: 1024,
                                    imageQuality: 82,
                                  );
                                  if (picked == null) return;
                                  setSheet(() => uploadingImg = true);
                                  try {
                                    final url = await MediaApiService().uploadImage(
                                      File(picked.path),
                                      folder: 'products',
                                    );
                                    setSheet(() {
                                      imageUrl = url;
                                      uploadingImg = false;
                                    });
                                  } catch (e) {
                                    setSheet(() => uploadingImg = false);
                                    _snack(
                                      e is ApiException ? e.message : 'Tải ảnh lên thất bại.',
                                      error: true,
                                    );
                                  }
                                },
                          icon: const Icon(LucideIcons.upload, size: 16),
                          label: Text(
                            uploadingImg
                                ? 'Đang tải ảnh...'
                                : (imageUrl.isEmpty ? 'Chọn ảnh sản phẩm' : 'Đổi ảnh sản phẩm'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên sản phẩm *',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: priceCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Giá bán (VNĐ) *',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: stockCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Tồn kho',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: skuCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Mã SKU (tuỳ chọn)',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: unitCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Đơn vị',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_categories.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCatId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Danh mục',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('-- Không chọn --')),
                        ..._categories.map((c) {
                          final cid = (c['categoryId'] ?? c['id']).toString();
                          final cname = (c['categoryName'] ?? c['name'] ?? 'DM #$cid').toString();
                          return DropdownMenuItem(value: cid, child: Text(cname, overflow: TextOverflow.ellipsis));
                        }),
                      ],
                      onChanged: (v) => setSheet(() => selectedCatId = v ?? ''),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Mô tả sản phẩm',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: saving || uploadingImg
                        ? null
                        : () async {
                            final name = nameCtrl.text.trim();
                            final price = num.tryParse(priceCtrl.text.trim());
                            final stock = int.tryParse(stockCtrl.text.trim());
                            if (name.isEmpty || price == null || price < 0) {
                              _snack('Vui lòng nhập tên sản phẩm và giá bán hợp lệ.', error: true);
                              return;
                            }
                            setSheet(() => saving = true);
                            try {
                              final body = <String, dynamic>{
                                'productName': name,
                                'name': name,
                                'basePrice': price,
                                'price': price,
                                if (skuCtrl.text.trim().isNotEmpty) 'sku': skuCtrl.text.trim(),
                                if (unitCtrl.text.trim().isNotEmpty) 'unit': unitCtrl.text.trim(),
                                if (descCtrl.text.trim().isNotEmpty) 'description': descCtrl.text.trim(),
                                if (selectedCatId.isNotEmpty) 'categoryId': selectedCatId,
                                if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
                                if (!isEdit && stock != null) 'initialStock': stock,
                              };
                              if (isEdit) {
                                await _merchantApi.updateProduct(productId, body);
                                if (stock != null) {
                                  await _merchantApi.updateProductStock(
                                    productId,
                                    availableStock: stock,
                                  );
                                }
                              } else {
                                await _merchantApi.createProduct(body);
                              }
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } catch (e) {
                              setSheet(() => saving = false);
                              _snack(
                                e is ApiException ? e.message : 'Lưu sản phẩm thất bại.',
                                error: true,
                              );
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF047857),
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(saving ? 'Đang lưu...' : (isEdit ? 'Lưu thay đổi' : 'Tạo sản phẩm')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (saved == true) {
        _snack(isEdit ? 'Đã cập nhật sản phẩm!' : 'Đã tạo sản phẩm mới!');
        _loadProducts();
      }
    } finally {
      nameCtrl.dispose();
      skuCtrl.dispose();
      priceCtrl.dispose();
      stockCtrl.dispose();
      unitCtrl.dispose();
      descCtrl.dispose();
    }
  }

  Future<void> _openQuickStockDialog(Map<String, dynamic> p) async {
    final pid = (p['productId'] ?? p['id']).toString();
    final stockCtrl = TextEditingController(text: _availableStock(p).toString());
    final thresholdCtrl = TextEditingController(text: _minStockAlert(p).toString());
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            'Cập nhật tồn kho: ${p['name'] ?? p['productName']}',
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: stockCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Số lượng tồn kho khả dụng'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: thresholdCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Ngưỡng cảnh báo sắp hết'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cập nhật')),
          ],
        ),
      );
      if (ok != true) return;
      final qty = int.tryParse(stockCtrl.text.trim());
      if (qty == null || qty < 0) {
        _snack('Số lượng tồn kho không hợp lệ.', error: true);
        return;
      }
      await _merchantApi.updateProductStock(
        pid,
        availableStock: qty,
        lowStockThreshold: int.tryParse(thresholdCtrl.text.trim()),
      );
      _snack('Đã cập nhật tồn kho thành công!');
      _loadProducts();
    } catch (e) {
      _snack(e is ApiException ? e.message : 'Cập nhật tồn kho thất bại.', error: true);
    } finally {
      stockCtrl.dispose();
      thresholdCtrl.dispose();
    }
  }

  Future<void> _openDiscountsSheet(Map<String, dynamic> p) async {
    final pid = (p['productId'] ?? p['id']).toString();
    final pname = (p['name'] ?? p['productName'] ?? 'Sản phẩm').toString();
    final pctCtrl = TextEditingController(text: '10');
    final daysCtrl = TextEditingController(text: '7');
    List<Map<String, dynamic>> discounts = [];
    bool loading = true;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheet) {
            if (loading) {
              loading = false;
              _merchantApi.listDiscounts(pid).then((rows) {
                if (ctx.mounted) setSheet(() => discounts = rows);
              }).catchError((_) {});
            }
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
                    Text(
                      'Ưu đãi giảm giá: $pname',
                      style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: pctCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Giảm (%)',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: daysCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Số ngày áp dụng',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () async {
                            final pct = num.tryParse(pctCtrl.text.trim());
                            final days = (int.tryParse(daysCtrl.text.trim()) ?? 7).clamp(1, 365);
                            if (pct == null || pct <= 0 || pct > 100) {
                              _snack('Phần trăm giảm phải từ 1–100%.', error: true);
                              return;
                            }
                            try {
                              final now = DateTime.now();
                              await _merchantApi.createDiscount(
                                pid,
                                discountPercent: pct,
                                startAt: now,
                                endAt: now.add(Duration(days: days)),
                              );
                              final fresh = await _merchantApi.listDiscounts(pid);
                              if (ctx.mounted) setSheet(() => discounts = fresh);
                              _snack('Đã tạo chương trình giảm giá -$pct%!');
                            } catch (e) {
                              _snack(e is ApiException ? e.message : 'Tạo giảm giá thất bại.', error: true);
                            }
                          },
                          child: const Text('Thêm'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (discounts.isEmpty)
                      const Text(
                        'Chưa có chương trình giảm giá nào.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      )
                    else
                      for (final d in discounts)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            d['discountPercent'] != null
                                ? 'Giảm ${d['discountPercent']}%'
                                : 'Giảm ${_formatVnd(d['discountAmount'])}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text('Trạng thái: ${d['status']}'),
                          trailing: IconButton(
                            icon: const Icon(LucideIcons.trash2, size: 17, color: Color(0xFFDC2626)),
                            onPressed: () async {
                              final did = (d['discountId'] ?? d['id']).toString();
                              try {
                                await _merchantApi.deleteDiscount(did);
                                final fresh = await _merchantApi.listDiscounts(pid);
                                if (ctx.mounted) setSheet(() => discounts = fresh);
                              } catch (e) {
                                _snack(e is ApiException ? e.message : 'Xóa giảm giá thất bại.', error: true);
                              }
                            },
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
      pctCtrl.dispose();
      daysCtrl.dispose();
    }
  }

  Future<void> _openCategoriesSheet() async {
    final storeId = await _resolveStoreId();
    if (!mounted) return;
    if (storeId == null || storeId.isEmpty) {
      _snack('Không xác định được mã cửa hàng.', error: true);
      return;
    }
    final nameCtrl = TextEditingController();
    List<Map<String, dynamic>> cats = List.from(_categories);

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
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
                  const Text(
                    'Danh mục sản phẩm của cửa hàng',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Tên danh mục mới (VD: Nước uống 20L)',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          if (nameCtrl.text.trim().isEmpty) return;
                          try {
                            await _merchantApi.createCategory(
                              storeId,
                              categoryName: nameCtrl.text,
                            );
                            nameCtrl.clear();
                            final fresh = await _merchantApi.listCategories(storeId);
                            if (ctx.mounted) setSheet(() => cats = fresh);
                            if (mounted) setState(() => _categories = fresh);
                            _snack('Đã tạo danh mục mới!');
                          } catch (e) {
                            _snack(e is ApiException ? e.message : 'Tạo danh mục thất bại.', error: true);
                          }
                        },
                        child: const Text('Thêm'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (cats.isEmpty)
                    const Text(
                      'Chưa có danh mục nào.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    )
                  else
                    for (final c in cats)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(LucideIcons.folder, size: 18, color: Color(0xFF047857)),
                        title: Text(
                          (c['categoryName'] ?? c['name'] ?? '').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        trailing: IconButton(
                          icon: const Icon(LucideIcons.trash2, size: 17, color: Color(0xFFDC2626)),
                          onPressed: () async {
                            final cid = (c['categoryId'] ?? c['id']).toString();
                            try {
                              await _merchantApi.deleteCategory(cid);
                              final fresh = await _merchantApi.listCategories(storeId);
                              if (ctx.mounted) setSheet(() => cats = fresh);
                              if (mounted) setState(() => _categories = fresh);
                            } catch (e) {
                              _snack(e is ApiException ? e.message : 'Xóa danh mục thất bại.', error: true);
                            }
                          },
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      );
    } finally {
      nameCtrl.dispose();
    }
  }

  Future<void> _showProductActions(Map<String, dynamic> p) async {
    final pid = (p['productId'] ?? p['id']).toString();
    final pname = (p['name'] ?? p['productName'] ?? 'Sản phẩm').toString();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(pname, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('Giá: ${_formatVnd(p['basePrice'] ?? p['price'])} • Tồn: ${_availableStock(p)}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(LucideIcons.pencil, color: Color(0xFF047857)),
              title: const Text('Chỉnh sửa thông tin & ảnh'),
              onTap: () {
                Navigator.pop(ctx);
                _openProductForm(editing: p);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.boxes, color: Color(0xFF0E6BA8)),
              title: const Text('Cập nhật nhanh tồn kho'),
              onTap: () {
                Navigator.pop(ctx);
                _openQuickStockDialog(p);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.percent, color: Color(0xFFD97706)),
              title: const Text('Chương trình giảm giá'),
              onTap: () {
                Navigator.pop(ctx);
                _openDiscountsSheet(p);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.trash2, color: Color(0xFFDC2626)),
              title: const Text(
                'Ngừng kinh doanh sản phẩm',
                style: TextStyle(color: Color(0xFFDC2626)),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await _merchantApi.deactivateProduct(pid);
                  _snack('Đã chuyển sản phẩm sang trạng thái ngừng kinh doanh.');
                  _loadProducts();
                } catch (e) {
                  _snack(e is ApiException ? e.message : 'Thao tác thất bại.', error: true);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiCard(String label, int value, Color color) {
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
              style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800, color: color),
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

  Widget _stockChip(String label, String key) {
    final active = _stockFilter == key;
    return TactilePress(
      scaleDown: 0.95,
      haptic: true,
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        if (_stockFilter == key) return;
        setState(() => _stockFilter = key);
      },
      child: AnimatedContainer(
        duration: AppMotion.fastDuration,
        curve: AppMotion.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF047857) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? const Color(0xFF047857) : const Color(0xFFE2E8F0)),
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

  @override
  Widget build(BuildContext context) {
    final userProv = context.watch<UserProvider?>();
    final outOfStockItems = _products.where((p) => _availableStock(p) <= 0).toList();
    final lowStockItems = _products.where((p) {
      final avail = _availableStock(p);
      return avail > 0 && avail <= _minStockAlert(p);
    }).toList();

    final filtered = _products.where((p) {
      final avail = _availableStock(p);
      final minAlert = _minStockAlert(p);
      if (_stockFilter == 'OUT' && avail > 0) return false;
      if (_stockFilter == 'LOW' && (avail <= 0 || avail > minAlert)) return false;
      if (_stockFilter == 'IN_STOCK' && avail <= minAlert) return false;

      if (_search.trim().isNotEmpty) {
        final q = _search.trim().toLowerCase();
        final name = (p['name'] ?? p['productName'] ?? '').toString().toLowerCase();
        final sku = (p['sku'] ?? p['productCode'] ?? '').toString().toLowerCase();
        return name.contains(q) || sku.contains(q);
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openProductForm(),
        backgroundColor: const Color(0xFF047857),
        foregroundColor: Colors.white,
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('Thêm SP', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: AContent(
        maxWidth: SampleA.listWidth,
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _loadProducts,
            color: const Color(0xFF047857),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 88),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: 1 + (_loading || _error != null || filtered.isEmpty ? 1 : filtered.length),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Sản phẩm & tồn kho', style: SampleA.title),
                                const SizedBox(height: 4),
                                Text(
                                  userProv?.storeName?.isNotEmpty == true
                                      ? '${userProv!.storeName!} • ${_products.length} sản phẩm'
                                      : '${_products.length} sản phẩm đang quản lý',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _openCategoriesSheet,
                            icon: const Icon(LucideIcons.folderTree, size: 20),
                            tooltip: 'Quản lý danh mục',
                          ),
                          IconButton(
                            onPressed: _loading ? null : _loadProducts,
                            icon: const Icon(LucideIcons.refreshCw, size: 20),
                            tooltip: 'Làm mới',
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _kpiCard('Tổng SP', _products.length, const Color(0xFF047857)),
                          const SizedBox(width: 10),
                          _kpiCard('Sắp hết', lowStockItems.length, const Color(0xFFD97706)),
                          const SizedBox(width: 10),
                          _kpiCard('Hết hàng', outOfStockItems.length, const Color(0xFFDC2626)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (!_loading &&
                          (outOfStockItems.isNotEmpty || lowStockItems.isNotEmpty)) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: outOfStockItems.isNotEmpty
                                ? const Color(0xFFFEF2F2)
                                : const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: outOfStockItems.isNotEmpty
                                  ? const Color(0xFFFECACA)
                                  : const Color(0xFFFDE68A),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                LucideIcons.alertTriangle,
                                size: 20,
                                color: outOfStockItems.isNotEmpty
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFFD97706),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  outOfStockItems.isNotEmpty
                                      ? 'Cảnh báo: ${outOfStockItems.length} sản phẩm đã HẾT HÀNG!'
                                      : 'Cảnh báo: ${lowStockItems.length} sản phẩm sắp hết hàng!',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: outOfStockItems.isNotEmpty
                                        ? const Color(0xFF991B1B)
                                        : const Color(0xFF92400E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextField(
                        onChanged: (v) => setState(() => _search = v),
                        decoration: InputDecoration(
                          hintText: 'Tìm tên sản phẩm hoặc mã SKU...',
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
                            _stockChip('Tất cả', 'ALL'),
                            const SizedBox(width: 8),
                            _stockChip('Còn hàng', 'IN_STOCK'),
                            const SizedBox(width: 8),
                            _stockChip('Sắp hết', 'LOW'),
                            const SizedBox(width: 8),
                            _stockChip('Hết hàng', 'OUT'),
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
                        height: 82,
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
                        AButton(label: 'Thử lại', onPressed: _loadProducts),
                      ],
                    ),
                  );
                }

                if (filtered.isEmpty) {
                  return ACard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Column(
                        children: [
                          const Icon(LucideIcons.packageOpen, size: 40, color: Color(0xFF94A3B8)),
                          const SizedBox(height: 10),
                          Text(
                            _products.isEmpty
                                ? 'Chưa có sản phẩm nào'
                                : 'Không có sản phẩm khớp bộ lọc',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: () => _openProductForm(),
                            icon: const Icon(LucideIcons.plus, size: 16),
                            label: const Text('Thêm sản phẩm đầu tiên'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final p = filtered[index - 1];
                final name = (p['name'] ?? p['productName'] ?? 'Sản phẩm').toString();
                final sku = (p['sku'] ?? p['productCode'] ?? '').toString();
                final price = p['basePrice'] ?? p['price'] ?? 0;
                final stock = _availableStock(p);
                final minAlert = _minStockAlert(p);
                final isOut = stock <= 0;
                final isLow = !isOut && stock <= minAlert;
                final status = (p['status'] ?? 'ACTIVE').toString().toUpperCase();
                final img = (p['thumbnailUrl'] ?? p['imageUrl'] ?? '').toString();

                return InkWell(
                  onTap: () => _showProductActions(p),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: AppMotion.cardShadow,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: img.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: img,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 140,
                                  memCacheHeight: 140,
                                  placeholder: (_, _) => const Icon(
                                    LucideIcons.package,
                                    color: Color(0xFF047857),
                                  ),
                                  errorWidget: (_, _, _) => const Icon(
                                    LucideIcons.package,
                                    color: Color(0xFF047857),
                                  ),
                                )
                              : const Icon(LucideIcons.package, color: Color(0xFF047857)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              if (sku.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'SKU: $sku',
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(
                                    _formatVnd(price),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF047857),
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isOut || status != 'ACTIVE'
                                          ? const Color(0xFFFEF2F2)
                                          : isLow
                                          ? const Color(0xFFFFFBEB)
                                          : const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      isOut
                                          ? 'Hết hàng'
                                          : isLow
                                          ? 'Sắp hết: $stock'
                                          : 'Tồn kho: $stock',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: isOut || status != 'ACTIVE'
                                            ? const Color(0xFFDC2626)
                                            : isLow
                                            ? const Color(0xFFD97706)
                                            : const Color(0xFF047857),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(LucideIcons.moreVertical, size: 18, color: Color(0xFF94A3B8)),
                      ],
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
}
