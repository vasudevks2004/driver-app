import 'dart:async';
import 'dart:convert';
import 'package:realtime_client/realtime_client.dart';
import '../auth_config.dart';

abstract class AssignmentFeed {
  Future<void> connect(
    String token,
    void Function() changed,
    void Function(bool) connected,
  );
  Future<void> updateToken(String token);
  Future<void> stop();
}

/// Notifications contain no duty, contact or identity data. Always re-read the
/// authorised API after a notification or reconnect; notifications are hints.
class SupabaseAssignmentFeed implements AssignmentFeed {
  SupabaseAssignmentFeed(this.config);
  final DriverAuthConfig config;
  RealtimeClient? _client;
  int _generation = 0;

  static String? subject(String token) {
    try {
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
      );
      final id = claims['sub'];
      return id is String && RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)
          ? id
          : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> connect(
    String token,
    void Function() changed,
    void Function(bool) connected,
  ) async {
    final generation = ++_generation;
    final previous = _client;
    _client = null;
    if (previous != null) await _close(previous);
    if (generation != _generation) return;
    if (!config.isConfigured) return;
    final id = subject(token);
    if (id == null) {
      connected(false);
      return;
    }
    final origin = Uri.parse(config.supabaseUrl);
    if (origin.scheme != 'https') {
      connected(false);
      return;
    }
    final client = RealtimeClient(
      origin
          .replace(
            scheme: 'wss',
            path: '/realtime/v1',
            query: null,
            fragment: null,
          )
          .toString(),
      params: {'apikey': config.publishableKey},
      timeout: const Duration(seconds: 10),
      disconnectOnEmptyChannelsAfter: Duration.zero,
    );
    _client = client;
    try {
      await client.setAuth(token);
      if (generation != _generation) return;
      client
          .channel(
            'driver-assignments:$id',
            const RealtimeChannelConfig(private: true),
          )
          .onBroadcast(
            event: 'changed',
            callback: (_) {
              if (generation == _generation) changed();
            },
          )
          .subscribe((status, error) {
            if (generation != _generation) return;
            final ready = status == RealtimeSubscribeStatus.subscribed;
            connected(ready);
            if (ready) changed(); // Recover changes missed while disconnected.
          });
    } catch (_) {
      if (generation == _generation) connected(false);
    }
  }

  @override
  Future<void> updateToken(String token) async {
    try {
      await _client?.setAuth(token);
    } catch (_) {
      /* API polling remains available. */
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    final client = _client;
    _client = null;
    if (client != null) await _close(client);
  }

  Future<void> _close(RealtimeClient client) async {
    try {
      await client.removeAllChannels();
    } catch (_) {
      try {
        await client.disconnect();
      } catch (_) {}
    }
  }
}
