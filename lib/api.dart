import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class ApiException implements Exception {
  const ApiException(
    this.message,
    this.statusCode, {
    this.isApplicationError = false,
    this.uncertain = false,
  });
  final String message;
  final int statusCode;
  final bool isApplicationError;
  final bool uncertain;
  @override
  String toString() => message;
}

class ReconciledOperation extends ApiException {
  const ReconciledOperation({required this.previousCommitted})
    : super(
        previousCommitted
            ? 'Your earlier change was saved. Refresh and review it before adding another.'
            : 'The interrupted request was cancelled. Submit your intended change again.',
        409,
      );
  final bool previousCommitted;
}

const driverUploadLimit = 5 * 1024 * 1024;
String? driverFileType(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255) {
    return 'image/jpeg';
  }
  const png = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length >= 8 &&
      List.generate(8, (i) => bytes[i] == png[i]).every((v) => v)) {
    return 'image/png';
  }
  if (bytes.length >= 5 &&
      ascii.decode(bytes.take(5).toList(), allowInvalid: true) == '%PDF-') {
    return 'application/pdf';
  }
  return null;
}

/// The same raw-body contract used by UniT7's authenticated driver Worker.
class DriverApi {
  DriverApi(
    this.baseUrl,
    this.token, {
    http.Client? client,
    this.timeout = const Duration(seconds: 25),
  }) : _client = client;
  final String baseUrl, token;
  final http.Client? _client;
  final Duration timeout;

  Uri _url(String path) {
    final base = Uri.tryParse(baseUrl);
    if (base == null ||
        !base.hasAuthority ||
        base.userInfo.isNotEmpty ||
        (base.scheme != 'https' &&
            !(kDebugMode &&
                base.scheme == 'http' &&
                ['127.0.0.1', 'localhost'].contains(base.host)))) {
      throw const ApiException(
        'The driver service is not configured correctly.',
        0,
      );
    }
    return Uri.parse('${baseUrl.replaceFirst(RegExp(r'/$'), '')}$path');
  }

  Future<http.Response> _send(
    http.Request request, {
    Duration? deadline,
  }) async {
    final client = _client ?? http.Client();
    try {
      return await (() async {
        final stream = await client.send(request);
        // JSON responses are bounded by the paginated contract. Uploads return JSON too.
        final chunks = <int>[];
        await for (final chunk in stream.stream) {
          if (chunks.length + chunk.length > 2 * 1024 * 1024) {
            throw const ApiException(
              'The response was too large to confirm. Refresh before retrying.',
              0,
              uncertain: true,
            );
          }
          chunks.addAll(chunk);
        }
        return http.Response.bytes(
          chunks,
          stream.statusCode,
          headers: stream.headers,
        );
      })().timeout(deadline ?? timeout);
    } on TimeoutException {
      throw const ApiException(
        'The response could not be confirmed. Check your connection and retry the same action.',
        0,
        uncertain: true,
      );
    } on http.ClientException {
      throw const ApiException(
        'Unable to connect. Retry the same action when you are online.',
        0,
        uncertain: true,
      );
    } on SocketException {
      throw const ApiException(
        'Unable to connect. Retry the same action when you are online.',
        0,
        uncertain: true,
      );
    } finally {
      if (_client == null) client.close();
    }
  }

  dynamic _decode(http.Response response, {required bool mutation}) {
    dynamic payload;
    try {
      payload = jsonDecode(response.body);
    } catch (_) {
      throw ApiException(
        'The service response could not be confirmed. Refresh before retrying.',
        response.statusCode,
        uncertain:
            mutation &&
            (response.statusCode < 400 ||
                response.statusCode >= 500 ||
                response.statusCode == 429),
      );
    }
    if (response.statusCode >= 400 ||
        payload is Map && payload['success'] == false) {
      final error = payload is Map ? payload['error'] : null;
      final message = error is Map
          ? error['message']
          : payload is Map
          ? payload['message']
          : null;
      throw ApiException(
        message is String ? message : 'The request could not be completed.',
        response.statusCode,
        isApplicationError: error is Map && message is String,
        uncertain:
            mutation &&
            (response.statusCode >= 500 || response.statusCode == 429),
      );
    }
    return payload is Map ? payload['data'] ?? payload : payload;
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final request = http.Request(method, _url(path));
    request.headers.addAll({
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      ...?headers,
    });
    if (body != null) request.body = jsonEncode(body);
    return _decode(await _send(request), mutation: method != 'GET');
  }

  Future<void> upload(
    String path,
    String filePath, {
    String? requestKey,
    String? expiresOn,
  }) async {
    final file = File(filePath);
    final length = await file.length();
    if (length < 1 || length > driverUploadLimit) {
      throw const ApiException('Choose a file up to 5 MB.', 400);
    }
    final bytes = await file.readAsBytes();
    final mime = driverFileType(bytes);
    if (mime == null ||
        (path.endsWith('/selfie') && mime == 'application/pdf')) {
      throw const ApiException(
        'Choose a JPG or PNG photo. Documents can also be PDF files.',
        400,
      );
    }
    final name = filePath.replaceAll('\\', '/').split('/').last;
    if (name.isEmpty || name.length > 180) {
      throw const ApiException('Choose a shorter filename.', 400);
    }
    final request = http.Request('POST', _url(path));
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Content-Type': mime,
      'X-Filename': Uri.encodeComponent(name),
      if (requestKey != null) 'Idempotency-Key': requestKey,
      if (expiresOn != null) 'X-Expires-On': expiresOn,
    });
    request.bodyBytes = bytes;
    _decode(
      await _send(request, deadline: const Duration(seconds: 50)),
      mutation: true,
    );
  }
}
