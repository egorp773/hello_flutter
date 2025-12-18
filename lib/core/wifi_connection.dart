import 'dart:async';

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
      final r = await http.get(_pingUri).timeout(const Duration(seconds: 5));
      _log("← /ping ${r.statusCode}: ${r.body}");
      final success =
          r.statusCode == 200 && r.body.toUpperCase().contains("OK");
      if (!success) {
        _log("× /ping failed: status=${r.statusCode}, body=${r.body}");
      }
      return success;
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

      // На iOS ready может не работать, поэтому используем другой подход
      // Устанавливаем канал сразу и слушаем stream
      _channel = ch;

      // Создаем completer для отслеживания успешного подключения
      final connectionCompleter = Completer<bool>();
      bool connectionEstablished = false;

      _sub?.cancel();
      _sub = ch.stream.listen(
        (msg) {
          if (!connectionEstablished) {
            connectionEstablished = true;
            if (!connectionCompleter.isCompleted) {
              connectionCompleter.complete(true);
            }
            _log("✓ WS connected (first message received)");
          }

          final msgStr = msg.toString().trim();
          _log("← $msgStr");
          final upperMsg = msgStr.toUpperCase();
          if (upperMsg == "PONG" || upperMsg.startsWith("PONG")) {
            _log("✓ PONG received");
            _pongWaiter?.complete();
            _pongWaiter = null;
          }
        },
        onError: (e) {
          _log("× WS stream error: $e");
          if (!connectionCompleter.isCompleted) {
            connectionCompleter.complete(false);
          }
          disconnect(error: "WebSocket ошибка: $e");
        },
        onDone: () {
          _log("× WS stream closed");
          if (!connectionCompleter.isCompleted) {
            connectionCompleter.complete(false);
          }
          disconnect(error: "WebSocket закрыт");
        },
        cancelOnError: false,
      );

      // Ждем либо первого сообщения, либо ошибки (максимум 10 секунд)
      try {
        final connected = await connectionCompleter.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            _log("× Connection timeout waiting for first message");
            return false;
          },
        );

        if (!connected) {
          await disconnect(error: "Не удалось установить WebSocket соединение");
          return;
        }

        // Даем немного времени на установку соединения
        await Future.delayed(const Duration(milliseconds: 500));

        // финальная проверка: PING/PONG
        _log("→ Sending PING for handshake");
        _pongWaiter = Completer<void>();
        sendRaw("PING");

        try {
          await _pongWaiter!.future.timeout(const Duration(seconds: 5));
          state = state.copyWith(
              isConnecting: false, isConnected: true, error: null);
          _log("=== CONNECT OK ===");
        } catch (timeout) {
          _log("× PONG timeout");
          await disconnect(
              error: "Робот не ответил на PING. Проверь подключение.");
        }
      } catch (e) {
        _log("=== CONNECT FAIL: $e ===");
        await disconnect(error: "Не удалось подключиться по WebSocket: $e");
      }
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
    if (ch == null) {
      _log("× sendRaw failed: channel is null");
      return;
    }
    try {
      _log("→ $text");
      ch.sink.add(text);
    } catch (e) {
      _log("× sendRaw error: $e");
      disconnect(error: "Ошибка отправки: $e");
    }
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
