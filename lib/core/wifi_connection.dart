import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final wifiConnectionProvider =
    StateNotifierProvider<WifiConnectionController, WifiConnectionState>((ref) {
  return WifiConnectionController(ref);
});

@immutable
class WifiConnectionState {
  final bool isConnected;
  final bool isBusy; // подключение/отключение
  final bool isConnecting;
  final bool isSupported; // всегда true для WebSocket
  final bool isWifiOk; // SSID подходит

  final String deviceName; // имя робота (из SSID или по умолчанию)
  final String? error;

  final List<String> logLines; // RX/TX терминал

  const WifiConnectionState({
    required this.isConnected,
    required this.isBusy,
    required this.isConnecting,
    required this.isSupported,
    required this.isWifiOk,
    required this.deviceName,
    required this.error,
    required this.logLines,
  });

  factory WifiConnectionState.initial() => const WifiConnectionState(
        isConnected: false,
        isBusy: false,
        isConnecting: false,
        isSupported: true,
        isWifiOk: false,
        deviceName: 'HoverRobot',
        error: null,
        logLines: [],
      );

  WifiConnectionState copyWith({
    bool? isConnected,
    bool? isBusy,
    bool? isConnecting,
    bool? isSupported,
    bool? isWifiOk,
    String? deviceName,
    String? error,
    List<String>? logLines,
  }) {
    return WifiConnectionState(
      isConnected: isConnected ?? this.isConnected,
      isBusy: isBusy ?? this.isBusy,
      isConnecting: isConnecting ?? this.isConnecting,
      isSupported: isSupported ?? this.isSupported,
      isWifiOk: isWifiOk ?? this.isWifiOk,
      deviceName: deviceName ?? this.deviceName,
      error: error,
      logLines: logLines ?? this.logLines,
    );
  }
}

class WifiConnectionController extends StateNotifier<WifiConnectionState> {
  final Ref ref;
  WebSocketChannel? _channel;
  StreamSubscription? _wsSubscription;
  Timer? _reconnectTimer;
  Timer? _throttleTimer;

  static const String _robotUrl = 'ws://192.168.4.1:81/ws';
  static const int _throttleMs = 30; // throttling для команд джойстика
  static const int _maxLog = 220;

  String? _lastMoveCommand; // для throttling

  WifiConnectionController(this.ref) : super(WifiConnectionState.initial()) {
    _boot();
  }

  Future<void> _boot() async {
    // Проверяем Wi-Fi при старте
    await _checkWifi();

    // Периодически проверяем Wi-Fi (каждые 3 секунды)
    Timer.periodic(const Duration(seconds: 3), (_) {
      if (!state.isConnected) {
        _checkWifi();
      }
    });
  }

  /// Проверка Wi-Fi SSID
  Future<void> _checkWifi() async {
    try {
      final ssid = await getWifiName();
      final isOk = isCorrectWifi(ssid);

      String deviceName = state.deviceName;
      if (ssid != null && isOk) {
        deviceName = ssid;
      }

      state = state.copyWith(
        isWifiOk: isOk,
        deviceName: deviceName,
        error: isOk
            ? null
            : (state.error?.contains('Wi-Fi') == true ? state.error : null),
      );
    } catch (e) {
      // На iOS может быть недоступен SSID - это нормально
      if (kDebugMode) {
        _appendLog('⚠ Wi-Fi check: $e');
      }
    }
  }

  /// Получить SSID текущей Wi-Fi сети
  Future<String?> getWifiName() async {
    if (kIsWeb) {
      return null; // Web не поддерживает
    }

    try {
      // На Android 10+ нужен location permission для SSID
      if (Platform.isAndroid) {
        final status = await Permission.locationWhenInUse.status;
        if (!status.isGranted) {
          final result = await Permission.locationWhenInUse.request();
          if (!result.isGranted) {
            return null;
          }
        }
      }

      final networkInfo = NetworkInfo();
      final wifiName = await networkInfo.getWifiName();

      // На Android может вернуться в кавычках, убираем их
      if (wifiName != null &&
          wifiName.startsWith('"') &&
          wifiName.endsWith('"')) {
        return wifiName.substring(1, wifiName.length - 1);
      }

      return wifiName;
    } catch (e) {
      if (kDebugMode) {
        _appendLog('⚠ getWifiName error: $e');
      }
      return null;
    }
  }

  /// Проверка, что SSID подходит (содержит "Robot" или "HoverRobot")
  bool isCorrectWifi(String? ssid) {
    if (ssid == null) return false;
    final lower = ssid.toLowerCase();
    return lower.contains('robot') || lower.contains('hoverrobot');
  }

  /// Подключение к WebSocket
  Future<void> connect() async {
    if (state.isConnected || state.isConnecting) {
      return;
    }

    state = state.copyWith(
      isConnecting: true,
      isBusy: true,
      error: null,
    );

    // Проверяем Wi-Fi перед подключением
    await _checkWifi();

    if (!state.isWifiOk) {
      state = state.copyWith(
        isConnecting: false,
        isBusy: false,
        error: 'Подключитесь к Wi-Fi робота',
      );
      _appendLog('✗ CONNECT: Wi-Fi не подходит');
      return;
    }

    try {
      _appendLog('… CONNECTING to $_robotUrl');

      final uri = Uri.parse(_robotUrl);
      _channel = WebSocketChannel.connect(uri);

      // Подписываемся на входящие сообщения
      _wsSubscription?.cancel();
      _wsSubscription = _channel!.stream.listen(
        (message) {
          final text = message.toString();
          if (text.trim().isNotEmpty) {
            _appendLog('← $text');
          }
        },
        onError: (error) {
          _appendLog('✗ WS ERROR: $error');
          _handleDisconnection('ошибка WebSocket: $error');
        },
        onDone: () {
          _appendLog('… WS CLOSED');
          _handleDisconnection('соединение закрыто');
        },
        cancelOnError: true,
      );

      // Небольшая задержка для установки соединения
      await Future.delayed(const Duration(milliseconds: 500));

      state = state.copyWith(
        isConnected: true,
        isConnecting: false,
        isBusy: false,
      );

      _appendLog('✓ CONNECTED to $_robotUrl');
    } catch (e) {
      _appendLog('✗ CONNECT FAIL: $e');
      state = state.copyWith(
        isConnected: false,
        isConnecting: false,
        isBusy: false,
        error: 'Ошибка подключения: $e',
      );
      _cleanup();
    }
  }

  /// Отключение от WebSocket
  Future<void> disconnect() async {
    if (!state.isConnected) {
      return;
    }

    _appendLog('… DISCONNECT');

    // Отправляем STOP перед отключением
    if (_channel != null) {
      try {
        _channel!.sink.add('STOP');
        _appendLog('→ STOP');
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (_) {}
    }

    _cleanup();

    state = state.copyWith(
      isConnected: false,
      isConnecting: false,
      isBusy: false,
    );
  }

  void _handleDisconnection(String reason) {
    _appendLog('… DISCONNECTED ($reason)');
    _cleanup();
    state = state.copyWith(
      isConnected: false,
      isConnecting: false,
      isBusy: false,
      error: reason,
    );
  }

  void _cleanup() {
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _channel?.sink.close();
    _channel = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _lastMoveCommand = null;
  }

  /// Отправка команды движения: M,left,right
  void sendMove(int left, int right) {
    if (!state.isConnected || _channel == null) {
      return;
    }

    // Ограничиваем значения
    final leftClamped = left.clamp(-100, 100);
    final rightClamped = right.clamp(-100, 100);

    final command = 'M,$leftClamped,$rightClamped';

    // Throttling: не отправляем одинаковые команды слишком часто
    if (_lastMoveCommand == command) {
      return;
    }

    _throttleTimer?.cancel();
    _throttleTimer = Timer(Duration(milliseconds: _throttleMs), () {
      _lastMoveCommand = null;
    });

    _lastMoveCommand = command;

    try {
      _channel!.sink.add(command);
      // Не логируем каждую команду джойстика, чтобы не засорять лог
    } catch (e) {
      _appendLog('✗ SEND MOVE FAIL: $e');
      if (state.isConnected) {
        state = state.copyWith(error: 'Ошибка отправки: $e');
      }
    }
  }

  /// Отправка команды STOP
  void sendStop() {
    if (!state.isConnected || _channel == null) {
      return;
    }

    _lastMoveCommand = null;
    _throttleTimer?.cancel();
    _throttleTimer = null;

    try {
      _channel!.sink.add('STOP');
      _appendLog('→ STOP');
    } catch (e) {
      _appendLog('✗ SEND STOP FAIL: $e');
      if (state.isConnected) {
        state = state.copyWith(error: 'Ошибка отправки STOP: $e');
      }
    }
  }

  /// Отправка произвольной команды (для терминала)
  Future<void> sendRaw(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;

    if (!state.isConnected || _channel == null) {
      _appendLog('✗ TX (нет соединения)');
      return;
    }

    try {
      _channel!.sink.add(t);
      _appendLog('→ $t');
    } catch (e) {
      state = state.copyWith(error: 'Ошибка отправки: $e');
      _appendLog('✗ TX FAIL: $e');
    }
  }

  void clearLog() => state = state.copyWith(logLines: []);

  void _appendLog(String line) {
    final next = [...state.logLines, line];
    final trimmed =
        next.length <= _maxLog ? next : next.sublist(next.length - _maxLog);
    state = state.copyWith(logLines: trimmed);
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}
