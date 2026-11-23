import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_order_button/models/device_model.dart';
import 'package:smart_order_button/screens/customer_buttons_screen.dart';
import 'package:smart_order_button/services/api_client.dart';
import 'package:smart_order_button/services/stock_service.dart';
import 'package:smart_order_button/services/customer_buttons_api_service.dart';
import 'package:smart_order_button/services/devices_api_service.dart';

http.Response _response(String body, int status) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  late ApiClient api;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = ApiClient();
    await api.setTokens(accessToken: 'test-only');
  });
  tearDown(() => api.testClient = http.Client());

  test('F10: server restriction survives parsing and copyWith', () {
    final device = DeviceModel.fromJson({
      'deviceId': '42',
      'canOrder': false,
      'inventoryState': 'RETURN_IN_TRANSIT',
      'rentalId': '7',
    });
    expect(device.orderRestriction, 'Nút đang chờ cửa hàng nhận lại');
    expect(device.copyWith(name: 'New name').canOrder, isFalse);
    expect(device.copyWith(name: 'New name').rentalId, '7');
    expect(DeviceModel.fromJson({'canOrder': true}).orderRestriction, isNull);
  });

  test(
    'F10: legacy device response is enriched from the customer contract',
    () async {
      api.testClient = MockClient((request) async {
        if (request.url.path.endsWith('/rentals/my-rentals')) {
          return _response(
            jsonEncode({
              'data': [
                {
                  'rentalId': '7',
                  'status': 'PENDING_HANDOVER',
                  'depositAmount': 100000,
                  'canOrder': false,
                  'buttons': [
                    {'buttonId': '42', 'name': 'Button'},
                  ],
                },
              ],
            }),
            200,
          );
        }
        return _response(
          jsonEncode({
            'data': {'buttonId': '42', 'deviceId': 'ESP-42', 'products': []},
          }),
          200,
        );
      });
      final device = await DevicesApiService().getDeviceModelById('ESP-42');
      expect(device.canOrder, isFalse);
      expect(device.orderRestriction, 'Nút chưa được bàn giao');
    },
  );

  test(
    'F10: cannot place an order for a returned button even with enough stock',
    () async {
      api.testClient = MockClient(
        (request) async => _response(
          jsonEncode({
            'data': {
              'deviceId': 'returned-test',
              'canOrder': false,
              'inventoryState': 'RETURN_IN_TRANSIT',
              'products': [
                {'productId': '10', 'quantity': 1},
              ],
            },
          }),
          200,
        ),
      );
      await expectLater(
        StockService.instance.verify('returned-test'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            contains('chờ cửa hàng nhận lại'),
          ),
        ),
      );
    },
  );

  testWidgets(
    'F06: customer sees deposit, no rental fee or renewal, return request does not report refund',
    (tester) async {
      var returnRequests = 0;
      api.testClient = MockClient((request) async {
        if (request.method == 'GET') {
          expect(request.url.path, endsWith('/rentals/my-rentals'));
          return _response(
            jsonEncode({
              'data': [
                {
                  'rentalId': '7',
                  'rentalCode': 'RNT-7',
                  'status': 'ACTIVE',
                  'depositAmount': 100000,
                  'totalRentAmount': 150000,
                  'buttons': [
                    {'buttonId': '42', 'name': 'Nút Bếp', 'status': 'ACTIVE'},
                  ],
                },
              ],
            }),
            200,
          );
        }
        expect(request.url.path, endsWith('/rentals/7/return-requests'));
        expect(jsonDecode(request.body), {'buttonId': '42'});
        returnRequests++;
        return _response(
          jsonEncode({
            'data': {'returnId': '8', 'status': 'PENDING_RECEIPT'},
          }),
          200,
        );
      });
      expect(await CustomerButtonsApiService().getMyButtons(), hasLength(1));
      await tester.pumpWidget(const MaterialApp(home: CustomerButtonsScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('100.000'), findsOneWidget);
      expect(find.textContaining('150.000'), findsNothing);
      expect(find.text('Gia hạn'), findsNothing);
      await tester.tap(find.byTooltip('Làm mới'));
      await tester.pumpAndSettle();
      expect(find.textContaining('100.000'), findsOneWidget);
      await tester.tap(find.text('Yêu cầu trả nút'));
      await tester.pumpAndSettle();
      expect(returnRequests, 0);
      expect(find.textContaining('Tiền cọc chỉ được hoàn sau'), findsOneWidget);
      await tester.tap(find.text('Gửi yêu cầu'));
      await tester.pumpAndSettle();
      expect(returnRequests, 1);
      expect(
        find.text('Đã gửi yêu cầu — chờ cửa hàng nhận lại'),
        findsOneWidget,
      );
      expect(find.text('Đã hoàn cọc'), findsNothing);
    },
  );

  testWidgets('F06: failed return request does not advance the button status', (
    tester,
  ) async {
    api.testClient = MockClient(
      (request) async => request.method == 'GET'
          ? _response(
              jsonEncode({
                'data': [
                  {
                    'rentalId': '7',
                    'status': 'ACTIVE',
                    'depositAmount': 100000,
                    'buttons': [
                      {'buttonId': '42', 'name': 'Nút Bếp'},
                    ],
                  },
                ],
              }),
              200,
            )
          : _response(jsonEncode({'message': 'Không thể nhận yêu cầu'}), 400),
    );
    await tester.pumpWidget(const MaterialApp(home: CustomerButtonsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yêu cầu trả nút'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gửi yêu cầu'));
    await tester.pumpAndSettle();
    expect(find.text('Không thể nhận yêu cầu'), findsOneWidget);
    expect(find.text('Đã gửi yêu cầu — chờ cửa hàng nhận lại'), findsNothing);
  });

  testWidgets(
    'Tab 1 renders live string decimal monthlyPrice/depositFee and orders with X-Idempotency-Key + whitelisted DTO',
    (tester) async {
      String? sentIdempotencyKey;
      Map<String, dynamic>? sentOrderBody;
      var myRentalsCalls = 0;

      api.testClient = MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith('/rentals/packages')) {
          return _response(
            jsonEncode({
              'success': true,
              'data': [
                {
                  'packageId': 43,
                  'packageCode': 'KIT_3THANG',
                  'packageName': 'Gói Kit 3 nút',
                  'description': 'Gói tiện lợi cho gia đình',
                  'buttonQuantity': 3,
                  'monthlyPrice': '30',
                  'depositFee': '100000',
                  'isActive': true,
                },
                {
                  'packageId': 42,
                  'packageCode': 'GOI_1NUT',
                  'packageName': 'Bộ kit 1 nút bấm',
                  'description': 'Gói khởi đầu 1 nút bấm',
                  'buttonQuantity': 1,
                  'monthlyPrice': '3000',
                  'depositFee': '20000',
                  'isActive': true,
                },
              ],
            }),
            200,
          );
        }
        if (request.method == 'POST' &&
            request.url.path.endsWith('/rentals/order')) {
          sentIdempotencyKey = request.headers['X-Idempotency-Key'];
          sentOrderBody = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map,
          );
          return _response(
            jsonEncode({
              'success': true,
              'data': {
                'rentalId': '99',
                'rentalCode': 'RNT-99',
                'status': 'PENDING_PAYMENT',
                'depositAmount': 20000,
                'monthsRented': 3,
              },
            }),
            201,
          );
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/rentals/my-rentals')) {
          myRentalsCalls++;
          return _response(
            jsonEncode({
              'success': true,
              'data': [
                {
                  'rentalId': '99',
                  'rentalCode': 'RNT-99',
                  'status': 'PENDING_PAYMENT',
                  'depositAmount': '20000',
                  'monthsRented': 3,
                  'package': {'packageName': 'Bộ kit 1 nút bấm'},
                  'buttons': [],
                },
              ],
            }),
            200,
          );
        }
        return _response(jsonEncode({'data': []}), 200);
      });

      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: CustomerButtonsScreen(initialTab: 0)),
      );
      await tester.pumpAndSettle();

      // Verifies no ErrorWidget crash and real decimal strings render cleanly
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text('Gói Kit 3 nút'), findsOneWidget);
      expect(find.text('Bộ kit 1 nút bấm'), findsOneWidget);
      expect(find.textContaining('100.000'), findsOneWidget);
      expect(find.textContaining('3.000'), findsOneWidget);
      expect(find.textContaining('20.000'), findsOneWidget);

      // Open rent sheet for second package and submit
      final rentButtons = find.text('Thuê gói nút này');
      expect(rentButtons, findsNWidgets(2));
      await tester.ensureVisible(rentButtons.last);
      await tester.pumpAndSettle();
      await tester.tap(rentButtons.last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('3 tháng'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Xác nhận đặt thuê nút'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận đặt thuê nút'));
      await tester.pumpAndSettle();

      expect(sentIdempotencyKey, isNotNull);
      expect(sentIdempotencyKey, isNotEmpty);
      expect(sentOrderBody, {'packageId': 42, 'monthsRented': 3});
      expect(myRentalsCalls, greaterThanOrEqualTo(1));
      expect(find.text('Hồ sơ RNT-99'), findsOneWidget);
      expect(find.text('Chờ hoàn tất tiền cọc'), findsOneWidget);
      expect(find.text('Thanh toán tiền cọc'), findsOneWidget);
    },
  );

  testWidgets(
    'Tab 2 surfaces clear 403 non-customer message with CTA to view packages',
    (tester) async {
      api.testClient = MockClient((request) async {
        if (request.url.path.endsWith('/rentals/my-rentals')) {
          return _response(
            jsonEncode({
              'success': false,
              'message':
                  'Chỉ tài khoản khách hàng mới có thể xem danh sách nút thuê',
            }),
            403,
          );
        }
        return _response(jsonEncode({'success': true, 'data': []}), 200);
      });

      await tester.pumpWidget(const MaterialApp(home: CustomerButtonsScreen()));
      await tester.pumpAndSettle();

      expect(
        find.text('Chỉ tài khoản khách hàng mới có thể xem danh sách nút thuê'),
        findsOneWidget,
      );
      expect(find.text('Xem gói thuê nút'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
    },
  );
}
