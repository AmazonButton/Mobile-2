import '../models/customer_button_contract.dart';
import 'api_client.dart';
import 'api_config.dart';

/// Customer custody operations only. Store rental fees are not collected here.
class CustomerButtonsApiService {
  final ApiClient _client = ApiClient();
  static Future<List<CustomerButtonContract>>? _inFlightMyButtons;
  static String? _inFlightToken;

  Future<List<CustomerButtonContract>> getMyButtons() {
    final token = _client.accessToken;
    if (_inFlightMyButtons != null && _inFlightToken == token) {
      return _inFlightMyButtons!;
    }
    _inFlightToken = token;
    final request = _fetchMyButtons().whenComplete(() {
      _inFlightMyButtons = null;
      _inFlightToken = null;
    });
    _inFlightMyButtons = request;
    return request;
  }

  Future<List<CustomerButtonContract>> _fetchMyButtons() async {
    final response = await _client.get(ApiConfig.myRentals);
    dynamic rows = response['data'];
    if (rows is Map && rows['items'] is List) {
      rows = rows['items'];
    } else if (rows == null && response['items'] is List) {
      rows = response['items'];
    } else if (rows == null && response['success'] == true) {
      return const [];
    }
    if (rows is! List) throw const FormatException('Không thể đọc hồ sơ nút');
    return rows
        .whereType<Map>()
        .map(
          (row) => CustomerButtonContract.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList();
  }

  Future<Map<String, dynamic>> createDepositPaymentRequest(
    String contractId, {
    String? idempotencyKey,
  }) async {
    final key =
        idempotencyKey ??
        'pay_rnt_${contractId}_${DateTime.now().microsecondsSinceEpoch}';
    final response = await _client.post(
      '/rentals/${Uri.encodeComponent(contractId)}/payment-requests',
      headers: {'X-Idempotency-Key': key},
    );
    final data = response['data'] ?? response;
    if (data is! Map) {
      throw const FormatException('Không thể tạo liên kết thanh toán tiền cọc');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> requestReturn({
    required String contractId,
    required String buttonId,
  }) async {
    final response = await _client.post(
      '/rentals/${Uri.encodeComponent(contractId)}/return-requests',
      body: {'buttonId': buttonId},
    );
    final data = response['data'];
    if (data is! Map ||
        data['returnId'] == null ||
        data['status'] != 'PENDING_RECEIPT') {
      throw const FormatException('Chưa nhận được xác nhận yêu cầu trả nút');
    }
    return Map<String, dynamic>.from(data);
  }

  /// Lấy chi tiết hợp đồng thuê (GET /rentals/:id)
  Future<Map<String, dynamic>> getRentalDetail(String contractId) async {
    final response = await _client.get(
      ApiConfig.rentalDetail(Uri.encodeComponent(contractId)),
    );
    final data = response['data'] ?? response;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// Gia hạn hợp đồng thuê nút IoT (POST /rentals/:id/extensions + X-Idempotency-Key)
  Future<Map<String, dynamic>> extendRental({
    required String contractId,
    required int additionalMonths,
    String? idempotencyKey,
  }) async {
    final safeMonths = additionalMonths.clamp(1, 24);
    final key =
        idempotencyKey ??
        'ext_rnt_${contractId}_${DateTime.now().microsecondsSinceEpoch}';
    final response = await _client.post(
      ApiConfig.rentalExtensions(Uri.encodeComponent(contractId)),
      headers: {'X-Idempotency-Key': key},
      body: {'additionalMonths': safeMonths},
    );
    final data = response['data'] ?? response;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}
