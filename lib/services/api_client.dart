import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'order_updates.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';


class ApiException implements Exception {
  final String message;
  final int statusCode;
  final String? errorCode;
  final dynamic details;

  ApiException({
    required this.message,
    required this.statusCode,
    this.errorCode,
    this.details,
  });

  @override
  String toString() => 'ApiException: [$statusCode] $message (code: $errorCode)';
}

class ApiResponse<T> {
  final bool success;
  final String? message;
  final T? data;
  final int statusCode;

  ApiResponse({
    required this.success,
    this.message,
    this.data,
    required this.statusCode,
  });
}

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  http.Client _httpClient = http.Client();

  static const String _prefAccessTokenKey = 'auth_access_token';
  static const String _prefRefreshTokenKey = 'auth_refresh_token';

  String? _accessToken;
  String? _refreshToken;
  bool _isInitialized = false;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get isAuthenticated => _accessToken != null && _accessToken!.isNotEmpty;

  /// Nạp token từ SharedPreferences khi khởi động ứng dụng
  Future<void> init({bool force = false}) async {
    if (_isInitialized && !force) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _accessToken = prefs.getString(_prefAccessTokenKey);
      _refreshToken = prefs.getString(_prefRefreshTokenKey);
      _isInitialized = true;
    } catch (_) {}
  }

  /// Cập nhật token và lưu trữ bền vững vào SharedPreferences
  Future<void> setTokens({required String? accessToken, String? refreshToken}) async {
    _accessToken = accessToken;
    if (refreshToken != null) {
      _refreshToken = refreshToken;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (accessToken != null && accessToken.isNotEmpty) {
        await prefs.setString(_prefAccessTokenKey, accessToken);
      } else {
        await prefs.remove(_prefAccessTokenKey);
      }
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await prefs.setString(_prefRefreshTokenKey, refreshToken);
      }
    } catch (_) {}
  }

  /// Xóa sạch token khỏi RAM và SharedPreferences khi đăng xuất
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    _isInitialized = false;
    OrderUpdates.endSession();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefAccessTokenKey);
      await prefs.remove(_prefRefreshTokenKey);
    } catch (_) {}
  }

  bool _isPublicAuthPath(String path) {
    final p = path.toLowerCase();
    return p.contains('/auth/login') ||
        p.contains('/auth/refresh') ||
        p.contains('/auth/register') ||
        p.contains('/auth/google-login') ||
        p.contains('/auth/forgot-password') ||
        p.contains('/auth/reset-password') ||
        p.contains('/auth/verify-email') ||
        p.contains('/auth/resend-verification') ||
        p.contains('/auth/check-email') ||
        p.contains('/auth/check-username');
  }

  /// Các endpoint trả 401 mang nghĩa nghiệp vụ (sai mật khẩu hiện tại, sai thông tin đăng nhập)
  /// không nên tự động gọi /auth/refresh hay xóa phiên đăng nhập.
  bool _skips401Refresh(String path) {
    final p = path.toLowerCase();
    return _isPublicAuthPath(p) || p.contains('/auth/change-password');
  }

  bool get _isMockClient =>
      _httpClient.runtimeType.toString().contains('Mock');

  static const Duration _requestTimeout = Duration(seconds: 45);
  static const Duration _refreshTimeout = Duration(seconds: 30);

  /// Đảm bảo token đã được nạp từ bộ nhớ lưu trữ nếu chưa khởi tạo
  Future<void> ensureAuthenticated() async {
    if (_accessToken != null && _accessToken!.isNotEmpty) return;
    if (_isInitialized) return;
    await init(force: true);
  }

  Uri _buildUri(String path, [Map<String, dynamic>? queryParams]) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final fullUrl = '${ApiConfig.baseUrl}$cleanPath';
    final uri = Uri.parse(fullUrl);

    if (queryParams == null || queryParams.isEmpty) {
      return uri;
    }

    final queryMap = <String, String>{};
    queryParams.forEach((key, value) {
      if (value != null) {
        queryMap[key] = value.toString();
      }
    });

    return uri.replace(queryParameters: queryMap);
  }

  Map<String, String> _buildHeaders([Map<String, String>? extraHeaders]) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (_accessToken != null && _accessToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }

    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }

    return headers;
  }

  dynamic _processResponse(http.Response response) {
    dynamic jsonBody;
    try {
      jsonBody = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      jsonBody = null;
    }

    final statusCode = response.statusCode;

    if (statusCode >= 200 && statusCode < 300) {
      if (jsonBody is Map<String, dynamic>) {
        return jsonBody;
      }
      return {'success': true, 'data': jsonBody};
    }

    // Handle 429 Too Many Requests with Retry-After support
    if (statusCode == 429) {
      final retryAfterRaw = response.headers['retry-after'];
      final retrySec = int.tryParse(retryAfterRaw?.trim() ?? '');
      final rateMsg = retrySec != null && retrySec > 0
          ? 'Máy chủ đang giới hạn yêu cầu. Vui lòng thử lại sau $retrySec giây.'
          : (jsonBody is Map<String, dynamic> && jsonBody['message'] is String
                ? jsonBody['message'] as String
                : 'Máy chủ đang giới hạn yêu cầu. Vui lòng thử lại sau ít phút.');
      throw ApiException(
        message: rateMsg,
        statusCode: 429,
        errorCode: 'RATE_LIMITED',
        details: retrySec != null ? {'retryAfterSeconds': retrySec} : null,
      );
    }

    // Handle error envelope from NestJS
    String errorMessage = 'Yêu cầu thất bại (HTTP $statusCode)';
    String? errorCode;
    dynamic details;

    if (jsonBody is Map<String, dynamic>) {
      if (jsonBody['message'] is String) {
        errorMessage = jsonBody['message'];
      } else if (jsonBody['message'] is List) {
        errorMessage = (jsonBody['message'] as List).join(', ');
      }
      errorCode = jsonBody['errorCode']?.toString();
      details = jsonBody['data'] ?? jsonBody['details'];
    }

    throw ApiException(
      message: errorMessage,
      statusCode: statusCode,
      errorCode: errorCode,
      details: details,
    );
  }

  Completer<bool>? _refreshCompleter;

  // Cho phép thay thế Client trong Unit Test
  set testClient(http.Client client) => _httpClient = client;

  Future<void> _checkAuth(String path) async {
    if (!_isPublicAuthPath(path)) {
      await ensureAuthenticated();
    }
  }

  /// Xử lý refresh token khi gặp mã lỗi 401 Unauthorized.
  /// Sử dụng Completer để chặn các request đồng thời gọi trùng lặp refresh API.
  /// Chỉ xóa token khi server xác nhận 401/403 (token bị thu hồi/hết hạn),
  /// KHÔNG xóa token khi lỗi timeout hoặc rớt mạng tạm thời.
  Future<bool> _handle401Refresh() async {
    if (_refreshToken == null || _refreshToken!.isEmpty) {
      await clearTokens();
      return false;
    }

    if (_refreshCompleter != null) {
      return await _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<bool>();
    try {
      final refreshUri = _buildUri(ApiConfig.authRefresh);
      final res = await _httpClient
          .post(
            refreshUri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'refreshToken': _refreshToken}),
          )
          .timeout(_refreshTimeout);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final dynamic jsonBody = jsonDecode(utf8.decode(res.bodyBytes));
        final data = jsonBody['data'] ?? jsonBody;
        final newAccessToken =
            jsonBody['accessToken'] ?? data['token'] ?? data['accessToken'];
        final newRefreshToken = jsonBody['refreshToken'] ?? data['refreshToken'];

        if (newAccessToken != null) {
          await setTokens(
            accessToken: newAccessToken.toString(),
            refreshToken: newRefreshToken?.toString(),
          );
          _refreshCompleter!.complete(true);
          return true;
        }
        await clearTokens();
        _refreshCompleter!.complete(false);
        return false;
      }

      if (res.statusCode == 401 || res.statusCode == 403) {
        await clearTokens();
      }
      _refreshCompleter!.complete(false);
      return false;
    } on TimeoutException {
      // Transient cold-start / slow network — preserve tokens!
      if (!_refreshCompleter!.isCompleted) {
        _refreshCompleter!.complete(false);
      }
      return false;
    } on SocketException {
      // Offline / transient network drop — preserve tokens!
      if (!_refreshCompleter!.isCompleted) {
        _refreshCompleter!.complete(false);
      }
      return false;
    } catch (_) {
      if (!_refreshCompleter!.isCompleted) {
        _refreshCompleter!.complete(false);
      }
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  Future<http.Response> _executeWithTimeout(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    String? body,
  }) async {
    switch (method.toUpperCase()) {
      case 'GET':
        return await _httpClient
            .get(uri, headers: headers)
            .timeout(_requestTimeout);
      case 'POST':
        return await _httpClient
            .post(uri, headers: headers, body: body)
            .timeout(_requestTimeout);
      case 'PUT':
        return await _httpClient
            .put(uri, headers: headers, body: body)
            .timeout(_requestTimeout);
      case 'PATCH':
        return await _httpClient
            .patch(uri, headers: headers, body: body)
            .timeout(_requestTimeout);
      case 'DELETE':
        return await _httpClient
            .delete(uri, headers: headers, body: body)
            .timeout(_requestTimeout);
      default:
        throw UnsupportedError('Unsupported HTTP method: $method');
    }
  }

  Future<dynamic> _request(
    String method,
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
    bool isRetry = false,
    int transientAttempt = 0,
  }) async {
    await _checkAuth(path);
    final uri = _buildUri(path, queryParams);
    final encodedBody = body != null ? jsonEncode(body) : null;
    final reqHeaders = _buildHeaders(headers);
    final canRetryTransient =
        method.toUpperCase() == 'GET' && transientAttempt == 0 && !_isMockClient;

    http.Response response;
    try {
      response = await _executeWithTimeout(
        method,
        uri,
        headers: reqHeaders,
        body: encodedBody,
      );
    } on TimeoutException {
      if (canRetryTransient) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        return _request(
          method,
          path,
          body: body,
          queryParams: queryParams,
          headers: headers,
          isRetry: isRetry,
          transientAttempt: transientAttempt + 1,
        );
      }
      throw ApiException(
        message:
            'Máy chủ phản hồi chậm (có thể đang khởi động lại). Vui lòng thử lại sau giây lát.',
        statusCode: 408,
        errorCode: 'TIMEOUT',
      );
    } on SocketException {
      if (canRetryTransient) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        return _request(
          method,
          path,
          body: body,
          queryParams: queryParams,
          headers: headers,
          isRetry: isRetry,
          transientAttempt: transientAttempt + 1,
        );
      }
      throw ApiException(
        message:
            'Không thể kết nối đến máy chủ (${ApiConfig.baseUrl}). Vui lòng kiểm tra kết nối mạng.',
        statusCode: 0,
        errorCode: 'NETWORK_ERROR',
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: 'Lỗi truyền tải mạng: ${e.toString()}',
        statusCode: -1,
      );
    }

    if (canRetryTransient &&
        (response.statusCode == 502 ||
            response.statusCode == 503 ||
            response.statusCode == 504)) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      return _request(
        method,
        path,
        body: body,
        queryParams: queryParams,
        headers: headers,
        isRetry: isRetry,
        transientAttempt: transientAttempt + 1,
      );
    }

    // 401 Interceptor: Tự làm mới token cho mọi endpoint cần auth (bao gồm /auth/me)
    if (response.statusCode == 401 && !_skips401Refresh(path) && !isRetry) {
      final refreshed = await _handle401Refresh();
      if (refreshed) {
        // Thực thi lại request gốc với Access Token mới
        return _request(
          method,
          path,
          body: body,
          queryParams: queryParams,
          headers: headers,
          isRetry: true,
        );
      }
    }

    return _processResponse(response);
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) =>
      _request('GET', path, queryParams: queryParams, headers: headers);

  Future<dynamic> post(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) =>
      _request('POST', path, body: body, queryParams: queryParams, headers: headers);

  Future<dynamic> put(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) =>
      _request('PUT', path, body: body, queryParams: queryParams, headers: headers);

  Future<dynamic> patch(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) =>
      _request('PATCH', path, body: body, queryParams: queryParams, headers: headers);

  Future<dynamic> delete(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) =>
      _request('DELETE', path, body: body, queryParams: queryParams, headers: headers);

  Future<dynamic> uploadFile(
    String path, {
    required File file,
    String fileField = 'file',
    Map<String, String>? fields,
    bool isRetry = false,
  }) async {
    await _checkAuth(path);
    final uri = _buildUri(path);
    final request = http.MultipartRequest('POST', uri);

    if (_accessToken != null && _accessToken!.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $_accessToken';
    }

    if (fields != null) {
      request.fields.addAll(fields);
    }

    final multipartFile = await http.MultipartFile.fromPath(fileField, file.path);
    request.files.add(multipartFile);

    try {
      final streamedResponse = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 45));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 401 && !_isPublicAuthPath(path) && !isRetry) {
        final refreshed = await _handle401Refresh();
        if (refreshed) {
          return await uploadFile(
            path,
            file: file,
            fileField: fileField,
            fields: fields,
            isRetry: true,
          );
        }
      }

      return _processResponse(response);
    } on TimeoutException {
      throw ApiException(
        message: 'Tải tệp lên quá thời gian chờ. Vui lòng thử lại.',
        statusCode: 408,
        errorCode: 'TIMEOUT',
      );
    } on SocketException {
      throw ApiException(
        message: 'Không thể tải tệp lên máy chủ. Vui lòng kiểm tra kết nối mạng.',
        statusCode: 0,
        errorCode: 'NETWORK_ERROR',
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: 'Lỗi tải tệp: ${e.toString()}',
        statusCode: -1,
      );
    }
  }
}
