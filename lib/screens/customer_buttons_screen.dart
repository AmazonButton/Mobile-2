import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import 'customer_bank_accounts_screen.dart';
import '../models/customer_button_contract.dart';
import '../providers/address_provider.dart';
import '../services/api_client.dart';
import '../services/customer_buttons_api_service.dart';
import '../services/stores_api_service.dart';
import '../utils/formatters.dart';
import '../widgets/app_motion.dart';
import '../widgets/resident_ui.dart';
import '../widgets/smart_order_tour.dart';

num _parseNum(dynamic value, {num fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value;
  return num.tryParse(value.toString().trim()) ?? fallback;
}

int _parseInt(dynamic value, {int fallback = 1}) {
  final parsed = _parseNum(value, fallback: fallback);
  return parsed.round();
}

class CustomerButtonsScreen extends StatefulWidget {
  final CustomerButtonsApiService? service;
  final StoresApiService? storesService;
  final SmartOrderTour? tour;
  final int initialTab;

  const CustomerButtonsScreen({
    super.key,
    this.service,
    this.storesService,
    this.tour,
    this.initialTab = 1,
  });

  @override
  State<CustomerButtonsScreen> createState() => _CustomerButtonsScreenState();
}

class _CustomerButtonsScreenState extends State<CustomerButtonsScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final _service = widget.service ?? CustomerButtonsApiService();
  late final _storesService = widget.storesService ?? StoresApiService();

  late TabController _tabController;
  Future<List<CustomerButtonContract>>? _contracts;
  Future<List<dynamic>>? _packages;

  final Set<String> _pendingReturns = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final startTab = widget.initialTab.clamp(0, 1);
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: startTab,
    )..addListener(_handleTabChanged);

    if (startTab == 0) {
      _packages = _storesService.getRentalPackages();
      _contracts = _service.getMyButtons();
    } else {
      _contracts = _service.getMyButtons();
    }
  }

  void _ensureTabLoaded(int index) {
    if (!mounted) return;
    if (index == 0 && _packages == null) {
      setState(() {
        _packages = _storesService.getRentalPackages();
      });
    } else if (index == 1 && _contracts == null) {
      setState(() {
        _contracts = _service.getMyButtons();
      });
    }
  }

  void _handleTabChanged() => _ensureTabLoaded(_tabController.index);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _reload();
  }

  Future<void> _reload() async {
    final activeIndex = _tabController.index;
    final Future<List<dynamic>>? nextPackages =
        (activeIndex == 0 || _packages != null)
        ? _storesService.getRentalPackages()
        : null;
    final Future<List<CustomerButtonContract>>? nextContracts =
        (activeIndex == 1 || _contracts != null)
        ? _service.getMyButtons()
        : null;

    setState(() {
      if (nextPackages != null) _packages = nextPackages;
      if (nextContracts != null) _contracts = nextContracts;
    });

    final pending = <Future<dynamic>>[?nextPackages, ?nextContracts];
    try {
      await Future.wait(pending);
    } catch (_) {
      /* FutureBuilders own their error states */
    }
  }

  Future<void> _reloadPackagesOnly() async {
    final next = _storesService.getRentalPackages();
    setState(() => _packages = next);
    try {
      await next;
    } catch (_) {}
  }

  Future<void> _reloadContractsOnly() async {
    final next = _service.getMyButtons();
    setState(() => _contracts = next);
    try {
      await next;
    } catch (_) {}
  }

  Future<void> _requestReturn(
    CustomerButtonContract contract,
    CustomerContractButton button,
  ) async {
    final key = '${contract.id}:${button.id}';
    if (_busy || _pendingReturns.contains(key)) return;
    final confirmed = await showResidentConfirmation(
      context,
      title: 'Trả lại nút?',
      message:
          'Gửi yêu cầu trả ${button.name}. Tiền cọc chỉ được hoàn sau khi cửa hàng xác nhận đã nhận lại nút.',
      confirmLabel: 'Gửi yêu cầu',
      cancelLabel: 'Quay lại',
      destructive: true,
    );
    if (!mounted ||
        confirmed != true ||
        _busy ||
        _pendingReturns.contains(key)) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _service.requestReturn(
        contractId: contract.id,
        buttonId: button.id,
      );
      if (!mounted) return;
      setState(() => _pendingReturns.add(key));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Đã gửi yêu cầu. Vui lòng trả nút cho cửa hàng và chờ xác nhận tiếp nhận.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiException
                  ? error.message
                  : 'Không thể gửi yêu cầu trả nút. Vui lòng tải lại và thử lại.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _payDeposit(CustomerButtonContract contract) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final payment = await _service.createDepositPaymentRequest(contract.id);
      if (!mounted) return;
      final checkoutUrl = payment['checkoutUrl']?.toString().trim();
      final qrCode = payment['qrCode']?.toString().trim();
      final amount = _parseNum(
        payment['amount'],
        fallback: contract.depositAmount,
      );
      final txCode = payment['transactionCode']?.toString().trim() ?? '';

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Hoàn tất tiền cọc ${contract.code}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Số tiền cọc: ${CurrencyFormatter.format(amount)} (hoàn lại 100% khi trả nút)',
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF475569),
                  ),
                ),
                if (txCode.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Mã giao dịch: $txCode',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
                if (qrCode != null && qrCode.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: QrImageView(
                        data: qrCode,
                        size: 190,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (checkoutUrl != null && checkoutUrl.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: () async {
                      final uri = Uri.tryParse(checkoutUrl);
                      if (uri != null && await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      } else if (ctx.mounted) {
                        await Clipboard.setData(
                          ClipboardData(text: checkoutUrl),
                        );
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Đã sao chép liên kết thanh toán PayOS.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(LucideIcons.externalLink, size: 16),
                    label: const Text('Mở cổng thanh toán PayOS'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _reloadContractsOnly();
                  },
                  child: const Text('Tôi đã thanh toán — Kiểm tra lại'),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFDC2626),
            content: Text(
              error is ApiException
                  ? error.message
                  : 'Không thể khởi tạo yêu cầu thanh toán tiền cọc.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openRentSheet(Map<String, dynamic> pkg) {
    HapticFeedback.lightImpact();
    final userAddress =
        context.read<AddressProvider?>()?.currentAddressDisplay ?? '';
    final addressCtrl = TextEditingController(text: userAddress);
    int months = 1;

    final pkgName =
        (pkg['packageName'] ?? pkg['name'] ?? 'Gói nút bấm').toString();
    final monthlyPrice = _parseNum(
      pkg['monthlyPrice'] ??
          pkg['monthlyFee'] ??
          pkg['price'] ??
          pkg['rentalPrice'],
    );
    final deposit = _parseNum(pkg['depositFee'] ?? pkg['depositAmount']);
    final buttonCount = _parseInt(
      pkg['buttonQuantity'] ?? pkg['numberOfButtons'],
      fallback: 1,
    );
    final packageId = (pkg['packageId'] ?? pkg['id'] ?? '').toString();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalContext, setModalState) {
          final totalRent = monthlyPrice * months;

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 18,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          LucideIcons.cpu,
                          color: Color(0xFF2563EB),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pkgName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Bao gồm $buttonCount nút bấm thông minh IoT',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Thời hạn thuê
                  const Text(
                    'Thời hạn thuê',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [1, 3, 6, 12].map((m) {
                      final selected = months == m;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: InkWell(
                            onTap: () => setModalState(() => months = m),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFF2563EB)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '$m tháng',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? Colors.white
                                        : const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),

                  // Địa chỉ nhận nút (tham khảo hiển thị tại máy)
                  const Text(
                    'Địa chỉ giao nhận nút (ghi chú)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: addressCtrl,
                    decoration: InputDecoration(
                      hintText: 'Nhập số nhà, tên đường, khu vực...',
                      prefixIcon: const Icon(
                        LucideIcons.mapPin,
                        size: 18,
                        color: Color(0xFF2563EB),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Chi tiết thanh toán
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              'Giá gói tham khảo ($months tháng)',
                              style: const TextStyle(color: Color(0xFF475569)),
                            ),
                            Text(
                              CurrencyFormatter.format(totalRent),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            const Text(
                              'Tiền cọc thiết bị (hoàn lại 100%)',
                              style: TextStyle(color: Color(0xFF475569)),
                            ),
                            Text(
                              CurrencyFormatter.format(deposit),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 18),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            const Text(
                              'Tiền cọc cần hoàn tất',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(deposit),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Khách hàng mới lần đầu được tặng thêm 7 ngày dùng thử. Tiền cọc được hoàn lại 100% khi bạn trả nút.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Nút xác nhận đặt thuê
                  ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final deliveryAddress = addressCtrl.text.trim();
                            Navigator.pop(ctx);
                            setState(() => _busy = true);
                            try {
                              await _storesService.orderRentalPackage(
                                packageId: packageId,
                                months: months,
                                deliveryAddress: deliveryAddress,
                              );
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: Color(0xFF16A34A),
                                  content: Text(
                                    'Đã tạo hợp đồng thuê nút thành công! Kiểm tra hồ sơ để hoàn tất tiền cọc.',
                                  ),
                                ),
                              );
                              _tabController.animateTo(1);
                              await _reloadContractsOnly();
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: const Color(0xFFDC2626),
                                  content: Text(
                                    e is ApiException
                                        ? e.message
                                        : 'Không thể đặt thuê gói. Vui lòng thử lại sau.',
                                  ),
                                ),
                              );
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Xác nhận đặt thuê nút',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(addressCtrl.dispose);
  }

  Widget _buildPackagesLoadingPlaceholder(BuildContext context) {
    final skeletonList = ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      itemBuilder: (_, _) => Container(
        height: 180,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
    if (!AppMotion.allowAmbient(context)) {
      return skeletonList;
    }
    return Shimmer.fromColors(
      baseColor: const Color(0xFFF1F5F9),
      highlightColor: Colors.white,
      child: skeletonList,
    );
  }

  Widget _buildTabError({
    required IconData icon,
    required String title,
    required String detail,
    required VoidCallback onRetry,
    Widget? secondaryAction,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF2F2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: const Color(0xFFDC2626)),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: onRetry,
                  child: const Text('Thử lại'),
                ),
                ?secondaryAction,
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    widget.tour?.trackRoute(context, TourStep.amount);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Thuê nút & Tiền cọc',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _busy ? null : _reload,
            icon: const Icon(
              LucideIcons.refreshCw,
              size: 20,
              color: Color(0xFF2563EB),
            ),
          ),
          IconButton(
            tooltip: 'Tài khoản hoàn cọc',
            icon: const Icon(
              LucideIcons.landmark,
              size: 20,
              color: Color(0xFF64748B),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const CustomerBankAccountsScreen(),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          onTap: _ensureTabLoaded,
          labelColor: const Color(0xFF2563EB),
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorColor: const Color(0xFF2563EB),
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          tabs: const [
            Tab(text: 'Gói thuê nút IoT'),
            Tab(text: 'Hợp đồng của tôi'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const BouncingScrollPhysics(),
        children: [
          // ── TAB 1: GÓI THUÊ NÚT IOT ──
          FutureBuilder<List<dynamic>>(
            future: _packages,
            builder: (context, snapshot) {
              if (_packages == null ||
                  snapshot.connectionState != ConnectionState.done) {
                return _buildPackagesLoadingPlaceholder(context);
              }

              if (snapshot.hasError) {
                final err = snapshot.error;
                final detail = err is ApiException
                    ? err.message
                    : 'Vui lòng kiểm tra kết nối mạng và thử lại.';
                return _buildTabError(
                  icon: LucideIcons.wifiOff,
                  title: 'Không thể tải danh sách gói thuê nút IoT.',
                  detail: detail,
                  onRetry: _reloadPackagesOnly,
                );
              }

              final packages = (snapshot.data ?? [])
                  .whereType<Map>()
                  .map((p) => Map<String, dynamic>.from(p))
                  .toList();

              if (packages.isEmpty) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            color: Color(0xFFEFF6FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            LucideIcons.cpu,
                            size: 36,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Chưa có gói thuê nút khả dụng',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Hệ thống đang cập nhật các gói nút bấm IoT mới.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _reloadPackagesOnly,
                          child: const Text('Tải lại'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _reloadPackagesOnly,
                color: const Color(0xFF2563EB),
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.all(16),
                  itemCount: packages.length,
                  itemBuilder: (context, index) {
                    final pkg = packages[index];
                    final name =
                        (pkg['packageName'] ??
                                pkg['name'] ??
                                'Gói nút thông minh')
                            .toString();
                    final rawDesc = pkg['description']?.toString().trim();
                    final desc = (rawDesc != null && rawDesc.isNotEmpty)
                        ? rawDesc
                        : 'Trải nghiệm đặt hàng một chạm ngay tại nhà';
                    final price = _parseNum(
                      pkg['monthlyPrice'] ??
                          pkg['monthlyFee'] ??
                          pkg['price'] ??
                          pkg['rentalPrice'],
                    );
                    final deposit = _parseNum(
                      pkg['depositFee'] ?? pkg['depositAmount'],
                    );
                    final count = _parseInt(
                      pkg['buttonQuantity'] ?? pkg['numberOfButtons'],
                      fallback: 1,
                    );
                    final packageCode =
                        pkg['packageCode']?.toString().trim() ?? '';

                    return StaggeredReveal(
                      index: index,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                runAlignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          LucideIcons.radio,
                                          size: 12,
                                          color: Color(0xFF2563EB),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$count Nút bấm IoT',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF2563EB),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'Bảo hành trọn đời',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF059669),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              if (packageCode.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Mã gói: $packageCode',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                desc,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  spacing: 12,
                                  runSpacing: 10,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Cước thuê hàng tháng',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${CurrencyFormatter.format(price)}/tháng',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF2563EB),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Tiền cọc (hoàn lại 100%)',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          deposit > 0
                                              ? CurrencyFormatter.format(
                                                  deposit,
                                                )
                                              : 'Miễn cọc',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              ElevatedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _openRentSheet(pkg),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 44),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  children: [
                                    Icon(LucideIcons.shoppingCart, size: 16),
                                    Text(
                                      'Thuê gói nút này',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),

          // ── TAB 2: HỢP ĐỒNG CỦA TÔI & TIỀN CỌC ──
          FutureBuilder<List<CustomerButtonContract>>(
            future: _contracts,
            builder: (context, snapshot) {
              if (_contracts == null ||
                  snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF2563EB),
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                final error = snapshot.error;
                final isForbidden =
                    error is ApiException && error.statusCode == 403;
                final isUnauthorized =
                    error is ApiException && error.statusCode == 401;
                final title = isForbidden
                    ? 'Tài khoản hiện tại chưa có hồ sơ khách hàng.'
                    : isUnauthorized
                    ? 'Phiên đăng nhập đã hết hạn.'
                    : 'Không thể tải thông tin nút và tiền cọc.';
                final detail = error is ApiException
                    ? error.message
                    : 'Vui lòng kiểm tra kết nối mạng và thử lại.';
                return _buildTabError(
                  icon: isForbidden
                      ? LucideIcons.userX
                      : LucideIcons.alertCircle,
                  title: title,
                  detail: detail,
                  onRetry: _reloadContractsOnly,
                  secondaryAction: OutlinedButton(
                    onPressed: () => _tabController.animateTo(0),
                    child: const Text('Xem gói thuê nút'),
                  ),
                );
              }
              final contracts = snapshot.data ?? [];
              return RefreshIndicator(
                onRefresh: _reloadContractsOnly,
                color: const Color(0xFF2563EB),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.all(16),
                  children: [
                    const ResidentNotice(
                      'Theo dõi nút và tiền cọc của bạn. Cửa hàng xác nhận nhận lại nút trước khi xử lý hoàn cọc.',
                    ),
                    if (contracts.isEmpty)
                      ResidentPanel(
                        child: Column(
                          children: [
                            const Text('Bạn chưa có hợp đồng thuê nút nào.'),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: () => _tabController.animateTo(0),
                              icon: const Icon(LucideIcons.plus, size: 16),
                              label: const Text('Xem các gói thuê nút ngay'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    for (final contract in contracts)
                      ResidentPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Text(
                                  'Hồ sơ ${contract.code}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                ResidentBadge(
                                  contract.statusLabel,
                                  success: contract.status == 'RETURNED',
                                  waiting:
                                      (contract.canOrder == false &&
                                          contract.status != 'RETURNED') ||
                                      contract.status == 'PENDING_PAYMENT' ||
                                      contract.status == 'PENDING_HANDOVER' ||
                                      contract.status == 'RETURN_REQUESTED',
                                ),
                              ],
                            ),
                            if (contract.packageName != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                contract.monthsRented != null
                                    ? '${contract.packageName} • ${contract.monthsRented} tháng'
                                    : contract.packageName!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                            for (final button in contract.buttons) ...[
                              const SizedBox(height: 12),
                              Builder(
                                builder: (context) {
                                  final isPendingReturn =
                                      _pendingReturns.contains(
                                        '${contract.id}:${button.id}',
                                      ) ||
                                      contract.pendingReturnButtonIds.contains(
                                        button.id,
                                      );
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: const ResidentIcon(
                                          Icons.smart_button_outlined,
                                        ),
                                        title: Text(
                                          button.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        subtitle: isPendingReturn
                                            ? const Text(
                                                'Đã gửi yêu cầu — chờ cửa hàng nhận lại',
                                              )
                                            : null,
                                      ),
                                      if (contract.canRequestReturn)
                                        OutlinedButton(
                                          onPressed: _busy || isPendingReturn
                                              ? null
                                              : () => _requestReturn(
                                                  contract,
                                                  button,
                                                ),
                                          child: const Text('Yêu cầu trả nút'),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                            const Divider(height: 24),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                const Text('Tiền cọc theo hồ sơ'),
                                Text(
                                  CurrencyFormatter.format(
                                    contract.depositAmount,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                              ],
                            ),
                            if (contract.status == 'PENDING_PAYMENT') ...[
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _payDeposit(contract),
                                icon: const Icon(
                                  LucideIcons.creditCard,
                                  size: 16,
                                ),
                                label: const Text('Thanh toán tiền cọc'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 44),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ],
                            if (contract.status == 'PENDING_HANDOVER' &&
                                contract.buttons.isEmpty) ...[
                              const SizedBox(height: 12),
                              const ResidentNotice(
                                'Đã tiếp nhận tiền cọc. Cửa hàng đang chuẩn bị và bàn giao nút bấm IoT cho bạn.',
                              ),
                            ],
                            if (contract.canOrder == false &&
                                contract.status == 'ACTIVE') ...[
                              const SizedBox(height: 12),
                              const ResidentNotice(
                                'Nút đang tạm ngừng sử dụng. Vui lòng liên hệ cửa hàng.',
                              ),
                            ],
                            if (contract.status == 'RETURNED') ...[
                              const SizedBox(height: 12),
                              const ResidentNotice(
                                'Cửa hàng đã nhận lại nút. Khoản hoàn cọc sẽ được chuyển về tài khoản ngân hàng đã xác minh sau khi được duyệt.',
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
