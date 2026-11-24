import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/notification_item.dart';
import 'api_client.dart';
import 'api_config.dart';

class NotificationsApiService {
  final ApiClient _apiClient;

  NotificationsApiService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  /// Lấy danh sách thông báo thực từ Backend (GET /notifications)
  Future<({List<NotificationItem> items, int unreadCount})> getNotifications({
    int page = 1,
    int pageSize = 30,
  }) async {
    final response = await _apiClient.get(
      ApiConfig.notifications,
      queryParams: {
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      },
    );
    final rawList = response is Map
        ? (response['data'] is List
              ? response['data'] as List
              : (response['items'] is List ? response['items'] as List : const []))
        : (response is List ? response : const []);
    final items = rawList
        .whereType<Map>()
        .map((e) => NotificationItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final unread = response is Map && response['unreadCount'] != null
        ? int.tryParse(response['unreadCount'].toString()) ??
            items.where((e) => !e.isRead).length
        : items.where((e) => !e.isRead).length;
    return (items: items, unreadCount: unread);
  }

  /// Lấy số thông báo chưa đọc từ Backend (GET /notifications/unread-count)
  Future<int> getUnreadCount() async {
    final response = await _apiClient.get(ApiConfig.notificationsUnreadCount);
    if (response is Map) {
      final data = response['data'] is Map ? response['data'] as Map : response;
      return int.tryParse((data['unreadCount'] ?? 0).toString()) ?? 0;
    }
    return 0;
  }

  /// Đánh dấu một thông báo đã đọc trên Backend (PATCH /notifications/:id/read)
  Future<bool> markAsRead(String id) async {
    if (id.trim().isEmpty) return false;
    try {
      await _apiClient.patch(ApiConfig.notificationMarkRead(id.trim()));
      return true;
    } catch (e) {
      debugPrint('[NotificationsApiService] markAsRead error: $e');
      return false;
    }
  }

  /// Đánh dấu tất cả thông báo đã đọc trên Backend (PATCH /notifications/read-all)
  Future<bool> markAllAsRead() async {
    try {
      await _apiClient.patch(ApiConfig.notificationsReadAll);
      return true;
    } catch (e) {
      debugPrint('[NotificationsApiService] markAllAsRead error: $e');
      return false;
    }
  }

  /// Đăng ký hoặc cập nhật FCM Device Token lên Backend
  Future<bool> registerFcmToken(
    String token, {
    String deviceType = 'ANDROID',
  }) async {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) return false;

    try {
      final response = await _apiClient.post(
        ApiConfig.notificationsFcmToken,
        body: {
          'token': trimmedToken,
          'deviceType': deviceType.toUpperCase(),
        },
      );

      if (response != null && response is Map<String, dynamic>) {
        return response['success'] == true;
      }
      return true;
    } catch (e) {
      debugPrint('[NotificationsApiService] Lỗi khi đăng ký FCM token: $e');
      return false;
    }
  }

  /// Hủy đăng ký hoặc vô hiệu hóa FCM Device Token khi đăng xuất
  Future<bool> unregisterFcmToken(String token) async {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) return false;

    try {
      final response = await _apiClient.delete(
        ApiConfig.notificationsFcmToken,
        body: {
          'token': trimmedToken,
        },
      );

      if (response != null && response is Map<String, dynamic>) {
        return response['success'] == true;
      }
      return true;
    } catch (e) {
      debugPrint('[NotificationsApiService] Lỗi khi hủy FCM token: $e');
      return false;
    }
  }
}
