import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../models/order_model.dart';
import '../../../models/order_timeline_entry.dart';
import '../../../services/api_client.dart';
import '../../../services/media_api_service.dart';
import '../../../services/order_updates.dart';
import '../../../services/orders_api_service.dart';
import '../../../services/payments_api_service.dart';
import '../../../widgets/sample_a.dart';
import 'order_card_item.dart';
import 'order_server_timeline.dart';
import 'payos_qr_payment_sheet.dart';

class OrderDetailBottomSheet extends StatefulWidget {
  final OrderModel order;
  final VoidCallback? onReorder, onCancel;
  final bool isStoreOwner;
  final bool isAdmin;
  final Future<void> Function(OrderModel order, String nextStatus, String label)?
      onStoreAdvanceStatus;
  final OrdersApiService? service;
  const OrderDetailBottomSheet({
    super.key,
    required this.order,
    this.onReorder,
    this.onCancel,
    this.isStoreOwner = false,
    this.isAdmin = false,
    this.onStoreAdvanceStatus,
    this.service,
  });
  static Future<void> show(
    BuildContext context, {
    required OrderModel order,
    VoidCallback? onReorder,
    VoidCallback? onCancel,
    bool isStoreOwner = false,
    bool isAdmin = false,
    Future<void> Function(OrderModel order, String nextStatus, String label)?
        onStoreAdvanceStatus,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => OrderDetailBottomSheet(
        order: order,
        onReorder: onReorder,
        onCancel: onCancel,
        isStoreOwner: isStoreOwner,
        isAdmin: isAdmin,
        onStoreAdvanceStatus: onStoreAdvanceStatus,
      ),
    ),
  );
  @override
  State<OrderDetailBottomSheet> createState() => _OrderDetailBottomSheetState();
}

class _OrderDetailBottomSheetState extends State<OrderDetailBottomSheet>
    with WidgetsBindingObserver {
  late OrderModel _order = widget.order;
  late final _api = widget.service ?? OrdersApiService();
  List<OrderTimelineEntry> _timeline = [];
  bool _loading = true, _reloadAgain = false, _advancing = false;
  String? _detailError, _timelineError;
  StreamSubscription<String?>? _updates;
  Timer? _debounce;

  (String, String)? _nextAction(OrderModel order) {
    switch (order.rawStatus.toUpperCase()) {
      case 'PENDING':
        return ('CONFIRMED', 'Xác nhận đơn');
      case 'CONFIRMED':
        return ('PREPARING', 'Bắt đầu chuẩn bị');
      case 'PREPARING':
      case 'PROCESSING':
        return ('READY_FOR_DELIVERY', 'Sẵn sàng giao');
      case 'READY_FOR_DELIVERY':
        return ('SHIPPING', 'Xuất giao hàng');
      case 'SHIPPING':
        return ('DELIVERED', 'Xác nhận đã giao');
      default:
        return null;
    }
  }

  Future<void> _handleSwitchPaymentMethod() async {
    if (_advancing) return;
    final target = _order.isPayos ? 'COD' : 'PAYOS';
    final label = target == 'PAYOS' ? 'Chuyển khoản PayOS' : 'Tiền mặt (COD)';
    setState(() => _advancing = true);
    try {
      await PaymentsApiService().changeOrderPaymentMethod(
        orderId: _order.id,
        paymentMethod: target,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text('Đã đổi phương thức thanh toán sang $label.'),
        ),
      );
      await _reload();
      if (mounted && target == 'PAYOS') {
        await PayosQrPaymentSheet.show(context, order: _order);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFDC2626),
            content: Text(
              e is ApiException
                  ? e.message
                  : 'Không thể đổi phương thức thanh toán.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  Future<void> _handleViewPodPhoto() async {
    if (_advancing) return;
    setState(() => _advancing = true);
    try {
      final res = await _api.getPodViewUrl(_order.id);
      final url = (res['url'] ??
              res['signedUrl'] ??
              res['podUrl'] ??
              res['podImageUrl'] ??
              res['viewUrl'] ??
              '')
          .toString()
          .trim();
      if (!mounted) return;
      if (url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đơn hàng này chưa có ảnh xác thực giao hàng.')),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 14),
                    child: Text(
                      'Ảnh xác thực giao hàng (POD)',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(LucideIcons.x, color: Colors.white),
                  ),
                ],
              ),
              InteractiveViewer(
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  height: 360,
                  placeholder: (_, _) => const SizedBox(
                    height: 220,
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                  errorWidget: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Không tải được ảnh POD.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFDC2626),
            content: Text(
              e is ApiException
                  ? e.message
                  : 'Chưa có ảnh xác thực giao hàng cho đơn này.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  Future<void> _handleStoreAdvance() async {
    final next = _nextAction(_order);
    if (next == null || _advancing || widget.onStoreAdvanceStatus == null) return;
    if (next.$1 == 'DELIVERED') {
      await _handleStoreDeliverWithPod();
      return;
    }
    setState(() => _advancing = true);
    try {
      await widget.onStoreAdvanceStatus!(_order, next.$1, next.$2);
      await _reload();
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  Future<void> _handleStoreReject() async {
    if (_advancing) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Từ chối đơn hàng?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Bạn có chắc muốn từ chối đơn ${_order.orderCode}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Quay lại')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Từ chối đơn'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _advancing = true);
    try {
      await _api.updateOrderStatus(_order.id, status: 'REJECTED');
      OrderUpdates.notify(_order.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã từ chối đơn hàng.')),
        );
      }
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFDC2626),
            content: Text(e is ApiException ? e.message : 'Từ chối đơn thất bại.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  Future<void> _handleStoreDeliverWithPod() async {
    if (_advancing) return;
    final amountDigits = _order.price.replaceAll(RegExp(r'[^0-9]'), '');
    final collectedCtrl = TextEditingController(text: amountDigits);
    String payMethod = _order.isPayos ? 'PAYOS' : 'COD';
    String? podUrl;
    bool uploading = false;

    try {
      final confirm = await showModalBottomSheet<bool>(
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
                    'Xác nhận giao hàng (POD)',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: payMethod,
                    decoration: const InputDecoration(
                      labelText: 'Hình thức thu tiền',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'COD', child: Text('Tiền mặt (COD)')),
                      DropdownMenuItem(value: 'PAYOS', child: Text('PayOS')),
                      DropdownMenuItem(value: 'VIETQR', child: Text('VietQR')),
                    ],
                    onChanged: (v) => setSheet(() => payMethod = v ?? 'COD'),
                  ),
                  if (payMethod == 'COD') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: collectedCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Số tiền mặt đã thu (VNĐ)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: uploading
                        ? null
                        : () async {
                            final picked = await ImagePicker().pickImage(
                              source: ImageSource.camera,
                              maxWidth: 1280,
                              imageQuality: 80,
                            );
                            if (picked == null) return;
                            setSheet(() => uploading = true);
                            try {
                              final url = await MediaApiService().uploadImage(
                                File(picked.path),
                                folder: 'pod',
                              );
                              setSheet(() {
                                podUrl = url;
                                uploading = false;
                              });
                            } catch (e) {
                              setSheet(() => uploading = false);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: const Color(0xFFDC2626),
                                    content: Text(
                                      e is ApiException ? e.message : 'Tải ảnh POD thất bại.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                    icon: const Icon(LucideIcons.camera, size: 17),
                    label: Text(
                      uploading
                          ? 'Đang tải ảnh POD...'
                          : (podUrl == null ? 'Chụp ảnh xác thực giao hàng (POD)' : 'Đã có ảnh POD (chụp lại)'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: uploading ? null : () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF047857),
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: const Text('Hoàn tất giao hàng'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (confirm != true || !mounted) return;
      setState(() => _advancing = true);
      await _api.deliverOrder(
        _order.id,
        paymentMethod: payMethod,
        collectedAmount: payMethod == 'COD' ? num.tryParse(collectedCtrl.text.trim()) : null,
        podImageUrl: podUrl,
      );
      OrderUpdates.notify(_order.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF059669),
            content: Text('Đã hoàn tất giao hàng thành công!'),
          ),
        );
      }
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFDC2626),
            content: Text(e is ApiException ? e.message : 'Xác nhận giao hàng thất bại.'),
          ),
        );
      }
    } finally {
      collectedCtrl.dispose();
      if (mounted) setState(() => _advancing = false);
    }
  }

  Future<void> _handleStoreFailDelivery() async {
    if (_advancing) return;
    String reasonCode = 'CUSTOMER_UNREACHABLE';
    final noteCtrl = TextEditingController();
    String? evidenceUrl;
    bool uploading = false;

    try {
      final confirm = await showModalBottomSheet<bool>(
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
                    'Báo cáo giao hàng thất bại',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: reasonCode,
                    decoration: const InputDecoration(
                      labelText: 'Lý do thất bại *',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'CUSTOMER_UNREACHABLE', child: Text('Không liên lạc được khách')),
                      DropdownMenuItem(value: 'WRONG_ADDRESS', child: Text('Sai địa chỉ giao hàng')),
                      DropdownMenuItem(value: 'CUSTOMER_REJECTED', child: Text('Khách từ chối nhận')),
                      DropdownMenuItem(value: 'GOODS_DAMAGED_IN_TRANSIT', child: Text('Hàng hư hại khi giao')),
                    ],
                    onChanged: (v) => setSheet(() => reasonCode = v ?? 'CUSTOMER_UNREACHABLE'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ghi chú chi tiết',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: uploading
                        ? null
                        : () async {
                            final picked = await ImagePicker().pickImage(
                              source: ImageSource.camera,
                              maxWidth: 1280,
                              imageQuality: 80,
                            );
                            if (picked == null) return;
                            setSheet(() => uploading = true);
                            try {
                              final url = await MediaApiService().uploadImage(
                                File(picked.path),
                                folder: 'delivery-failures',
                              );
                              setSheet(() {
                                evidenceUrl = url;
                                uploading = false;
                              });
                            } catch (e) {
                              setSheet(() => uploading = false);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: const Color(0xFFDC2626),
                                    content: Text(
                                      e is ApiException ? e.message : 'Tải ảnh bằng chứng thất bại.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                    icon: const Icon(LucideIcons.camera, size: 17),
                    label: Text(
                      uploading
                          ? 'Đang tải ảnh...'
                          : (evidenceUrl == null ? 'Chụp ảnh bằng chứng *' : 'Đã có ảnh bằng chứng'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: (uploading || evidenceUrl == null)
                        ? null
                        : () => Navigator.pop(ctx, true),
                    child: const Text('Gửi báo cáo giao thất bại'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (confirm != true || evidenceUrl == null || !mounted) return;
      setState(() => _advancing = true);
      await _api.failDelivery(
        _order.id,
        failureReasonCode: reasonCode,
        failureNote: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        evidenceImageUrl: evidenceUrl!,
      );
      OrderUpdates.notify(_order.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã ghi nhận giao hàng thất bại.')),
        );
      }
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFDC2626),
            content: Text(e is ApiException ? e.message : 'Báo giao thất bại không thành công.'),
          ),
        );
      }
    } finally {
      noteCtrl.dispose();
      if (mounted) setState(() => _advancing = false);
    }
  }
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updates = OrderUpdates.events.listen((id) {
      if (id == null || id == _order.id || id == _order.orderCode) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 250), _reload);
      }
    });
    _loading = false;
    _reload();
  }

  @override
  void dispose() {
    _updates?.cancel();
    _debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    if (_loading) {
      _reloadAgain = true;
      return;
    }
    setState(() {
      _loading = true;
      _detailError = null;
      _timelineError = null;
    });
    await Future.wait([
      () async {
        try {
          final data = await _api.getOrderById(widget.order.id);
          final order = OrderModel.fromJson(data);
          if (order.id != widget.order.id) {
            throw const FormatException('Sai mã đơn hàng');
          }
          if (mounted) setState(() => _order = order);
        } catch (_) {
          if (mounted) {
            setState(
              () => _detailError = 'Chưa thể cập nhật chi tiết đơn hàng.',
            );
          }
        }
      }(),
      () async {
        try {
          final entries = await _api.getTimeline(widget.order.id);
          if (mounted) setState(() => _timeline = entries);
        } catch (_) {
          if (mounted) {
            setState(() => _timelineError = 'Chưa tải được lịch sử đơn hàng.');
          }
        }
      }(),
    ]);
    if (!mounted) return;
    setState(() => _loading = false);
    if (_reloadAgain) {
      _reloadAgain = false;
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final next = widget.isStoreOwner ? _nextAction(_order) : null;
    final rawSt = _order.rawStatus.toUpperCase();
    return _OrderDetailContent(
      order: _order,
      onReorder: widget.onReorder,
      onCancel: widget.onCancel,
      isStoreOwner: widget.isStoreOwner,
      isAdmin: widget.isAdmin,
      storeActionLabel: next?.$2,
      advancing: _advancing,
      onAdvanceStatus: next != null && widget.onStoreAdvanceStatus != null
          ? _handleStoreAdvance
          : null,
      onStoreReject: widget.isStoreOwner &&
              (rawSt == 'PENDING' || rawSt == 'CONFIRMED')
          ? _handleStoreReject
          : null,
      onStoreFailDelivery: widget.isStoreOwner && rawSt == 'SHIPPING'
          ? _handleStoreFailDelivery
          : null,
      onSwitchPaymentMethod:
          !widget.isStoreOwner &&
              !widget.isAdmin &&
              !_order.isPaid &&
              !_order.isCancelled &&
              !_order.isCompleted
          ? _handleSwitchPaymentMethod
          : null,
      onViewPodPhoto: (rawSt == 'DELIVERED' || rawSt == 'COMPLETED')
          ? _handleViewPodPhoto
          : null,
      entries: _timeline,
      loading: _loading,
      detailError: _detailError,
      timelineError: _timelineError,
      reload: _reload,
    );
  }
}

class _OrderDetailContent extends StatelessWidget {
  final OrderModel order;
  final VoidCallback? onReorder,
      onCancel,
      onAdvanceStatus,
      onStoreReject,
      onStoreFailDelivery,
      onSwitchPaymentMethod,
      onViewPodPhoto;
  final bool isStoreOwner, isAdmin, advancing;
  final String? storeActionLabel;
  final List<OrderTimelineEntry> entries;
  final bool loading;
  final String? detailError, timelineError;
  final VoidCallback reload;
  const _OrderDetailContent({
    required this.order,
    this.onReorder,
    this.onCancel,
    this.isStoreOwner = false,
    this.isAdmin = false,
    this.storeActionLabel,
    this.advancing = false,
    this.onAdvanceStatus,
    this.onStoreReject,
    this.onStoreFailDelivery,
    this.onSwitchPaymentMethod,
    this.onViewPodPhoto,
    required this.entries,
    required this.loading,
    this.detailError,
    this.timelineError,
    required this.reload,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      title: const Text('Chi tiết đơn hàng'),
      backgroundColor: Colors.white,
    ),
    body: AContent(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              ACard(
                color: SampleA.pale,
                border: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OrderStatusBadge(order: order),
                    const SizedBox(height: 12),
                    Text(
                      order.orderCode,
                      style: SampleA.title.copyWith(fontSize: 24),
                    ),
                    if (order.storeName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(order.storeName, style: SampleA.body),
                      ),
                    if (order.time.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(order.time, style: SampleA.caption),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (loading) const LinearProgressIndicator(),
              if (detailError != null)
                Text(detailError!, style: SampleA.caption),
              if (timelineError != null)
                Text(timelineError!, style: SampleA.caption),
              TextButton.icon(
                onPressed: loading ? null : reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Làm mới chi tiết'),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ACard(
                  color: SampleA.pale,
                  border: false,
                  child: Text(
                    OrderModel.lifecycleLabel(order.rawStatus),
                    style: SampleA.body,
                  ),
                ),
              ),
              OrderTimeline(rawStatus: order.rawStatus),
              const SizedBox(height: 16),
              if (entries.isNotEmpty || (!loading && timelineError == null))
                OrderServerTimeline(entries: entries),
              if (order.apartment.isNotEmpty) ...[
                const SizedBox(height: 16),
                ACard(
                  color: const Color(0xFFF8FAFC),
                  border: false,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(LucideIcons.mapPin, color: SampleA.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Địa chỉ nhận hàng',
                              style: SampleA.section,
                            ),
                            const SizedBox(height: 6),
                            if (order.customerName.isNotEmpty)
                              Text(
                                order.customerName,
                                style: SampleA.body.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            Text(order.apartment, style: SampleA.body),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Text('Sản phẩm', style: SampleA.section),
              const SizedBox(height: 12),
              OrderProductLine(order: order),
              if (order.items.length > 1) ...[
                const SizedBox(height: 12),
                for (final item in order.items.skip(1))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${item.quantity} × ${item.name}',
                      style: SampleA.body,
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              const Divider(color: SampleA.border),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  const Text('Tổng thanh toán', style: SampleA.body),
                  Text(
                    order.price,
                    style: SampleA.title.copyWith(fontSize: 24),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                order.isPaid
                    ? 'Đã thanh toán · ${order.paymentMethod}'
                    : order.isPayos
                    ? 'Chưa thanh toán · PayOS'
                    : 'Thanh toán khi nhận hàng',
                style: SampleA.caption,
              ),
              const SizedBox(height: 24),
              if (isStoreOwner && storeActionLabel != null && onAdvanceStatus != null) ...[
                AButton(
                  label: storeActionLabel!,
                  busy: advancing,
                  onPressed: advancing ? null : onAdvanceStatus,
                ),
                const SizedBox(height: 12),
              ],
              if (onStoreFailDelivery != null) ...[
                AButton(
                  label: 'Báo giao hàng thất bại',
                  kind: AButtonKind.danger,
                  busy: advancing,
                  onPressed: advancing ? null : onStoreFailDelivery,
                ),
                const SizedBox(height: 12),
              ],
              if (onStoreReject != null) ...[
                AButton(
                  label: 'Từ chối đơn hàng',
                  kind: AButtonKind.danger,
                  busy: advancing,
                  onPressed: advancing ? null : onStoreReject,
                ),
                const SizedBox(height: 12),
              ],
              if (!isStoreOwner && !isAdmin && order.canPay) ...[
                AButton(
                  label: order.isPayos
                      ? 'Thanh toán'
                      : 'Thanh toán trước bằng PayOS',
                  onPressed: () =>
                      PayosQrPaymentSheet.show(context, order: order),
                ),
                const SizedBox(height: 12),
              ],
              if (onSwitchPaymentMethod != null) ...[
                AButton(
                  label: order.isPayos
                      ? 'Đổi sang thanh toán tiền mặt (COD)'
                      : 'Đổi sang thanh toán PayOS',
                  kind: AButtonKind.secondary,
                  busy: advancing,
                  onPressed: advancing ? null : onSwitchPaymentMethod,
                ),
                const SizedBox(height: 12),
              ],
              if (onViewPodPhoto != null) ...[
                AButton(
                  label: 'Xem ảnh xác thực giao hàng (POD)',
                  kind: AButtonKind.secondary,
                  busy: advancing,
                  onPressed: advancing ? null : onViewPodPhoto,
                ),
                const SizedBox(height: 12),
              ],
              if (!isStoreOwner && !isAdmin && order.isEmergencyCancellable && onCancel != null) ...[
                AButton(
                  label: 'Hủy đơn hàng này',
                  kind: AButtonKind.danger,
                  onPressed: () {
                    Navigator.pop(context);
                    onCancel!();
                  },
                ),
                const SizedBox(height: 12),
              ],
              if (!isStoreOwner && !isAdmin && order.isCompleted && onReorder != null) ...[
                AButton(
                  label: 'Đặt lại đơn này',
                  onPressed: () {
                    Navigator.pop(context);
                    onReorder!();
                  },
                ),
                const SizedBox(height: 12),
              ],
              AButton(
                label: 'Quay lại đơn hàng',
                kind: AButtonKind.secondary,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
