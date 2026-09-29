import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A request the server turned down, or one that never reached it.
class ApiError implements Exception {
  final int code;
  final String message;
  ApiError(this.code, this.message);

  @override
  String toString() => message;
}

/// Talks to /api/admin. Every response is {code, message, data}; code 0 is
/// success and anything else is an error whose message is shown to the user.
class Api {
  String server;
  String? token;

  /// Shows an error to the user, like the web console's toast.
  void Function(String message)? onError;

  /// The server no longer accepts our token.
  void Function()? onSignedOut;

  final http.Client _client = http.Client();

  Api(this.server);

  String get base => '$server/api/admin';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept-Language': 'en',
        if (token != null && token!.isNotEmpty) 'api-token': token!,
      };

  Uri uri(String path, [Map<String, dynamic>? params]) {
    final q = <String, dynamic>{};
    params?.forEach((k, v) {
      if (v == null) return;
      if (v is String && v.isEmpty) return;
      q[k] = v is List ? v.map((e) => '$e').toList() : '$v';
    });
    final u = Uri.parse('$base$path');
    return q.isEmpty ? u : u.replace(queryParameters: q);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? params, bool quiet = false, Duration? timeout}) =>
      _send(() => _client.get(uri(path, params), headers: _headers), quiet, timeout);

  Future<dynamic> post(String path, {Object? body, bool quiet = false, Duration? timeout}) =>
      _send(() => _client.post(uri(path), headers: _headers, body: jsonEncode(body ?? {})), quiet, timeout);

  /// Fetches a file from the server outside the API, such as the API reference.
  Future<String> fetchText(String url) async {
    final res = await _client.get(Uri.parse(url.startsWith('http') ? url : '$server$url'));
    if (res.statusCode != 200) throw ApiError(res.statusCode, 'HTTP ${res.statusCode}');
    return utf8.decode(res.bodyBytes);
  }

  Future<dynamic> _send(Future<http.Response> Function() request, bool quiet, Duration? timeout) async {
    http.Response res;
    try {
      res = await request().timeout(timeout ?? const Duration(seconds: 50));
    } on TimeoutException {
      return _fail(ApiError(-1, 'Connection Time Out!'), quiet);
    } catch (e) {
      return _fail(ApiError(-1, 'Can\'t reach the server: $e'), quiet);
    }
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return _fail(ApiError(res.statusCode, 'HTTP ${res.statusCode}'), quiet);
    }
    // the login options endpoint answers with a bare list
    if (body is List) return body;
    if (body is! Map) return _fail(ApiError(res.statusCode, 'Unexpected response'), quiet);
    if (!body.containsKey('code')) {
      // disabled accounts and bad API keys come back as {"error": ...}
      if (res.statusCode == 401) onSignedOut?.call();
      return _fail(ApiError(res.statusCode, '${body['error'] ?? 'HTTP ${res.statusCode}'}'), quiet);
    }
    final code = (body['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      final err = ApiError(code, '${body['message'] ?? 'error'}');
      if (code == 403) _checkStillSignedIn();
      return _fail(err, quiet);
    }
    return body['data'];
  }

  Never _fail(ApiError e, bool quiet) {
    if (!quiet) onError?.call(e.message);
    throw e;
  }

  // 403 means either "sign in first" or "your role can't do that"; only the
  // first should sign the user out
  bool _checking = false;
  Future<void> _checkStillSignedIn() async {
    if (_checking || token == null) return;
    _checking = true;
    try {
      final res = await _client.get(uri('/user/current'), headers: _headers);
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode == 401 || (body is Map && body['code'] == 403)) onSignedOut?.call();
    } catch (_) {
      // offline: leave the session alone
    } finally {
      _checking = false;
    }
  }
}

/// A page of results from a /list endpoint.
class PageResult {
  final List<Map<String, dynamic>> list;
  final int total;
  PageResult(this.list, this.total);

  factory PageResult.from(dynamic data) {
    final raw = (data is Map ? data['list'] : null) as List? ?? const [];
    return PageResult(
      raw.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      (data is Map ? (data['total'] as num?)?.toInt() : null) ?? raw.length,
    );
  }
}
