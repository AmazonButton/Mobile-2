import '../widgets/app_motion.dart';
import '../widgets/smart_order_tour.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/sample_a.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../models/order_model.dart';
import '../providers/order_provider.dart';
import '../providers/user_provider.dart';
import '../services/services.dart';
import 'orders/widgets/widgets.dart';

/// Màn hình Quản lý Đơn hàng - Orchestrator quản lý danh sách, phân tab và tác vụ hủy/đặt lại
class OrdersScreen extends StatefulWidget {
  final bool showBackButton;
  final SmartOrderTour? tour;
  final String? initialOrderId;

  const OrdersScreen({
    super.key,
    this.showBackButton = true,
    this.initialOrderId,
    this.tour,
  });

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _cancelCountdown = 60;
  Timer? _countdownTimer;

  final Set<String> _reordering = {};
  final Set<String> _updatingOrders = {};
  final OrderProvider _fallback = OrderProvider();

  (String, String)? _nextStoreAction(OrderModel order) {
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

  Future<void> _handleStoreAdvanceStatus(
    OrderModel order,
    String nextStatus,
    String actionLabel,
  ) async {
    if (!_updatingOrders.add(order.id)) return;
    if (mounted) setState(() {});
    try {
      final provider = _ordersProvider();
      await provider.updateOrderStatus(order.id, status: nextStatus);
      if (mounted) {
        _showFloatingToast('Đã cập nhật ${order.orderCode}: $actionLabel');
      }
    } catch (e) {
      if (mounted) {
        _showFloatingToast(
          'Lỗi cập nhật trạng thái: ${e is ApiException ? e.message : e.toString()}',
        );
      }
    } finally {
      _updatingOrders.remove(order.id);
      if (mounted) setState(() {});
    }
  }
  OrderProvider _ordersProvider({bool listen = false}) {
    try {
      return Provider.of<OrderProvider>(context, listen: listen);
    } catch (_) {
      return _fallback;
    }
  }

  void _redrawFallback() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fallback.addListener(_redrawFallback);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _startCountdown();
      final provider = _ordersProvider();
      provider.startLiveUpdates();
      await provider.loadOrders();
      if (mounted) _startCountdown();
      final id = widget.initialOrderId;
      if (!mounted || id == null || id.isEmpty) return;
      try {
        final json = await OrdersApiService().getOrderById(id);
        if (mounted) _showOrderDetail(OrderModel.fromJson(json));
      } catch (_) {
        if (mounted) {
          _showFloatingToast('Không thể mở đơn hàng. Vui lòng tải lại.');
        }
      }
    });
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    if (!mounted) return;
    if (!AppMotion.allowAmbient(context)) return;
    final initialProvider = _ordersProvider(listen: false);
    if (!initialProvider.activeOrders.any((o) => o.isEmergencyCancellable)) {
      return;
    }
    _cancelCountdown = 60;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final provider = _ordersProvider(listen: false);
      final hasCancellable = provider.activeOrders.any(
        (o) => o.isEmergencyCancellable,
      );
      if (_cancelCountdown <= 0 || !hasCancellable) {
        timer.cancel();
        return;
      }
      if (!TickerMode.valuesOf(context).enabled) return;
      setState(() {
        _cancelCountdown--;
      });
      if (_cancelCountdown <= 0) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _fallback.removeListener(_redrawFallback);
    _fallback.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() => _fallback.loadOrders();

  void _showFloatingToast(String message) => OrderToast.show(context, message);

  void _handleEmergencyCancel(OrderModel order) {
    OrderCancelDialog.show(
      context,
      order: order,
      orderTitle: order.displayTitle,
      buttonName: order.buttonName,
      price: order.price,
      orderCode: order.orderCode,
      storeName: order.storeName,
      onConfirm: () async {
        try {
          OrderProvider? provider;
          try {
            provider = Provider.of<OrderProvider>(context, listen: false);
          } catch (_) {}

          if (provider != null) {
            await provider.cancelOrder(
              order.id,
              reason: 'Hủy đơn khẩn cấp từ ứng dụng',
            );
          } else {
            await OrdersApiService().cancelOrder(
              order.id,
              reason: 'Hủy đơn khẩn cấp từ ứng dụng',
            );
            await _loadOrders();
          }
          _showFloatingToast(
            'Đã hủy đơn hàng ${order.displayTitle} từ ${order.buttonName} thành công',
          );
        } catch (e) {
          _showFloatingToast(
            'Lỗi khi hủy: ${e is ApiException ? e.message : e.toString()}',
          );
          rethrow;
        }
      },
    );
  }

  Future<void> _handleReorder(OrderModel order) async {
    if (order.deviceId.isEmpty) {
      _showFloatingToast('Không tìm thấy thiết bị gán cho đơn hàng này');
      return;
    }

    if (!_reordering.add(order.deviceId)) return;
    setState(() {});
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Đặt lại đơn hàng?', style: SampleA.section),
          content: Text(order.displayTitle, style: SampleA.body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Quay lại'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Xác nhận đặt lại'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      OrderProvider? provider;
      try {
        provider = Provider.of<OrderProvider>(context, listen: false);
      } catch (_) {}

      if (provider != null) {
        await provider.quickReorder(order.deviceId);
      } else {
        await OrdersApiService().quickReorder(deviceId: order.deviceId);
        await _loadOrders();
      }
      if (!mounted) return;
      _showFloatingToast('Đã đặt lại thành công: ${order.displayTitle}');
      _tabController.animateTo(0);
    } catch (e) {
      if (mounted) {
        _showFloatingToast(
          'Lỗi đặt hàng: ${e is ApiException ? e.message : e.toString()}',
        );
      }
    } finally {
      _reordering.remove(order.deviceId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _showDeliveryQueueSheet(OrderProvider provider) async {
    List<OrderModel> queue = [];
    bool loading = true;
    String? err;
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
            OrdersApiService().getDeliveryQueue().then((rows) {
              if (ctx.mounted) setSheet(() => queue = rows);
            }).catchError((e) {
              if (ctx.mounted) {
                setSheet(() => err = e is ApiException ? e.message : 'Không tải được hàng đợi giao.');
              }
            });
          }
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.65,
            maxChildSize: 0.9,
            builder: (_, scrollCtrl) => ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Hàng đợi giao hàng',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(LucideIcons.x, size: 18),
                    ),
                  ],
                ),
                const Divider(height: 16),
                if (err != null)
                  Text(err!, style: const TextStyle(color: Color(0xFFDC2626)))
                else if (queue.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Text(
                      'Hiện chưa có đơn nào đang chờ nhận giao.',
                      textAlign: TextAlign.center,
                      style: SampleA.caption,
                    ),
                  )
                else
                  for (final item in queue)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
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
                                  item.orderCode,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.apartment.isNotEmpty ? item.apartment : item.customerName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () async {
                              final oid = item.id;
                              try {
                                await OrdersApiService().claimOrder(oid);
                                _showFloatingToast('Đã nhận đơn giao thành công!');
                                provider.refreshOrders();
                                if (ctx.mounted) {
                                  setSheet(() => queue.removeWhere((x) => x.id == oid));
                                }
                              } catch (e) {
                                _showFloatingToast(
                                  e is ApiException ? e.message : 'Không thể nhận đơn giao.',
                                );
                              }
                            },
                            child: const Text('Nhận giao'),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showOrderDetail(OrderModel order) {
    final userProv = context.read<UserProvider?>();
    final isStoreOwner = userProv?.isStoreOwner ?? false;
    final isAdmin = userProv?.isAdmin ?? false;
    OrderDetailBottomSheet.show(
      context,
      order: order,
      isStoreOwner: isStoreOwner,
      isAdmin: isAdmin,
      onStoreAdvanceStatus: isStoreOwner ? _handleStoreAdvanceStatus : null,
      onReorder: (!isStoreOwner && !isAdmin) ? () => _handleReorder(order) : null,
      onCancel: (!isStoreOwner && !isAdmin) ? () => _handleEmergencyCancel(order) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = _ordersProvider(listen: true);
    final userProv = context.watch<UserProvider?>();
    final isStoreOwner = userProv?.isStoreOwner ?? false;
    final isAdmin = userProv?.isAdmin ?? false;
    final activeOrders = provider.activeOrders;
    final historyOrders = provider.historyOrders;
    final isLoading = provider.isLoading;
    final errorMessage = provider.errorMessage;

    return Scaffold(
      backgroundColor: SampleA.background,
      body: AContent(
        maxWidth: SampleA.listWidth,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  children: [
                    if (widget.showBackButton && Navigator.canPop(context)) ...[
                      AIconButton(
                        icon: LucideIcons.chevronLeft,
                        tooltip: 'Quay lại',
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAdmin
                                ? 'Đơn hàng hệ thống'
                                : isStoreOwner
                                    ? 'Đơn hàng đại lý'
                                    : 'Đơn hàng của tôi',
                            style: SampleA.title,
                          ),
                          if (isStoreOwner || isAdmin)
                            Text(
                              isAdmin
                                  ? 'Giám sát đơn toàn hệ thống'
                                  : 'Tiếp nhận, chuẩn bị và xác nhận giao hàng',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isStoreOwner)
                      AIconButton(
                        icon: LucideIcons.truck,
                        tooltip: 'Hàng đợi giao',
                        onPressed: () => _showDeliveryQueueSheet(provider),
                      ),
                    AIconButton(
                      icon: LucideIcons.filter,
                      tooltip: 'Lọc đơn hàng',
                      onPressed: () => _showFilters(provider),
                    ),
                    AIconButton(
                      icon: LucideIcons.refreshCw,
                      tooltip: 'Làm mới đơn hàng',
                      onPressed: isLoading
                          ? null
                          : () {
                              provider.refreshOrders();
                            },
                    ),
                  ],
                ),
              ),
              OrderTabSelector(
                key: widget.tour?.key(TourStep.orders),
                controller: _tabController,
                activeCount: activeOrders.length,
                historyCount: historyOrders.length,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  provider.totalItems == null
                      ? 'Đã tải ${provider.orders.length} đơn'
                      : 'Đã tải ${provider.orders.length}/${provider.totalItems} đơn',
                  style: SampleA.caption,
                ),
              ),
              if (isLoading) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              if (errorMessage != null &&
                  (activeOrders.isNotEmpty || historyOrders.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Chưa thể làm mới dữ liệu. Kéo xuống để thử lại.',
                    style: SampleA.caption.copyWith(color: SampleA.warning),
                  ),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    RefreshIndicator(
                      color: SampleA.primary,
                      onRefresh: () async {
                        await provider.refreshOrders();
                      },
                      child: _buildList(
                        activeOrders,
                        isLoading,
                        errorMessage,
                        () {
                          provider.loadOrders();
                        },
                      ),
                    ),
                    RefreshIndicator(
                      color: SampleA.primary,
                      onRefresh: () async {
                        await provider.refreshOrders();
                      },
                      child: _buildList(
                        historyOrders,
                        isLoading,
                        errorMessage,
                        () {
                          provider.loadOrders();
                        },
                        history: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loadMoreButton(OrderProvider provider) => Column(
    children: [
      if (provider.loadMoreError != null)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Chưa tải được trang tiếp theo. Vui lòng thử lại.'),
        ),
      AButton(
        label: provider.loadMoreError == null
            ? 'Tải thêm đơn hàng'
            : 'Thử tải thêm',
        busy: provider.loadingMore,
        onPressed: provider.loadingMore ? null : provider.loadMore,
      ),
    ],
  );

  Future<void> _showFilters(OrderProvider provider) async {
    var status = provider.statusFilter ?? '';
    var payment = provider.paymentFilter ?? '';
    DateTimeRange? range = provider.fromDate != null && provider.toDate != null
        ? DateTimeRange(
            start: DateUtils.dateOnly(provider.fromDate!),
            end: DateUtils.dateOnly(provider.toDate!),
          )
        : null;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Lọc đơn hàng', style: SampleA.section),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(
                    labelText: 'Trạng thái đơn',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Tất cả trạng thái'),
                    ),
                    for (final value in [
                      'PENDING',
                      'CONFIRMED',
                      'PROCESSING',
                      'PREPARING',
                      'READY_FOR_DELIVERY',
                      'SHIPPING',
                      'DELIVERY_FAILED',
                      'DELIVERED',
                      'COMPLETED',
                      'CANCELLED',
                      'REJECTED',
                    ])
                      DropdownMenuItem(
                        value: value,
                        child: Text(OrderModel.lifecycleLabel(value)),
                      ),
                  ],
                  onChanged: (value) => update(() => status = value ?? ''),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: payment,
                  decoration: const InputDecoration(labelText: 'Thanh toán'),
                  items: const [
                    DropdownMenuItem(
                      value: '',
                      child: Text('Tất cả thanh toán'),
                    ),
                    DropdownMenuItem(
                      value: 'PAID',
                      child: Text('Đã thanh toán'),
                    ),
                    DropdownMenuItem(
                      value: 'UNPAID',
                      child: Text('Chưa thanh toán'),
                    ),
                    DropdownMenuItem(
                      value: 'REFUNDED',
                      child: Text('Đã hoàn tiền'),
                    ),
                  ],
                  onChanged: (value) => update(() => payment = value ?? ''),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    range == null
                        ? 'Chọn khoảng ngày'
                        : '${range!.start.day}/${range!.start.month}/${range!.start.year} – ${range!.end.day}/${range!.end.month}/${range!.end.year}',
                  ),
                  onPressed: () async {
                    final selected = await showDateRangePicker(
                      context: sheetContext,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      initialDateRange: range,
                    );
                    if (sheetContext.mounted && selected != null) {
                      update(() => range = selected);
                    }
                  },
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    provider.setFilters(
                      status: status.isEmpty ? null : status,
                      paymentStatus: payment.isEmpty ? null : payment,
                      fromDate: range?.start,
                      toDate: range == null
                          ? null
                          : DateTime(
                              range!.end.year,
                              range!.end.month,
                              range!.end.day + 1,
                            ).subtract(const Duration(microseconds: 1)),
                    );
                  },
                  child: const Text('Áp dụng'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    provider.setFilters();
                  },
                  child: const Text('Xóa bộ lọc'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(
    List<OrderModel> orders,
    bool loading,
    String? error,
    VoidCallback retry, {
    bool history = false,
  }) {
    if (loading && orders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(48),
        children: const [
          Center(child: CircularProgressIndicator(color: SampleA.primary)),
        ],
      );
    }
    if (error != null && orders.isEmpty) {
      return OrderErrorView(message: error, onRetry: retry);
    }
    final paging = _ordersProvider();
    if (orders.isEmpty && paging.hasMore) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const Text('Chưa có đơn thuộc tab này trong số đơn đã tải.'),
          _loadMoreButton(paging),
        ],
      );
    }
    if (orders.isEmpty) {
      return OrderEmptyView(
        isHistory: history,
        onViewHistory: history ? null : () => _tabController.animateTo(1),
      );
    }
    final userProv = context.read<UserProvider?>();
    final isStoreOwner = userProv?.isStoreOwner ?? false;
    final isAdmin = userProv?.isAdmin ?? false;
    final headerCount = history ? 1 : 0;
    final footerCount = paging.hasMore ? 1 : 0;
    final totalCount = headerCount + orders.length + footerCount;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: totalCount,
      itemBuilder: (ctx, index) {
        if (history && index == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Gần đây', style: SampleA.section),
          );
        }
        final orderIndex = index - headerCount;
        if (orderIndex >= orders.length) {
          return _loadMoreButton(paging);
        }
        final order = orders[orderIndex];
        final nextAction = isStoreOwner ? _nextStoreAction(order) : null;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OrderCardItem(
            key: ValueKey(order.id),
            order: order,
            isStoreOwner: isStoreOwner,
            isAdmin: isAdmin,
            storeActionLabel: nextAction?.$2,
            isUpdatingStatus: _updatingOrders.contains(order.id),
            onAdvanceStatus: nextAction == null
                ? null
                : () => _handleStoreAdvanceStatus(
                      order,
                      nextAction.$1,
                      nextAction.$2,
                    ),
            cancelCountdown: _cancelCountdown,
            onEmergencyCancel: (!isStoreOwner && !isAdmin)
                ? () => _handleEmergencyCancel(order)
                : null,
            onCancel: (!isStoreOwner && !isAdmin)
                ? () => _handleEmergencyCancel(order)
                : null,
            onTrack: () => _showOrderDetail(order),
            onDetailTap: () => _showOrderDetail(order),
            isReordering: _reordering.contains(order.deviceId),
            onReorder:
                (!isStoreOwner && !isAdmin && order.deviceId.isNotEmpty)
                    ? () => _handleReorder(order)
                    : null,
          ),
        );
      },
    );
  }
}
