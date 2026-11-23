num? _parseContractNum(dynamic value) {
  if (value == null) return null;
  if (value is num) return value;
  return num.tryParse(value.toString().trim());
}

int? _parseContractInt(dynamic value) {
  final n = _parseContractNum(value);
  return n?.round();
}

class CustomerButtonContract {
  final String id;
  final String code;
  final String status;
  final num depositAmount;
  final bool? canOrder;
  final List<CustomerContractButton> buttons;
  final String? packageName;
  final int? monthsRented;
  final int? buttonQuantity;
  final Set<String> pendingReturnButtonIds;

  const CustomerButtonContract({
    required this.id,
    required this.code,
    required this.status,
    required this.depositAmount,
    required this.canOrder,
    required this.buttons,
    this.packageName,
    this.monthsRented,
    this.buttonQuantity,
    this.pendingReturnButtonIds = const {},
  });

  factory CustomerButtonContract.fromJson(Map<String, dynamic> json) {
    final id = (json['rentalId'] ?? json['id'])?.toString().trim();
    if (id == null || id.isEmpty) {
      throw const FormatException('Thiếu mã hồ sơ nút');
    }

    final pkg = json['package'] is Map
        ? Map<String, dynamic>.from(json['package'] as Map)
        : null;
    final breakdown = json['depositBreakdown'] is Map
        ? Map<String, dynamic>.from(json['depositBreakdown'] as Map)
        : null;

    final rawDeposit =
        json['depositAmount'] ??
        breakdown?['depositAmount'] ??
        json['depositFee'] ??
        pkg?['depositFee'];
    final amount = rawDeposit == null ? 0 : _parseContractNum(rawDeposit);
    if (amount == null || amount < 0) {
      throw const FormatException('Tiền cọc không hợp lệ');
    }

    final rawButtons = json['buttons'] ?? json['rentalButtons'];
    final buttons = (rawButtons is List ? rawButtons : const [])
        .whereType<Map>()
        .map(
          (button) => CustomerContractButton.fromJson(
            Map<String, dynamic>.from(button),
          ),
        )
        .toList();

    final pendingReturns = <String>{};
    final rawReturns = json['returns'];
    if (rawReturns is List) {
      for (final item in rawReturns.whereType<Map>()) {
        final retStatus = item['status']?.toString().toUpperCase() ?? '';
        final btnId = item['buttonId']?.toString().trim();
        if (btnId != null &&
            btnId.isNotEmpty &&
            retStatus != 'CANCELLED' &&
            retStatus != 'REJECTED') {
          pendingReturns.add(btnId);
        }
      }
    }
    for (final button in buttons) {
      if (button.inventoryState == 'RETURN_IN_TRANSIT') {
        pendingReturns.add(button.id);
      }
    }

    final pkgName = (pkg?['packageName'] ??
            pkg?['name'] ??
            json['packageName'])
        ?.toString()
        .trim();

    return CustomerButtonContract(
      id: id,
      code: (json['rentalCode']?.toString().trim().isNotEmpty == true)
          ? json['rentalCode'].toString().trim()
          : id,
      status: json['status']?.toString().trim().toUpperCase() ?? 'UNKNOWN',
      depositAmount: amount,
      canOrder: json['canOrder'] is bool ? json['canOrder'] as bool : null,
      buttons: buttons,
      packageName: (pkgName != null && pkgName.isNotEmpty) ? pkgName : null,
      monthsRented: _parseContractInt(json['monthsRented'] ?? json['months']),
      buttonQuantity: _parseContractInt(
        json['buttonQuantity'] ?? pkg?['buttonQuantity'],
      ),
      pendingReturnButtonIds: pendingReturns,
    );
  }

  String get statusLabel => switch (status) {
    'PENDING_PAYMENT' => 'Chờ hoàn tất tiền cọc',
    'PENDING_HANDOVER' => 'Chờ bàn giao nút',
    'PAID' => 'Đã hoàn tất tiền cọc',
    'ACTIVE' => 'Đang sử dụng',
    'EXPIRED' => 'Tạm ngừng sử dụng — liên hệ cửa hàng',
    'RETURN_REQUESTED' => 'Đang chờ cửa hàng nhận lại nút',
    'RETURNED' => 'Cửa hàng đã nhận lại nút',
    'TERMINATED' => 'Đã kết thúc hợp đồng',
    'CANCELLED' => 'Đã hủy',
    _ => 'Đang cập nhật',
  };

  bool get canRequestReturn => {'ACTIVE', 'EXPIRED'}.contains(status);
}

class CustomerContractButton {
  final String id;
  final String name;
  final String status;
  final String? inventoryState;

  const CustomerContractButton({
    required this.id,
    required this.name,
    required this.status,
    this.inventoryState,
  });

  factory CustomerContractButton.fromJson(Map<String, dynamic> json) {
    final id = (json['buttonId'] ?? json['id'] ?? json['deviceId'])
        ?.toString()
        .trim();
    if (id == null || id.isEmpty) throw const FormatException('Thiếu mã nút');
    return CustomerContractButton(
      id: id,
      name:
          json['name']?.toString() ??
          json['buttonName']?.toString() ??
          json['buttonCode']?.toString() ??
          json['deviceId']?.toString() ??
          'Nút thông minh',
      status: json['status']?.toString() ?? 'UNKNOWN',
      inventoryState: json['inventoryState']?.toString().toUpperCase(),
    );
  }
}
