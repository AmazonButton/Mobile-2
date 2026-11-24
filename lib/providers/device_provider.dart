import 'dart:async';
import '../services/stock_service.dart';
import 'package:flutter/material.dart';
import '../models/button_product_model.dart';
import '../models/device_model.dart';
import '../services/devices_api_service.dart';

class DeviceProvider extends ChangeNotifier {
  final DevicesApiService _apiService;

  List<DeviceModel> _devices;
  bool _isLoading = false;
  String? _errorMessage;
  Future<void>? _inFlightLoad;

  DeviceProvider({
    DevicesApiService? apiService,
    List<DeviceModel>? initialDevices,
  }) : _apiService = apiService ?? DevicesApiService(),
       _devices = initialDevices ?? [];

  List<DeviceModel> get devices => List.unmodifiable(_devices);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  DeviceModel? getDeviceById(String id) {
    try {
      return _devices.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Tải toàn bộ danh sách thiết bị từ backend (coalesce lời gọi trùng, không ẩn nút chưa gán, không chặn UI chờ N+1 StockService)
  Future<void> loadDevices({bool includeCustomerUsage = true}) {
    if (_inFlightLoad != null) return _inFlightLoad!;
    final future = _doLoadDevices(
      includeCustomerUsage: includeCustomerUsage,
    ).whenComplete(() => _inFlightLoad = null);
    _inFlightLoad = future;
    return future;
  }

  Future<void> _doLoadDevices({required bool includeCustomerUsage}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final fetched = await _apiService.getDevices(
        includeCustomerUsage: includeCustomerUsage,
      );
      _devices = fetched;
      _errorMessage = null;
      // Refresh stock lazily in background for customer buttons with products so UI renders immediately
      if (includeCustomerUsage) {
        final withProducts = _devices
            .where((d) => d.productId != null && d.productId!.isNotEmpty)
            .take(8)
            .toList();
        if (withProducts.isNotEmpty) {
          unawaited(
            Future.wait(
              withProducts.map((d) => StockService.instance.refreshDevice(d.id)),
            ).catchError((_) => const <void>[]),
          );
        }
      }
    } catch (e) {
      _errorMessage = e.toString();
      // Nếu có lỗi kết nối, giữ lại danh sách thiết bị hiện tại nếu có
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Hủy ghép nối (Customer -> POST /devices/:id/unclaim) hoặc xóa thiết bị (Ops/Store -> DELETE /devices/:id)
  Future<void> removeDevice(
    String deviceId, {
    bool isCustomer = true,
  }) async {
    if (isCustomer) {
      await _apiService.unclaimDevice(deviceId);
    } else {
      await _apiService.deleteDevice(deviceId);
    }
    _devices.removeWhere((d) => d.id == deviceId);
    notifyListeners();
  }

  /// Đổi cửa hàng và nhận lại cấu hình nút đã xóa sản phẩm cũ từ backend.
  Future<void> updateDeviceStore(String deviceId, String storeId) async {
    if (!_devices.any((device) => device.id == deviceId)) {
      throw StateError('Không tìm thấy thiết bị');
    }
    final response = await _apiService.updateCustomerConfig(
      deviceId,
      storeId: storeId,
    );
    final updated = DeviceModel.fromJson(response);
    final index = _devices.indexWhere((device) => device.id == deviceId);
    if (index == -1) return;
    _devices[index] = updated;
    notifyListeners();
  }

  /// Chỉ cập nhật sản phẩm trên giao diện sau khi backend xác nhận.
  Future<void> updateDeviceProduct(
    String deviceId,
    ButtonProductModel product, {
    int quantity = 1,
  }) async {
    final index = _devices.indexWhere((d) => d.id == deviceId);
    if (index == -1) throw StateError('Không tìm thấy thiết bị');

    final response = await _apiService.updateCustomerConfig(
      deviceId,
      productId: product.id,
      quantity: quantity,
    );
    final currentIndex = _devices.indexWhere((d) => d.id == deviceId);
    if (currentIndex == -1) return;
    _devices[currentIndex] = DeviceModel.fromJson(response);
    notifyListeners();
    unawaited(StockService.instance.refreshDevice(deviceId));
  }

  /// Cập nhật sản phẩm tùy chỉnh (gửi kèm productId nếu có để lưu thật trên backend)
  Future<void> updateDeviceProductByName(
    String deviceId,
    String productName,
    String price, {
    String? productId,
    int? quantity,
    String? badgeText,
  }) async {
    final index = _devices.indexWhere((d) => d.id == deviceId);
    if (index == -1) return;

    final current = _devices[index];
    final badge =
        badgeText ??
        (productName.contains('Gas')
            ? '12kg'
            : (productName.contains('500ml') ||
                  productName.contains('chai') ||
                  productName.contains('lon'))
            ? '24 món'
            : '20L');

    final updated = current.copyWith(
      productId: productId ?? current.productId,
      product: productName,
      price: price.endsWith('đ') ? price : '$priceđ',
      badgeText: badge,
    );

    _devices[index] = updated;
    notifyListeners();

    if (productId != null && productId.trim().isNotEmpty) {
      final response = await _apiService.updateCustomerConfig(
        deviceId,
        productId: productId.trim(),
        quantity: quantity ?? current.quantity,
      );
      final currentIndex = _devices.indexWhere((d) => d.id == deviceId);
      if (currentIndex != -1) {
        _devices[currentIndex] = DeviceModel.fromJson(response);
        notifyListeners();
      }
    }
  }

  /// Đổi tên sau khi máy chủ xác nhận, giữ nguyên cấu hình đặt hàng.
  Future<void> renameDevice(String deviceId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 100) {
      throw ArgumentError('Tên nút phải có từ 1 đến 100 ký tự');
    }
    if (getDeviceById(deviceId) == null) {
      throw StateError('Không tìm thấy thiết bị');
    }
    final response = await _apiService.updateCustomerConfig(
      deviceId,
      buttonName: trimmed,
    );
    final savedName =
        response['buttonName'] ?? response['name'] ?? response['customName'];
    if (savedName is! String || savedName.trim().isEmpty) {
      throw const FormatException('Phản hồi không có tên nút đã lưu');
    }
    final index = _devices.indexWhere((device) => device.id == deviceId);
    if (index == -1) return;
    _devices[index] = _devices[index].copyWith(name: savedName);
    notifyListeners();
  }

  /// Cập nhật tên nút lên backend (chỉ gửi buttonName vì BE CustomerUpdateConfigDto không có roomLocation)
  Future<void> updateDeviceInfo(
    String deviceId, {
    String? name,
    String? room,
  }) async {
    final index = _devices.indexWhere((d) => d.id == deviceId);
    if (index == -1) return;

    final current = _devices[index];
    final trimmedName = name?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      await _apiService.updateCustomerConfig(
        deviceId,
        buttonName: trimmedName,
      );
    }

    final currentIndex = _devices.indexWhere((d) => d.id == deviceId);
    if (currentIndex == -1) return;
    _devices[currentIndex] = current.copyWith(
      name: (trimmedName != null && trimmedName.isNotEmpty)
          ? trimmedName
          : current.name,
      room: room ?? current.room,
    );
    notifyListeners();
  }

  /// Tạo mã chuyển nhượng thiết bị (POST /devices/:id/transfer)
  Future<Map<String, dynamic>> transferDevice(String deviceId) async {
    final res = await _apiService.transferDevice(deviceId);
    return res;
  }

  /// Xóa dữ liệu thiết bị khi đăng xuất hoặc đổi tài khoản
  void reset() {
    _inFlightLoad = null;
    _devices = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Làm mới danh sách thiết bị
  Future<void> refreshDevices({bool includeCustomerUsage = true}) =>
      loadDevices(includeCustomerUsage: includeCustomerUsage);
}
