import 'api_client.dart';
import 'api_config.dart';

/// Tổng hợp API Quản trị hệ thống (ADMIN / SYSTEM_ADMIN / SUPER_ADMIN).
class AdminApiService {
  static final AdminApiService _instance = AdminApiService._internal();
  factory AdminApiService() => _instance;
  AdminApiService._internal();

  final ApiClient _client = ApiClient();

  List<Map<String, dynamic>> _extractList(dynamic res) {
    final raw = res is Map
        ? (res['data'] is List
              ? res['data'] as List
              : (res['items'] is List ? res['items'] as List : const []))
        : (res is List ? res : const []);
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Map<String, dynamic> _extractMap(dynamic res) {
    if (res is Map) {
      if (res['data'] is Map) return Map<String, dynamic>.from(res['data'] as Map);
      return Map<String, dynamic>.from(res);
    }
    return {};
  }

  // ==================== STORES ====================

  Future<List<Map<String, dynamic>>> listStores({
    int page = 1,
    int pageSize = 50,
    String? status,
  }) async {
    final res = await _client.get(
      ApiConfig.adminStores,
      queryParams: {
        'page': '$page',
        'pageSize': '$pageSize',
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    return _extractList(res);
  }

  Future<Map<String, dynamic>> approveStore(String storeId) async {
    final res = await _client.post(ApiConfig.adminStoreApprove(storeId));
    return _extractMap(res);
  }

  Future<Map<String, dynamic>> rejectStore(String storeId, {String? reason}) async {
    final res = await _client.post(
      ApiConfig.adminStoreReject(storeId),
      body: {'reason': (reason != null && reason.trim().isNotEmpty) ? reason.trim() : 'Không đáp ứng yêu cầu'},
    );
    return _extractMap(res);
  }

  Future<Map<String, dynamic>> updateStore(
    String storeId, {
    String? status,
    String? name,
    String? phone,
    String? address,
  }) async {
    final res = await _client.patch(
      ApiConfig.adminStoreDetail(storeId),
      body: {
        'status': ?status,
        'name': ?name,
        'phone': ?phone,
        'address': ?address,
      },
    );
    return _extractMap(res);
  }

  // ==================== USERS & RBAC ====================

  Future<List<Map<String, dynamic>>> listUsers({
    int page = 1,
    int pageSize = 50,
    String? search,
  }) async {
    final res = await _client.get(
      ApiConfig.adminUsers,
      queryParams: {
        'page': '$page',
        'pageSize': '$pageSize',
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      },
    );
    return _extractList(res);
  }

  Future<Map<String, dynamic>> toggleUserStatus(String userId) async {
    final res = await _client.post(ApiConfig.adminUserToggleStatus(userId));
    return _extractMap(res);
  }

  Future<Map<String, dynamic>> updateUserRole(
    String userId, {
    required String role,
    String? reason,
  }) async {
    final res = await _client.post(
      ApiConfig.adminUserRole(userId),
      body: {
        'role': role,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return _extractMap(res);
  }

  // ==================== WITHDRAWALS & REFUND OBLIGATIONS ====================

  Future<List<Map<String, dynamic>>> listWithdrawals({
    int page = 1,
    int pageSize = 30,
  }) async {
    final res = await _client.get(
      ApiConfig.adminWithdrawals,
      queryParams: {'page': '$page', 'pageSize': '$pageSize'},
    );
    return _extractList(res);
  }

  Future<Map<String, dynamic>> payoutWithdrawal(String withdrawalId) async {
    final res = await _client.post(ApiConfig.adminWithdrawalPayout(withdrawalId));
    return _extractMap(res);
  }

  Future<Map<String, dynamic>> syncWithdrawalPayout(String withdrawalId) async {
    final res = await _client.post(ApiConfig.adminWithdrawalSyncPayout(withdrawalId));
    return _extractMap(res);
  }

  Future<Map<String, dynamic>> rejectWithdrawal(
    String withdrawalId, {
    required String reason,
  }) async {
    final res = await _client.post(
      ApiConfig.adminWithdrawalReject(withdrawalId),
      body: {'reason': reason.trim()},
    );
    return _extractMap(res);
  }

  Future<List<Map<String, dynamic>>> listRefundObligations() async {
    final res = await _client.get(ApiConfig.adminRefundObligations);
    return _extractList(res);
  }

  Future<Map<String, dynamic>> syncRefundObligation(String id) async {
    final res = await _client.post(ApiConfig.adminRefundObligationSync(id));
    return _extractMap(res);
  }

  // ==================== RENTALS & DEPOSIT REFUNDS ====================

  Future<List<Map<String, dynamic>>> listRentals({
    int page = 1,
    int pageSize = 30,
  }) async {
    final res = await _client.get(
      ApiConfig.adminRentals,
      queryParams: {'page': '$page', 'pageSize': '$pageSize'},
    );
    return _extractList(res);
  }

  Future<Map<String, dynamic>> assignFulfillment(
    String rentalId, {
    required String fulfillmentStoreId,
    required List<String> buttonIds,
    String? notes,
  }) async {
    final res = await _client.post(
      ApiConfig.adminRentalAssignFulfillment(rentalId),
      body: {
        'fulfillmentStoreId': fulfillmentStoreId,
        'buttonIds': buttonIds,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
    return _extractMap(res);
  }

  Future<Map<String, dynamic>> handoverRental(String rentalId) async {
    final res = await _client.post(ApiConfig.adminRentalHandover(rentalId));
    return _extractMap(res);
  }

  Future<Map<String, dynamic>> approveDepositRefund(String refundId) async {
    final res = await _client.post(ApiConfig.rentalRefundApprove(refundId));
    return _extractMap(res);
  }

  Future<Map<String, dynamic>> confirmDepositRefundPayout(
    String refundId, {
    String? providerReferenceId,
  }) async {
    final res = await _client.post(
      ApiConfig.adminRentalRefundConfirmPayout(refundId),
      body: {
        if (providerReferenceId != null && providerReferenceId.trim().isNotEmpty)
          'providerReferenceId': providerReferenceId.trim(),
      },
    );
    return _extractMap(res);
  }

  // ==================== RENTAL PACKAGES & PLANS ====================

  Future<List<Map<String, dynamic>>> listRentalPackages() async {
    final res = await _client.get(ApiConfig.adminRentalPackages);
    return _extractList(res);
  }

  Future<Map<String, dynamic>> createRentalPackage(Map<String, dynamic> body) async {
    final res = await _client.post(ApiConfig.adminRentalPackages, body: body);
    return _extractMap(res);
  }

  Future<Map<String, dynamic>> updateRentalPackage(
    String id,
    Map<String, dynamic> body,
  ) async {
    final res = await _client.put(ApiConfig.adminRentalPackageDetail(id), body: body);
    return _extractMap(res);
  }

  Future<List<Map<String, dynamic>>> listPlans() async {
    final res = await _client.get(ApiConfig.adminPlans);
    return _extractList(res);
  }

  Future<Map<String, dynamic>> createPlan(Map<String, dynamic> body) async {
    final res = await _client.post(ApiConfig.adminPlans, body: body);
    return _extractMap(res);
  }

  Future<Map<String, dynamic>> updatePlan(
    String id,
    Map<String, dynamic> body,
  ) async {
    final res = await _client.put(ApiConfig.adminPlanDetail(id), body: body);
    return _extractMap(res);
  }

  // ==================== IDENTITY VERIFICATION (eKYC) ====================

  Future<List<Map<String, dynamic>>> listIdentitySessions({
    int page = 1,
    int pageSize = 30,
  }) async {
    final res = await _client.get(
      ApiConfig.identityVerificationSessions,
      queryParams: {'page': '$page', 'pageSize': '$pageSize'},
    );
    return _extractList(res);
  }

  Future<void> deleteIdentitySession(String sessionId) async {
    await _client.delete(ApiConfig.identityVerificationSessionDetail(sessionId));
  }

  // ==================== STATS & AUDIT LOGS ====================

  Future<Map<String, dynamic>> getDashboard() async {
    final res = await _client.get(ApiConfig.adminDashboard);
    return _extractMap(res);
  }

  Future<Map<String, dynamic>> getStats() async {
    final res = await _client.get(ApiConfig.adminStats);
    return _extractMap(res);
  }

  Future<List<Map<String, dynamic>>> listAuditLogs() async {
    final res = await _client.get(ApiConfig.adminAuditLogs);
    return _extractList(res);
  }
}
