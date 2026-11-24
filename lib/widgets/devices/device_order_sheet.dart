import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/device_model.dart';
import '../../models/order_model.dart';
import '../../providers/address_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/api_client.dart';
import '../../screens/orders/widgets/order_detail_bottom_sheet.dart';
import '../../screens/orders/widgets/order_status_views.dart';
import '../sample_a.dart';

Future<void> showDeviceOrderSheet(
  BuildContext context,
  DeviceModel device,
) async {
  final provider = context.read<OrderProvider?>();
  final addressProv = context.read<AddressProvider?>();
  final selectedAddress = addressProv?.selectedAddress;
  final address =
      selectedAddress?.fullAddress.trim().isNotEmpty == true
          ? selectedAddress!.fullAddress
          : context.read<UserProvider?>()?.address;
  final order = await showModalBottomSheet<OrderModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _DeviceOrderConfirmation(
      device: device,
      provider: provider,
      address: address,
      addressId: selectedAddress?.id,
    ),
  );
  if (!context.mounted || order == null) return;
  OrderDetailBottomSheet.show(
    context,
    order: order,
    onCancel: () {
      if (!context.mounted) return;
      OrderCancelDialog.show(
        context,
        order: order,
        orderTitle: order.displayTitle,
        onConfirm: () async {
          await provider!.cancelOrder(
            order.id,
            reason: 'Hủy trong cửa sổ an toàn',
          );
        },
      );
    },
  );
}

class _DeviceOrderConfirmation extends StatefulWidget {
  final DeviceModel device;
  final OrderProvider? provider;
  final String? address;
  final String? addressId;
  const _DeviceOrderConfirmation({
    required this.device,
    this.provider,
    this.address,
    this.addressId,
  });
  @override
  State<_DeviceOrderConfirmation> createState() =>
      _DeviceOrderConfirmationState();
}

class _DeviceOrderConfirmationState extends State<_DeviceOrderConfirmation> {
  bool _busy = false;
  String? _error;
  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final provider = widget.provider;
      if (provider == null) {
        throw StateError('Không thể tải thông tin đơn hàng.');
      }
      final order = await provider.createOneTouchOrder(
        deviceId: widget.device.id,
        buttonName: widget.device.name,
        productName: widget.device.product,
        productPrice: widget.device.price,
        apartment: widget.address,
        addressId: widget.addressId,
      );
      if (order == null) throw StateError('Chưa nhận được xác nhận đơn hàng.');
      if (mounted) Navigator.pop(context, order);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is ApiException ? e.message : e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Kiểm tra trước khi đặt', style: SampleA.section),
            const SizedBox(height: 24),
            Row(
              children: [
                AProductImage(
                  product: widget.device.product,
                  imageUrl: widget.device.imageUrl,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.device.product,
                        style: SampleA.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Số lượng: ${widget.device.quantity}',
                        style: SampleA.caption,
                      ),
                      Text(
                        'Đơn giá: ${widget.device.price}',
                        style: SampleA.section,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ACard(
              color: SampleA.pale,
              border: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Giao đến', style: SampleA.body),
                  const SizedBox(height: 6),
                  Text(
                    widget.address?.trim().isNotEmpty == true
                        ? widget.address!
                        : 'Địa chỉ đã lưu trong tài khoản',
                    style: SampleA.caption,
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _error!,
                  style: SampleA.body.copyWith(color: SampleA.danger),
                ),
              ),
            const SizedBox(height: 24),
            AButton(
              label: 'Xác nhận đặt hàng',
              onPressed: _confirm,
              busy: _busy,
            ),
            const SizedBox(height: 12),
            AButton(
              label: 'Quay lại',
              onPressed: _busy ? null : () => Navigator.pop(context),
              kind: AButtonKind.secondary,
            ),
          ],
        ),
      ),
    ),
  );
}
