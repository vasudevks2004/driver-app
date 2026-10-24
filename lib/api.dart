import 'dart:convert';
import 'package:http/http.dart' as http;

/// Driver-scoped API adapter. Routes are provisional pending backend integration.
class ApiException implements Exception {
  ApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;
  @override
  String toString() => message;
}

class DriverApi {
  DriverApi(this.baseUrl, this.token);
  final String baseUrl;
  final String token;

  Future<dynamic> request(String path,
      {String method = 'GET', Map<String, dynamic>? body, Map<String,String>? headers}) async {
    if (baseUrl.isEmpty) throw StateError('API URL is not configured');
    final req = http.Request(method, Uri.parse('$baseUrl$path'));
    req.headers.addAll({
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      ...?headers,
    });
    if (body != null) req.body = jsonEncode(body);
    final http.Response res;
    try { res = await http.Response.fromStream(await req.send()); }
    catch (_) { throw StateError('Could not reach HireD. Check internet and server configuration.'); }
    dynamic payload;
    try {
      payload = jsonDecode(res.body);
    } catch (_) {
      throw StateError('Server returned an invalid response');
    }
    if (res.statusCode >= 400 ||
        (payload is Map && payload['success'] == false)) {
      final error = payload is Map ? payload['error'] : null;
      throw ApiException(error is Map
          ? (error['message']?.toString() ?? 'Request failed')
          : (payload is Map
              ? (payload['message']?.toString() ?? 'Request failed')
              : 'Request failed'), res.statusCode);
    }
    return payload is Map ? (payload['data'] ?? payload) : payload;
  }

  Future<void> upload(String path, String filePath) async {
    if (baseUrl.isEmpty) throw StateError('API URL is not configured');
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
    req.headers['Authorization'] = 'Bearer $token';
    req.files.add(await http.MultipartFile.fromPath('file', filePath));
    final res = await http.Response.fromStream(await req.send());
    if (res.statusCode >= 400) throw ApiException('Upload failed (${res.statusCode})', res.statusCode);
  }
}
