import 'api_client.dart';
import 'api_config.dart';

/// Tổng hợp API vận hành dành cho Chủ cửa hàng (STORE_OWNER / STORE_MANAGER):
/// Sản phẩm CRUD, Tồn kho, Danh mục, Giảm giá, Gói dịch vụ, Nhân sự, Khách hàng CRM, Xác minh ngân hàng, Phân tích.
class MerchantApiService {
  static final MerchantApiService _instance = MerchantApiService._internal();
  factory MerchantApiService() => _instance;
  MerchantApiService._internal();

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

  // ==================== PRODUCTS & INVENTORY ====================

  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> body) async {
    final res = await _client.post(ApiConfig.products, body: body);
    return _extractMap(res);
  }

  Future<Map<String, dynamic>> updateProduct(
    String productId,
    Map<String, dynamic> body,
  ) async {
    final res = await _client.put(ApiConfig.productDetail(productId), body: body);
    return _extractMap(res);
  }

  Future<Map<String, dynamic>> updateProductStock(
    String productId, {
    required int availableStock,
    int? lowStockThreshold,
  }) async {
    final res = await _client.patch(
      ApiConfig.productInventory(productId),
      body: {
        'availableStock': availableStock,
        'lowStockThreshold': ?lowStockThreshold,
      },
    );
    return _extractMap(res);
  }

  Future<void> deactivateProduct(String productId) async {
    await _client.delete(ApiConfig.productDetail(productId));
  }

  // ==================== CATEGORIES ====================

  Future<List<Map<String, dynamic>>> listCategories(String storeId) async {
    final res = await _client.get(
      ApiConfig.storeCategories(storeId),
      queryParams: {'mode': 'flat'},
    );
    return _extractList(res);
  }

  Future<Map<String, dynamic>> createCategory(
    String storeId, {
    required String categoryName,
  }) async {
    final res = await _client.post(
      ApiConfig.storeCategories(storeId),
      body: {'categoryName': categoryName.trim(), 'status': 'ACTIVE'},
    );
    return _extractMap(res);
  }

  Future<void> deleteCategory(String categoryId) async {
    await _client.delete(ApiConfig.categoryDetail(categoryId));
  }

  // ==================== PRODUCT DISCOUNTS ====================

  Future<List<Map<String, dynamic>>> listDiscounts(String productId) async {
    final res = await _client.get(ApiConfig.productDiscounts(productId));
    return _extractList(res);
  }

  Future<Map<String, dynamic>> createDiscount(
    String productId, {
    num? discountPercent,
    num? discountAmount,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    final res = await _client.post(
      ApiConfig.productDiscounts(productId),
      body: {
        'discountPercent': ?discountPercent,
        'discountAmount': ?discountAmount,
        'startAt': startAt.toUtc().toIso8601String(),
        'endAt': endAt.toUtc().toIso8601String(),
        'status': 'ACTIVE',
      },
    );
    return _extractMap(res);
  }

  Future<void> deleteDiscount(String discountId) async {
    await _client.delete(ApiConfig.discountDetail(discountId));
  }

  // ==================== SUBSCRIPTIONS ====================

  Future<Map<String, dynamic>?> getCurrentSubscription() async {
    final res = await _client.get(ApiConfig.storeSubscriptionCurrent);
    if (res is Map && res['data'] == null) return null;
    return _extractMap(res);
  }

  Future<List<Map<String, dynamic>>> listSubscriptionPlans() async {
    final res = await _client.get(ApiConfig.storeSubscriptionPlans);
    return _extractList(res);
  }

  Future<Map<String, dynamic>> subscribeWithWallet(String planId) async {
    final key = 'sub_${DateTime.now().microsecondsSinceEpoch}';
    final res = await _client.post(
      ApiConfig.storeSubscriptionSubscribe,
      headers: {'X-Idempotency-Key': key},
      body: {'planId': int.tryParse(planId) ?? planId, 'idempotencyKey': key},
    );
    return _extractMap(res);
  }

  Future<Map<String, dynamic>> createSubscriptionRenewCharge(String planId) async {
    final res = await _client.post(
      ApiConfig.storeSubscriptionRenewCharge,
      body: {'planId': planId},
    );
    return _extractMap(res);
  }

  // ==================== STORE STAFF ====================

  Future<List<Map<String, dynamic>>> listAssignableStaffRoles() async {
    final res = await _client.get(ApiConfig.storeStaffRoles);
    return _extractList(res);
  }

  Future<List<Map<String, dynamic>>> listStaff(String storeId) async {
    final res = await _client.get(ApiConfig.storeStaff(storeId));
    return _extractList(res);
  }

  Future<Map<String, dynamic>> addStaff(
    String storeId, {
    required String userIdentifier,
    required String roleCode,
  }) async {
    final res = await _client.post(
      ApiConfig.storeStaff(storeId),
      body: {
        'userIdentifier': userIdentifier.trim(),
        'roleCode': roleCode.trim(),
      },
    );
    return _extractMap(res);
  }

  Future<void> removeStaff(String staffId) async {
    await _client.delete(ApiConfig.storeStaffDetail(staffId));
  }

  // ==================== STORE CUSTOMERS CRM ====================

  Future<List<Map<String, dynamic>>> listCustomers(String storeId) async {
    final res = await _client.get(ApiConfig.storeCustomers(storeId));
    return _extractList(res);
  }

  Future<Map<String, dynamic>> updateCustomerStatus(
    String storeId,
    String customerId,
    String status,
  ) async {
    final res = await _client.patch(
      ApiConfig.storeCustomerStatus(storeId, customerId),
      body: {'status': status},
    );
    return _extractMap(res);
  }

  // ==================== STORE BANK VERIFICATION ====================

  Future<List<Map<String, dynamic>>> listStoreBankAccounts(String storeId) async {
    final res = await _client.get(ApiConfig.storeBankAccounts(storeId));
    return _extractList(res);
  }

  Future<Map<String, dynamic>> createBankVerification({
    required String storeId,
    required String bankBin,
    required String bankName,
    required String accountNumber,
    required String accountHolder,
  }) async {
    final res = await _client.post(
      ApiConfig.storeBankAccountVerification,
      body: {
        'storeId': int.tryParse(storeId) ?? storeId,
        'bankBin': bankBin.trim(),
        'bankName': bankName.trim(),
        'accountNumber': accountNumber.trim(),
        'accountHolder': accountHolder.trim(),
      },
    );
    return _extractMap(res);
  }

  // ==================== STORE CASH / HANDOVER PREVIEW ====================

  Future<Map<String, dynamic>> getRentalHandoverPreview(
    String storeId,
    String rentalId,
  ) async {
    final res = await _client.get(
      ApiConfig.storeRentalHandoverPreview(storeId, rentalId),
    );
    return _extractMap(res);
  }

  // ==================== ANALYTICS ====================

  Future<Map<String, dynamic>> getDashboardAnalytics() async {
    final res = await _client.get(ApiConfig.analyticsDashboard);
    return _extractMap(res);
  }

  Future<Map<String, dynamic>> getAlerts() async {
    final res = await _client.get(ApiConfig.analyticsAlerts);
    return _extractMap(res);
  }
}
