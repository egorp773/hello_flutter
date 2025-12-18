import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WifiConnectionState {
  final bool isWifi;
  final bool isConnecting;
  final bool isConnected;
  final String? error;
  final List<String> rxLog;

  const WifiConnectionState({
    required this.isWifi,
    required this.isConnecting,
    required this.isConnected,
    this.error,
    this.rxLog = const [],
  });

  WifiConnectionState copyWith({
    bool? isWifi,
    bool? isConnecting,
    bool? isConnected,
    String? error,
    List<String>? rxLog,
  }) {
    return WifiConnectionState(
      isWifi: isWifi ?? this.isWifi,
      isConnecting: isConnecting ?? this.isConnecting,
      isConnected: isConnected ?? this.isConnected,
      error: error,
      rxLog: rxLog ?? this.rxLog,
    );
  }

  static const initial = WifiConnectionState(
    isWifi: false,
    isConnecting: false,
    isConnected: false,
    error: null,
    rxLog: [],
  );
}

final wifiConnectionProvider =
    StateNotifierProvider<WifiConnectionController, WifiConnectionState>(
  (ref) => WifiConnectionController(),
);

class WifiConnectionController extends StateNotifier<WifiConnectionState> {
  WifiConnectionController() : super(WifiConnectionState.initial) {
    _watchConnectivity();
  }

  final _connectivity = Connectivity();
  StreamSubscription? _connSub;

  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;

  // Хост твоего ESP32 AP
  final String host = "192.168.4.1";
  final int port = 81;
  final String path = "/ws";

  // очередь команд, если отправили чуть раньше соединения
  final List<String> _queue = [];

  void _log(String s) {
    final next = [...state.rxLog, s];
    state = state.copyWith(
        rxLog: next.length > 200 ? next.sublist(next.length - 200) : next);
  }

  Future<void> _watchConnectivity() async {
    final first = await _connectivity.checkConnectivity();
    state = state.copyWith(isWifi: first.contains(ConnectivityResult.wifi));

    _connSub = _connectivity.onConnectivityChanged.listen((res) {
      final isWifi = res.contains(ConnectivityResult.wifi);
      state = state.copyWith(isWifi: isWifi);

      // если Wi-Fi пропал — рвём соединение
      if (!isWifi && state.isConnected) {
        disconnect();
      }
    });
  }

  Uri get wsUri => Uri.parse("ws://$host:$port$path");

  Future<void> connect() async {
    if (state.isConnecting) return;

    // Главное: НЕ проверяем SSID. Только факт Wi-Fi.
    if (!state.isWifi) {
      state =
          state.copyWith(error: "Телефон не в Wi-Fi. Подключись к сети Robot.");
      return;
    }

    state = state.copyWith(isConnecting: true, error: null);

    try {
      // таймаут на коннект
      final socket = await WebSocket.connect(wsUri.toString()).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException("WebSocket connect timeout"),
      );

      _channel = IOWebSocketChannel(socket);
      _log("✓ WS connected: $wsUri");

      // слушаем входящие
      _wsSub?.cancel();
      _wsSub = _channel!.stream.listen((event) {
        final msg = event.toString();
        _log("← $msg");
        _onIncoming(msg);
      }, onError: (e) {
        state = state.copyWith(
            error: "WS error: $e", isConnected: false, isConnecting: false);
      }, onDone: () {
        state = state.copyWith(isConnected: false, isConnecting: false);
        _log("× WS closed");
      });

      // рукопожатие
      final ok = await _handshake();
      if (!ok) {
        await disconnect();
        state =
            state.copyWith(error: "Робот не ответил на handshake (PING/PONG).");
        return;
      }

      state =
          state.copyWith(isConnected: true, isConnecting: false, error: null);
      _log("✓ Handshake OK. CONNECTED.");

      // слить очередь
      for (final cmd in _queue) {
        _sendRaw(cmd);
      }
      _queue.clear();
    } catch (e) {
      state = state.copyWith(
          isConnecting: false, isConnected: false, error: e.toString());
    }
  }

  Future<bool> _handshake() async {
    // Ждём PONG/OK максимум 2 сек
    final completer = Completer<bool>();
    late final Timer timer;

    void handler(String msg) {
      final m = msg.trim().toUpperCase();
      if (m == "PONG" || m.startsWith("PONG") || m == "OK") {
        if (!completer.isCompleted) completer.complete(true);
      }
    }

    // временный “перехват” через логический обработчик
    _tempIncomingHandler = handler;

    timer = Timer(const Duration(seconds: 2), () {
      if (!completer.isCompleted) completer.complete(false);
    });

    _sendRaw("PING");
    final ok = await completer.future;
    timer.cancel();
    _tempIncomingHandler = null;
    return ok;
  }

  void _sendRaw(String text) {
    _channel?.sink.add(text);
    _log("→ $text");
  }

  // Публичный метод для терминала
  void sendRaw(String text) {
    final t = text.trim();
    if (t.isEmpty) return;

    if (!state.isConnected) {
      _queue.add(t);
      return;
    }
    _sendRaw(t);
  }

  Future<void> disconnect() async {
    state = state.copyWith(isConnecting: false, isConnected: false);
    try {
      await _wsSub?.cancel();
      await _channel?.sink.close();
    } catch (_) {}
    _wsSub = null;
    _channel = null;
    _log("× Disconnected");
  }

  // ====== команды управления ======
  void sendMove(int left, int right) {
    final l = left.clamp(-100, 100);
    final r = right.clamp(-100, 100);
    final cmd = "M,$l,$r";

    if (!state.isConnected) {
      _queue.add(cmd); // чтобы не терять команды
      return;
    }
    _sendRaw(cmd);
  }

  void sendStop() {
    const cmd = "STOP";
    if (!state.isConnected) {
      _queue.add(cmd);
      return;
    }
    _sendRaw(cmd);
  }

  // ====== входящие ======
  void Function(String msg)? _tempIncomingHandler;

  void _onIncoming(String msg) {
    _tempIncomingHandler?.call(msg);

    // тут можешь парсить телеметрию
    // например JSON: {"bat":30,"gps":1}
    // try { final j=jsonDecode(msg); ... } catch (_) {}
  }

  void clearLog() {
    state = state.copyWith(rxLog: []);
  }

  @override
  void dispose() {
    _connSub?.cancel();
    disconnect();
    super.dispose();
  }
}
