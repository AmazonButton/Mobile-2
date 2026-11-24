import 'dart:convert';

/// Model representing an in-app notification item.
class NotificationItem {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final String type; // 'ORDER_CREATED', 'ORDER_STATUS_CHANGED', 'SYSTEM', etc.
  final String? orderId;
  final String? orderCode;

  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
    this.type = 'ORDER_CREATED',
    this.orderId,
    this.orderCode,
  });

  NotificationItem copyWith({
    String? id,
    String? title,
    String? body,
    DateTime? createdAt,
    bool? isRead,
    String? type,
    String? orderId,
    String? orderCode,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      type: type ?? this.type,
      orderId: orderId ?? this.orderId,
      orderCode: orderCode ?? this.orderCode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'createdAt': createdAt.toIso8601String(),
      'isRead': isRead,
      'type': type,
      'orderId': orderId,
      'orderCode': orderCode,
    };
  }

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    final nestedData = json['data'] is Map ? Map<String, dynamic>.from(json['data'] as Map) : const <String, dynamic>{};
    final readAt = json['readAt'] ?? json['read_at'];
    final isReadVal = json['isRead'] == true || (readAt != null && readAt.toString().isNotEmpty);
    return NotificationItem(
      id: (json['notificationId'] ?? json['notification_id'] ?? json['id'])?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      title: json['title']?.toString() ?? 'Thông báo',
      body: (json['body'] ?? json['message'])?.toString() ?? '',
      createdAt: (json['createdAt'] ?? json['created_at']) != null
          ? (DateTime.tryParse((json['createdAt'] ?? json['created_at']).toString()) ?? DateTime.now())
          : DateTime.now(),
      isRead: isReadVal,
      type: json['type']?.toString() ?? 'ORDER_CREATED',
      orderId: (json['orderId'] ?? nestedData['orderId'])?.toString(),
      orderCode: (json['orderCode'] ?? nestedData['orderCode'])?.toString(),
    );
  }

  /// Relative human-readable time formatting in Vietnamese
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inSeconds < 45) {
      return 'Vừa xong';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} phút trước';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} giờ trước';
    } else if (difference.inDays == 1) {
      final hour = createdAt.hour.toString().padLeft(2, '0');
      final minute = createdAt.minute.toString().padLeft(2, '0');
      return 'Hôm qua, $hour:$minute';
    } else {
      final day = createdAt.day.toString().padLeft(2, '0');
      final month = createdAt.month.toString().padLeft(2, '0');
      final year = createdAt.year;
      final hour = createdAt.hour.toString().padLeft(2, '0');
      final minute = createdAt.minute.toString().padLeft(2, '0');
      return '$day/$month/$year $hour:$minute';
    }
  }

  static String encodeList(List<NotificationItem> list) {
    return jsonEncode(list.map((item) => item.toJson()).toList());
  }

  static List<NotificationItem> decodeList(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is List) {
        return decoded
            .map((item) => NotificationItem.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
    } catch (_) {}
    return [];
  }
}
