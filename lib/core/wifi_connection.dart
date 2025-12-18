import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class WifiConnectionState {
  final bool isConnecting;
  final bool isConnected;
  final String? error;
  final List<String> rxLog;

  const WifiConnectionState({
    required this.isConnecting,
    required this.isConnected,
    required this.error,
    required this.rxLog,
  });

  factory WifiConnectionState.initial() => const WifiConnectionState(
        isConnecting: false,
        isConnected: false,
        error: null,
        rxLog: <String>[],
      );

  WifiConnectionState copyWith({
    bool? isConnecting,
    bool? isConnected,
    String? error,
    List<String>? rxLog,
  }) {
    return WifiConnectionState(
      isConnecting: isConnecting ?? this.isConnecting,
      isConnected: isConnected ?? this.isConnected,
      error: error,
      rxLog: rxLog ?? this.rxLog,
    );
  }
}

final wifiConnectionProvider =
    StateNotifierProvider<WifiConnectionNotifier, WifiConnectionState>(
  (ref) => WifiConnectionNotifier(),
);

class WifiConnectionNotifier extends StateNotifier<WifiConnectionState> {
  WifiConnectionNotifier() : super(WifiConnectionState.initial());

  static const String _host = "192.168.4.1";
  static const int _port = 81;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  Completer<void>? _pongWaiter;

  Uri get _pingUri => Uri.parse("http://$_host:$_port/ping");
  Uri get _wsUri => Uri.parse("ws://$_host:$_port/ws");

  void _log(String line) {
    final next = List<String>.from(state.rxLog);
    next.add(line);
    if (next.length > 200) next.removeRange(0, next.length - 200);
    state = state.copyWith(rxLog: next);
  }

  Future<bool> _ping() async {
    try {
      _log("→ GET $_pingUri");
      final r = await http.get(_pingUri).timeout(const Duration(seconds: 2));
      _log("← /ping ${r.statusCode}: ${r.body}");
      return r.statusCode == 200 && r.body.toUpperCase().contains("OK");
    } catch (e) {
      _log("× /ping error: $e");
      return false;
    }
  }

  Future<void> connect() async {
    if (state.isConnecting || state.isConnected) return;

    state = state.copyWith(isConnecting: true, error: null);
    _log("=== CONNECT START ===");

    final ok = await _ping();
    if (!ok) {
      state = state.copyWith(
        isConnecting: false,
        isConnected: false,
        error:
            "Не вижу робота по Wi-Fi. Проверь что iPhone/Android подключён к сети Robot и открой /ping.",
      );
      _log("=== CONNECT FAIL: ping ===");
      return;
    }

    try {
      _log("→ WS connect $_wsUri");
      final ch = WebSocketChannel.connect(_wsUri);
      // важно: дождаться готовности (если сервер недоступен — тут упадёт)
      await ch.ready.timeout(const Duration(seconds: 3));

      _channel = ch;

      _sub?.cancel();
      _sub = ch.stream.listen(
        (msg) {
          _log("← $msg");
          if (msg.toString().trim().toUpperCase() == "PONG") {
            _pongWaiter?.complete();
            _pongWaiter = null;
          }
        },
        onError: (e) {
          _log("× WS error: $e");
          disconnect(error: "WebSocket ошибка: $e");
        },
        onDone: () {
          _log("× WS closed");
          disconnect(error: "WebSocket закрыт");
        },
      );

      // финальная проверка: PING/PONG
      _pongWaiter = Completer<void>();
      sendRaw("PING");

      await _pongWaiter!.future.timeout(const Duration(seconds: 2));
      state =
          state.copyWith(isConnecting: false, isConnected: true, error: null);
      _log("=== CONNECT OK ===");
    } catch (e) {
      _log("=== CONNECT FAIL: $e ===");
      await disconnect(error: "Не удалось подключиться по WebSocket: $e");
    }
  }

  Future<void> disconnect({String? error}) async {
    state =
        state.copyWith(isConnecting: false, isConnected: false, error: error);

    _pongWaiter = null;

    await _sub?.cancel();
    _sub = null;

    try {
      _channel?.sink.close();
    } catch (_) {}

    _channel = null;
    _log("=== DISCONNECTED ===");
  }

  void sendRaw(String text) {
    final ch = _channel;
    if (ch == null) return;
    _log("→ $text");
    ch.sink.add(text);
  }

  /// left/right: -100..100
  void sendMove(int left, int right) {
    if (!state.isConnected) return;
    left = left.clamp(-100, 100);
    right = right.clamp(-100, 100);
    sendRaw("M,$left,$right");
  }

  void sendStop() {
    if (!state.isConnected) return;
    sendRaw("STOP");
  }

  void clearLog() {
    state = state.copyWith(rxLog: []);
  }
}
