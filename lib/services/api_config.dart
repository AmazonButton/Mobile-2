class ApiConfig {
  ApiConfig._();

  /// Override with --dart-define=API_BASE_URL=... for a local backend.
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://backend-fae8.onrender.com/api/v1',
  );

  /// Active Base URL in runtime (can be customized for physical devices on local Wi-Fi)
  static String baseUrl = defaultBaseUrl;

  /// Update base URL at runtime (e.g. testing with physical device IP: http://192.168.1.50:3000/api/v1)
  static void setBaseUrl(String newUrl) {
    if (newUrl.endsWith('/')) {
      baseUrl = newUrl.substring(0, newUrl.length - 1);
    } else {
      baseUrl = newUrl;
    }
  }

  // Auth endpoints
  static const String authLogin = '/auth/login';
  static const String authRegister = '/auth/register';
  static const String authGoogleLogin = '/auth/google-login';
  static const String authRefresh = '/auth/refresh';
  static const String authLogout = '/auth/logout';
  static const String authMe = '/auth/me';
  static const String authCheckEmail = '/auth/check-email';
  static const String authCheckUsername = '/auth/check-username';
  static const String authForgotPassword = '/auth/forgot-password';
  static const String authResetPassword = '/auth/reset-password';
  static const String authVerifyEmail = '/auth/verify-email';
  static const String authResendVerification = '/auth/resend-verification';
  static const String authRegisterByPhone = '/auth/register-by-phone';
  static const String authLoginByPhone = '/auth/login-by-phone';

  // Devices endpoints
  static const String devices = '/devices';
  static const String devicesUnassigned = '/devices/unassigned';
  static const String devicesBulkImport = '/devices/bulk-import';
  static const String devicesBatchGenerate = '/devices/batch-generate';
  static const String devicesAllocateStore = '/devices/allocate-store';
  static const String devicesClaim = '/devices/claim';
  static const String devicesLookupCode = '/devices/lookup-code';
  static const String devicesConfigureByCode = '/devices/configure-by-code';
  static const String devicesFleetStats = '/devices/fleet/stats';
  static String deviceDetail(String id) => '/devices/$id';
  static String deviceStoreInventory(String storeId) =>
      '/devices/stores/$storeId/inventory';
  static String deviceCustomerConfig(String id) =>
      '/devices/$id/customer-config';
  static String deviceEnable(String id) => '/devices/$id/enable';
  static String deviceDisable(String id) => '/devices/$id/disable';
  static String deviceStatus(String id) => '/devices/$id/status';
  static String deviceToggleActive(String id) => '/devices/$id/toggle-active';
  static String deviceSimulatePress(String id) => '/devices/$id/simulate-press';
  static String deviceTelemetry(String id) => '/devices/$id/telemetry';
  static String deviceAuditLogs(String id) => '/devices/$id/audit-logs';
  static String devicePair(String id) => '/devices/$id/pair';
  static String deviceRepair(String id) => '/devices/$id/re-pair';
  static String deviceAssign(String id) => '/devices/$id/assign';
  static String deviceAssignProduct(String id) => '/devices/$id/assign-product';
  static String deviceRemoveProduct(String id) => '/devices/$id/product';
  static String deviceBehavior(String id) => '/devices/$id/behavior';
  static String deviceBattery(String id) => '/devices/$id/battery';
  static String deviceExtendWarranty(String id) =>
      '/devices/$id/extend-warranty';
  static String deviceFactoryReset(String id) => '/devices/$id/factory-reset';
  static String deviceChangeWifi(String id) => '/devices/$id/change-wifi';
  static String deviceUnclaim(String id) => '/devices/$id/unclaim';
  static String deviceTransfer(String id) => '/devices/$id/transfer';
  static String deviceClaimCustomer(String id) => '/devices/$id/claim';

  // Device templates endpoints
  static const String deviceTemplates = '/device-templates';
  static String deviceTemplateDetail(String id) => '/device-templates/$id';
  static String deviceTemplateDeploy(String id) =>
      '/device-templates/$id/deploy';

  // Warranty endpoints
  static const String warrantyTickets = '/warranty/tickets';
  static String warrantyTicketDetail(String id) => '/warranty/tickets/$id';
  static String warrantyApproveSwap(String id) =>
      '/warranty/tickets/$id/approve-swap';
  static String warrantyLockDevice(String id) =>
      '/warranty/tickets/$id/lock-device';
  static String warrantyResolve(String id) => '/warranty/tickets/$id/resolve';
  static String warrantyReject(String id) => '/warranty/tickets/$id/reject';

  // Rental returns & customer rentals endpoints
  static const String rentalReturns = '/rentals/returns';
  static String rentalDetail(String id) => '/rentals/$id';
  static String rentalExtensions(String id) => '/rentals/$id/extensions';
  static String rentalReturnConfirmReceipt(String returnId) =>
      '/rentals/returns/$returnId/confirm-receipt';
  static String rentalRefundApprove(String refundId) =>
      '/rentals/refunds/$refundId/approve';

  // Products, categories & discounts endpoints
  static const String products = '/products';
  static String productDetail(String id) => '/products/$id';
  static String productInventory(String id) => '/products/$id/inventory';
  static String productImages(String id) => '/products/$id/images';
  static String productImageDetail(String productId, String imageId) =>
      '/products/$productId/images/$imageId';
  static String storeCategories(String storeId) =>
      '/stores/$storeId/categories';
  static String categoryDetail(String id) => '/categories/$id';
  static String discountDetail(String id) => '/discounts/$id';
  static String storeInventory(String storeId) => '/stores/$storeId/inventory';
  static String storeInventoryLowStock(String storeId) =>
      '/stores/$storeId/inventory/low-stock';

  // Orders & storefront endpoints
  static const String orders = '/orders';
  static const String ordersQuickReorder = '/orders/quick-reorder';
  static const String ordersSimulatePress = '/orders/simulate-button-press';
  static const String ordersDeliveryQuote = '/orders/delivery-quote';
  static const String ordersDeliveryQueue = '/orders/delivery-queue';
  static const String storefrontOrders = '/storefront/orders';
  static String orderDetail(String id) => '/orders/$id';
  static String orderCancel(String id) => '/orders/$id/cancel';
  static String orderStatus(String id) => '/orders/$id/status';
  static String orderClaim(String id) => '/orders/$id/claim';
  static String orderTakeoverDelivery(String id) =>
      '/orders/$id/takeover-delivery';
  static String orderDeliver(String id) => '/orders/$id/deliver';
  static String orderFailDelivery(String id) => '/orders/$id/fail';
  static String orderPodView(String id) => '/orders/$id/pod-view';
  static String orderRefund(String id) => '/orders/$id/refund';
  static String productDiscounts(String productId) =>
      '/products/$productId/discounts';

  // Provisioning endpoints
  static const String provisioningSession = '/provisioning/session';
  static const String provisioningVerify = '/provisioning/verify';
  static String provisioningConfirm(String sessionId) =>
      '/provisioning/sessions/$sessionId/confirm';
  static String provisioningChangeWifi(String id) =>
      '/provisioning/devices/$id/change-wifi';

  // Media endpoints
  static const String mediaUpload = '/media/upload';
  static const String mediaSignature = '/media/signature';

  // Stores & Rentals & Wallet & Merchant modules
  static const String stores = '/stores';
  static const String adminStores = '/admin/stores';
  static const String storeMe = '/stores/me';
  static String storeDetail(String id) => '/stores/$id';
  static const String rentalPackages = '/rentals/packages';
  static const String rentalOrder = '/rentals/order';
  static const String myRentals = '/rentals/my-rentals';
  static const String storeWallet = '/store/wallet';
  static const String storeWalletTransactions = '/store/wallet/transactions';
  static const String storeWalletWithdrawals = '/store/wallet/withdrawals';
  static String storeWalletWithdrawalSync(String id) =>
      '/store/wallet/withdrawals/$id/sync-status';
  static const String storeWalletBankAccount = '/store/wallet/bank-account';
  static String storeBankAccounts(String storeId) =>
      '/stores/$storeId/bank-accounts';
  static const String storeBankAccountVerification =
      '/stores/bank-accounts/verification';
  static const String storeSubscriptions = '/store/subscriptions';
  static const String storeSubscriptionCurrent = '/store/subscriptions/current';
  static const String storeSubscriptionPlans = '/store/subscriptions/plans';
  static const String storeSubscriptionSubscribe =
      '/store/subscriptions/subscribe';
  static const String storeSubscriptionRenewCharge =
      '/store/subscriptions/renew-charge';
  static String storeCashReceipts(String storeId) =>
      '/stores/$storeId/cash-receipts';
  static String storeRentalHandoverPreview(String storeId, String rentalId) =>
      '/stores/$storeId/rentals/$rentalId/handover-preview';
  static const String storeStaffRoles = '/store-staff-roles';
  static String storeStaff(String storeId) => '/stores/$storeId/staff';
  static String storeStaffDetail(String id) => '/store-staff/$id';
  static String storeCustomers(String storeId) => '/stores/$storeId/customers';
  static String storeCustomerStatus(String storeId, String customerId) =>
      '/stores/$storeId/customers/$customerId/status';
  static const String analyticsDashboard = '/analytics/dashboard';
  static const String analyticsAlerts = '/analytics/alerts';

  // Customer analytics & stores
  static const String customerDashboard = '/customers/me/dashboard';
  static const String customerAnalyticsOrders = '/customers/me/analytics/orders';
  static const String customerOrdersAnalytics = '/customers/me/analytics/orders';
  static const String customerDevicesAnalytics =
      '/customers/me/analytics/devices';
  static const String customerRentalsAnalytics =
      '/customers/me/analytics/rentals';
  static const String customerStores = '/customers/me/stores';
  static const String customerMyStores = '/customers/me/stores';

  // Admin endpoints (exact match to admin.controller.ts & admin-rentals.controller.ts)
  static String adminStoreDetail(String id) => '/admin/stores/$id';
  static String adminStoreApprove(String id) => '/admin/stores/$id/approve';
  static String adminStoreReject(String id) => '/admin/stores/$id/reject';
  static const String adminStats = '/admin/stats';
  static const String adminDashboard = '/admin/dashboard';
  static const String adminUsers = '/admin/users';
  static String adminUserToggleStatus(String id) =>
      '/admin/users/$id/toggle-status';
  static String adminUserRole(String id) => '/admin/users/$id/role';
  static const String adminRentalPackages = '/admin/rentals/packages';
  static String adminRentalPackageDetail(String id) =>
      '/admin/rentals/packages/$id';
  static const String adminRentals = '/admin/rentals';
  static String adminRentalAssignFulfillment(String id) =>
      '/admin/rentals/$id/assign-fulfillment';
  static String adminRentalHandover(String id) => '/admin/rentals/$id/handover';
  static String adminRentalRefundConfirmPayout(String refundId) =>
      '/admin/rentals/refunds/$refundId/confirm-payout';
  static const String adminWithdrawals = '/admin/withdrawals';
  static String adminWithdrawalPayout(String id) =>
      '/admin/withdrawals/$id/payout';
  static String adminWithdrawalSyncPayout(String id) =>
      '/admin/withdrawals/$id/sync-payout';
  static String adminWithdrawalReject(String id) =>
      '/admin/withdrawals/$id/reject';
  static const String adminPlans = '/admin/plans';
  static String adminPlanDetail(String id) => '/admin/plans/$id';
  static const String identityVerificationSessions =
      '/identity-verifications/sessions';
  static String identityVerificationSessionDetail(String id) =>
      '/identity-verifications/sessions/$id';
  static const String adminRefundObligations =
      '/admin/payment-refunds/obligations';
  static String adminRefundObligationPayout(String id) =>
      '/admin/payment-refunds/obligations/$id/payout';
  static String adminRefundObligationSync(String id) =>
      '/admin/payment-refunds/obligations/$id/sync';
  static const String adminAuditLogs = '/admin/audit-logs';
  static const String adminAnalyticsRevenue = '/admin/analytics/revenue';
  static const String adminAnalyticsOperations = '/admin/analytics/operations';
  static const String adminAnalyticsStores = '/admin/analytics/stores';

  // Addresses endpoints
  static const String addresses = '/customer-addresses';
  static String addressDetail(String id) => '$addresses/$id';

  // Notifications endpoints
  static const String notifications = '/notifications';
  static const String notificationsUnreadCount = '/notifications/unread-count';
  static String notificationMarkRead(String id) => '/notifications/$id/read';
  static const String notificationsReadAll = '/notifications/read-all';
  static const String notificationsFcmToken = '/notifications/fcm-token';

  // Payments endpoints
  static const String paymentsPayosCreateLink = '/payments/payos/create-link';
  static String paymentsPayosRequest(String id) =>
      '/payments/payos/payment-requests/$id';
  static String paymentsPayosCancel(String id) =>
      '/payments/payos/payment-requests/$id/cancel';
  static String paymentsChangeMethod(String orderId) =>
      '/payments/orders/$orderId/payment-method';
}
