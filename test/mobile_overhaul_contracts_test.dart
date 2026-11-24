import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_order_button/providers/notification_provider.dart';
import 'package:smart_order_button/services/admin_api_service.dart';
import 'package:smart_order_button/services/api_client.dart';
import 'package:smart_order_button/services/devices_api_service.dart';
import 'package:smart_order_button/services/merchant_api_service.dart';
import 'package:smart_order_button/services/orders_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ApiClient().testClient = http.Client();
    await ApiClient().setTokens(
      accessToken: 'access-tok',
      refreshToken: 'refresh-tok',
    );
  });

  tearDown(() async {
    ApiClient().testClient = http.Client();
    await ApiClient().clearTokens();
  });

  group('Mobile Overhaul BE Contract & Resilience Tests', () {
    test('ApiClient surfaces HTTP 429 Retry-After cleanly as RATE_LIMITED', () async {
      ApiClient().testClient = MockClient((req) async {
        return http.Response(
          jsonEncode({'message': 'Too many requests'}),
          429,
          headers: {'retry-after': '42', 'content-type': 'application/json'},
        );
      });

      await expectLater(
        () => ApiClient().get('/orders'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 429)
              .having((e) => e.errorCode, 'errorCode', 'RATE_LIMITED')
              .having((e) => e.message, 'message', contains('42')),
        ),
      );
    });

    test('ApiClient refreshes /auth/me on 401 and preserves session when refresh hits 503', () async {
      var meCalls = 0;
      ApiClient().testClient = MockClient((req) async {
        if (req.url.path.endsWith('/auth/me')) {
          meCalls++;
          return http.Response(jsonEncode({'message': 'Unauthorized'}), 401);
        }
        if (req.url.path.endsWith('/auth/refresh')) {
          // Transient upstream outage during Render cold start must NOT wipe tokens
          return http.Response(jsonEncode({'message': 'Service Unavailable'}), 503);
        }
        return http.Response('{}', 200);
      });

      await expectLater(
        () => ApiClient().get('/auth/me'),
        throwsA(isA<ApiException>()),
      );
      expect(meCalls, 1);
      expect(ApiClient().isAuthenticated, isTrue);
    });

    test('DevicesApiService sends strict whitelisted DTOs for customer-config, simulate-press, unclaim', () async {
      final recorded = <({String method, String path, Map<String, dynamic> body})>[];
      ApiClient().testClient = MockClient((req) async {
        final decoded = req.body.isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(req.body) as Map);
        recorded.add((method: req.method, path: req.url.path, body: decoded));
        return http.Response(jsonEncode({'success': true, 'data': {}}), 200);
      });

      final api = DevicesApiService();
      await api.updateCustomerConfig(
        'SOB-1',
        buttonName: 'Bếp',
        productId: '10',
        storeId: '2',
        quantity: 2,
        roomLocation: 'should_be_stripped',
        holdDurationMs: 2500,
      );
      await api.simulatePress('SOB-1', pressType: 'SINGLE_PRESS');
      await api.unclaimDevice('SOB-1');

      expect(recorded[0].path, endsWith('/devices/SOB-1/customer-config'));
      expect(recorded[0].body.containsKey('roomLocation'), isFalse);
      expect(recorded[0].body.containsKey('holdDurationMs'), isFalse);
      expect(recorded[0].body['buttonName'], 'Bếp');

      expect(recorded[1].path, endsWith('/devices/SOB-1/simulate-press'));
      expect(recorded[1].body['pressType'], 'SINGLE_PRESS');
      expect(recorded[1].body.containsKey('eventType'), isFalse);

      expect(recorded[2].method, 'POST');
      expect(recorded[2].path, endsWith('/devices/SOB-1/unclaim'));
    });

    test('OrdersApiService matches UpdateOrderStatusDto, DeliverOrderDto, and DeliveryFailureDto', () async {
      final recorded = <({String method, String path, Map<String, dynamic> body})>[];
      ApiClient().testClient = MockClient((req) async {
        final decoded = req.body.isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(req.body) as Map);
        recorded.add((method: req.method, path: req.url.path, body: decoded));
        return http.Response(jsonEncode({'success': true, 'data': {}}), 200);
      });

      final ordersApi = OrdersApiService();
      await ordersApi.updateOrderStatus('42', status: 'CONFIRMED', note: 'ignored');
      await ordersApi.deliverOrder(
        '42',
        paymentMethod: 'COD',
        collectedAmount: 65000,
        podImageUrl: 'https://cdn.example.com/pod.jpg',
      );
      await ordersApi.failDelivery(
        '42',
        failureReasonCode: 'CUSTOMER_UNREACHABLE',
        failureNote: 'Không nghe máy',
        evidenceImageUrl: 'https://cdn.example.com/fail.jpg',
      );

      expect(recorded[0].body, {'status': 'CONFIRMED'});
      expect(recorded[1].body['status'], 'DELIVERED');
      expect(recorded[1].body['paymentMethod'], 'COD');
      expect(recorded[1].body['collectedAmount'], 65000);
      expect(recorded[1].body['podImageUrl'], 'https://cdn.example.com/pod.jpg');
      expect(recorded[2].body['failureReasonCode'], 'CUSTOMER_UNREACHABLE');
      expect(recorded[2].body['evidenceImageUrl'], 'https://cdn.example.com/fail.jpg');
    });

    test('NotificationProvider syncs server inbox and persists markAsRead to BE', () async {
      var readPatched = false;
      ApiClient().testClient = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/notifications')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'unreadCount': 1,
              'data': [
                {
                  'notificationId': '9001',
                  'type': 'ORDER_CREATED',
                  'title': 'Đơn mới #ORD-99',
                  'body': 'Cửa hàng đã tiếp nhận',
                  'readAt': null,
                  'createdAt': '2026-11-24T12:00:00.000Z',
                  'data': {'orderId': '99', 'orderCode': 'ORD-99'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (req.method == 'PATCH' && req.url.path.endsWith('/notifications/9001/read')) {
          readPatched = true;
          return http.Response(jsonEncode({'success': true}), 200);
        }
        return http.Response(jsonEncode({'success': true, 'data': []}), 200);
      });

      final provider = NotificationProvider();
      await provider.refreshFromServer();
      expect(provider.notifications.length, 1);
      expect(provider.notifications.first.id, '9001');
      expect(provider.notifications.first.orderCode, 'ORD-99');
      expect(provider.unreadCount, 1);

      await provider.markAsRead('9001');
      expect(provider.unreadCount, 0);
      expect(readPatched, isTrue);
    });

    test('MerchantApiService and AdminApiService hit exact BE routes', () async {
      final hits = <String>[];
      ApiClient().testClient = MockClient((req) async {
        hits.add('${req.method} ${req.url.path}');
        return http.Response(jsonEncode({'success': true, 'data': {}}), 200);
      });

      await MerchantApiService().updateProductStock('5', availableStock: 25, lowStockThreshold: 3);
      await AdminApiService().approveStore('12');
      await AdminApiService().payoutWithdrawal('88');

      expect(hits[0], endsWith('PATCH /api/v1/products/5/inventory'));
      expect(hits[1], endsWith('POST /api/v1/admin/stores/12/approve'));
      expect(hits[2], endsWith('POST /api/v1/admin/withdrawals/88/payout'));
    });
  });
}
