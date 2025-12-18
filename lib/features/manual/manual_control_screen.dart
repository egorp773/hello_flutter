import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:hello_flutter/core/wifi_connection.dart';

/// ============================================================================
/// Battery mock (потом заменим на реальную телеметрию)
/// ============================================================================
final batteryPercentProvider = StateProvider<int>((ref) => 46);

/// ============================================================================
/// ✅ Speed настройки (1.0 = базовая скорость, 0.33 = ~в 3 раза медленнее)
/// ============================================================================
final manualSpeedProvider = StateProvider<double>((ref) => 0.33);

/// ============================================================================
/// ✅ Режим управления
/// ============================================================================
enum ControlMode {
  joystick, // Аналоговый джойстик
  arrows, // Управление стрелками (F/B/R/L/S)
}

final controlModeProvider =
    StateProvider<ControlMode>((ref) => ControlMode.joystick);

/// ============================================================================
/// Notice overlay — всегда поверх всего, с плавной анимацией
/// ============================================================================
enum NoticeKind { info, success, warning, danger }

@immutable
class NoticeState {
  final String title;
  final String message;
  final NoticeKind kind;
  const NoticeState({
    required this.title,
    required this.message,
    required this.kind,
  });
}

final noticeProvider =
    StateNotifierProvider<NoticeController, NoticeState?>((ref) {
  return NoticeController();
});

class NoticeController extends StateNotifier<NoticeState?> {
  NoticeController() : super(null);

  Timer? _t;

  void show(NoticeState n, {Duration ttl = const Duration(seconds: 3)}) {
    _t?.cancel();
    state = n;
    _t = Timer(ttl, () => state = null);
  }

  void hide() => state = null;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }
}

/// ============================================================================
/// Terminal - использует логи из wifiConnectionProvider
/// ============================================================================
@immutable
class TerminalState {
  final List<String> lines;
  const TerminalState(this.lines);
}

final terminalProvider =
    StateNotifierProvider<TerminalController, TerminalState>((ref) {
  return TerminalController(ref);
});

class TerminalController extends StateNotifier<TerminalState> {
  final Ref ref;
  TerminalController(this.ref) : super(const TerminalState([])) {
    // Следим за логами из wifiConnectionProvider
    ref.listen(wifiConnectionProvider, (prev, next) {
      if (prev?.rxLog != next.rxLog) {
        state = TerminalState(next.rxLog);
      }
    });
  }

  /// Отправка реальной команды в WebSocket терминал.
  Future<void> send(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;

    // Реальная отправка через WifiConnectionController
    ref.read(wifiConnectionProvider.notifier).sendRaw(t);
  }

  void clear() {
    // Очистка логов в wifiConnectionProvider
    ref.read(wifiConnectionProvider.notifier).clearLog();
  }
}

/// ============================================================================
/// Manual map model
/// ============================================================================
enum DrawKind { zone, forbidden, transition }

enum ManualStage { idle, drawing, completed }

@immutable
class PolyShape {
  final List<Offset> points; // world coords (cells)
  const PolyShape(this.points);
}

@immutable
class ManualMapState {
  final ManualStage stage;

  final String? mapName;
  final DrawKind? kind;

  final Offset robot; // world position in cells
  final double zoom; // 0.55..2.6
  final Offset pan; // pixels

  final List<PolyShape> zones;
  final List<PolyShape> forbiddens;
  final List<List<Offset>> transitions;

  final List<Offset> stroke; // current drawing

  const ManualMapState({
    required this.stage,
    required this.mapName,
    required this.kind,
    required this.robot,
    required this.zoom,
    required this.pan,
    required this.zones,
    required this.forbiddens,
    required this.transitions,
    required this.stroke,
  });

  ManualMapState copyWith({
    ManualStage? stage,
    String? mapName,
    DrawKind? kind,
    Offset? robot,
    double? zoom,
    Offset? pan,
    List<PolyShape>? zones,
    List<PolyShape>? forbiddens,
    List<List<Offset>>? transitions,
    List<Offset>? stroke,
  }) {
    return ManualMapState(
      stage: stage ?? this.stage,
      mapName: mapName ?? this.mapName,
      kind: kind ?? this.kind,
      robot: robot ?? this.robot,
      zoom: zoom ?? this.zoom,
      pan: pan ?? this.pan,
      zones: zones ?? this.zones,
      forbiddens: forbiddens ?? this.forbiddens,
      transitions: transitions ?? this.transitions,
      stroke: stroke ?? this.stroke,
    );
  }

  static ManualMapState initial() => const ManualMapState(
        stage: ManualStage.idle,
        mapName: null,
        kind: null,
        robot: Offset(0, 0),
        zoom: 1.0,
        pan: Offset.zero,
        zones: [],
        forbiddens: [],
        transitions: [],
        stroke: [],
      );
}

final manualMapProvider =
    StateNotifierProvider<ManualMapController, ManualMapState>((ref) {
  return ManualMapController(ref);
});

class ManualMapController extends StateNotifier<ManualMapState> {
  final Ref ref;
  ManualMapController(this.ref) : super(ManualMapState.initial());

  bool get _isConnected => ref.read(wifiConnectionProvider).isConnected;

  void setName(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return;
    state = state.copyWith(mapName: clean);
  }

  void setKind(DrawKind k) => state = state.copyWith(kind: k);

  /// ✅ После выбора модификатора возвращаем "idle",
  /// чтобы появились Джойстик + Старт
  void armForNextStart(DrawKind k) {
    state = state.copyWith(
      kind: k,
      stage: ManualStage.idle,
    );
  }

  void setZoom(double z) => state = state.copyWith(zoom: z.clamp(0.55, 2.6));
  void zoomIn() => setZoom(state.zoom * 1.12);
  void zoomOut() => setZoom(state.zoom / 1.12);

  void panBy(Offset dPx) => state = state.copyWith(pan: state.pan + dPx);

  /// центрирование: сбрасываем панорамирование
  void centerOnRobot() => state = state.copyWith(pan: Offset.zero);

  void resetAll() => state = ManualMapState.initial();

  /// ✅ Перерисовать: НЕ сбрасывает название карты
  void redrawKeepName() {
    state = state.copyWith(
      stage: ManualStage.idle,
      kind: null,
      zones: const [],
      forbiddens: const [],
      transitions: const [],
      stroke: const [],
    );
    ref.read(noticeProvider.notifier).show(const NoticeState(
          title: 'Перерисовка',
          message: 'Переместите робота и нажмите «Старт».',
          kind: NoticeKind.info,
        ));
  }

  void moveRobot(Offset direction) {
    if (!_isConnected) {
      ref.read(noticeProvider.notifier).show(const NoticeState(
            title: 'Подключение',
            message: 'Подключитесь к роботу.',
            kind: NoticeKind.danger,
          ));
      return;
    }

    // direction теперь это нормализованный вектор направления от джойстика (-1..1)
    // Если джойстик в центре (нулевое направление), отправляем STOP
    if (direction.dx.abs() < 0.001 && direction.dy.abs() < 0.001) {
      ref.read(wifiConnectionProvider.notifier).sendStop();
      return;
    }

    // Обновляем позицию робота на карте (для визуализации)
    // Используем небольшой шаг для плавного движения
    final stepSize = 0.15 * ref.read(manualSpeedProvider);
    final deltaCells = Offset(
      direction.dx * stepSize,
      direction.dy * stepSize,
    );
    final next = state.robot + deltaCells;
    state = state.copyWith(robot: next);

    if (state.stage == ManualStage.drawing) {
      _appendStroke(next);
    }

    // Преобразуем нормализованное направление в дифференциальные значения left/right
    // Координаты: dx - это движение влево/вправо (поворот),
    // dy - это движение вверх/вниз (вперёд/назад)
    // Для робота: вверх (вперёд) = положительное y, поэтому инвертируем
    final vx = direction.dx.clamp(-1.0, 1.0);
    final vy = -direction.dy
        .clamp(-1.0, 1.0); // инвертируем для правильного направления

    // Получаем множитель скорости из настроек
    final speedMultiplier = ref.read(manualSpeedProvider);

    // Дифференциальное управление:
    // left = vy - vx (вперёд/назад минус поворот)
    // right = vy + vx (вперёд/назад плюс поворот)
    final left = ((vy - vx) * speedMultiplier * 100).round().clamp(-100, 100);
    final right = ((vy + vx) * speedMultiplier * 100).round().clamp(-100, 100);

    // Отправляем команду в формате M,left,right
    ref.read(wifiConnectionProvider.notifier).sendMove(left, right);
  }

  void _appendStroke(Offset p) {
    if (state.stroke.isNotEmpty) {
      final last = state.stroke.last;
      if ((last - p).distance < 0.0005) return;
    }
    state = state.copyWith(stroke: [...state.stroke, p]);
  }

  bool _needsClosure(DrawKind k) =>
      (k == DrawKind.zone || k == DrawKind.forbidden);

  /// Запуск записи (когда имя и режим уже известны)
  void startDrawing() {
    if (!_isConnected) {
      ref.read(noticeProvider.notifier).show(const NoticeState(
            title: 'Подключение',
            message: 'Подключитесь к роботу.',
            kind: NoticeKind.danger,
          ));
      return;
    }
    if (state.mapName == null || state.kind == null) return;

    state = state.copyWith(stage: ManualStage.drawing, stroke: [state.robot]);

    ref.read(noticeProvider.notifier).show(NoticeState(
          title: 'Запись Начата',
          message: _kindLabel(state.kind!),
          kind: NoticeKind.success,
        ));
  }

  /// Стоп записи
  void stopDrawing() {
    if (state.stage != ManualStage.drawing) return;
    final k = state.kind!;
    final pts = state.stroke;
    if (pts.length < 2) {
      state = state.copyWith(stage: ManualStage.idle, stroke: []);
      return;
    }

    if (_needsClosure(k)) {
      final start = pts.first;
      final end = pts.last;
      final dist = (end - start).distance;

      // авто-замыкание если ближе чем 3 клетки
      if (dist > 0.001 && dist < 3.0) {
        final closed = [...pts, start];
        _commit(k, closed);
        return;
      }

      // далеко — просим замкнуть, остаёмся в drawing
      if (dist >= 3.0) {
        ref.read(noticeProvider.notifier).show(const NoticeState(
              title: 'Периметр Не Замкнут',
              message: 'Подведите робота к стартовой точке и замкните контур.',
              kind: NoticeKind.warning,
            ));
        return;
      }
    }

    _commit(k, pts);
  }

  void _commit(DrawKind k, List<Offset> pts) {
    if (k == DrawKind.zone) {
      state = state.copyWith(zones: [...state.zones, PolyShape(pts)]);
    } else if (k == DrawKind.forbidden) {
      state = state.copyWith(forbiddens: [...state.forbiddens, PolyShape(pts)]);
    } else {
      state = state.copyWith(transitions: [...state.transitions, pts]);
    }

    state = state.copyWith(stage: ManualStage.completed, stroke: const []);
    ref.read(noticeProvider.notifier).show(const NoticeState(
          title: 'Готово',
          message: 'Запись завершена.',
          kind: NoticeKind.success,
        ));
  }

  void saveAndReset() {
    ref.read(noticeProvider.notifier).show(const NoticeState(
          title: 'Карта Сохранена',
          message: 'Данные сохранены. Вы можете начать заново.',
          kind: NoticeKind.success,
        ));
    resetAll();
  }

  static String _kindLabel(DrawKind k) {
    switch (k) {
      case DrawKind.zone:
        return 'Режим: Зона Уборки';
      case DrawKind.forbidden:
        return 'Режим: Запретная Зона';
      case DrawKind.transition:
        return 'Режим: Переход Между Зонами';
    }
  }
}

/// ============================================================================
/// Kind UI metadata (иконки + цвета)
/// ============================================================================
class KindMeta {
  final DrawKind kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  const KindMeta({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

// Цветовая схема для модификаторов и путей
const _kNeon = Color(0xFF3DE7FF); // Неоновый голубой для переходов
const _kGood = Color(0xFF38F6A7); // Зеленый для зон уборки
const _kBad = Color(0xFFFF4D6D); // Красный для запретных зон

const List<KindMeta> kKinds = [
  KindMeta(
    kind: DrawKind.zone,
    title: 'Зона Уборки',
    subtitle: 'Участок, где робот будет убирать.',
    icon: Icons.grid_on_rounded,
    color: _kGood,
  ),
  KindMeta(
    kind: DrawKind.forbidden,
    title: 'Запретная Зона',
    subtitle: 'Участок, куда робот не заедет.',
    icon: Icons.block_rounded,
    color: _kBad,
  ),
  KindMeta(
    kind: DrawKind.transition,
    title: 'Переход Между Зонами',
    subtitle: 'Путь до другой территории.',
    icon: Icons.alt_route_rounded,
    color: _kNeon,
  ),
];

/// ✅ Для "Выбор режима" оставляем ТОЛЬКО 2 режима (без запретной зоны)
final List<KindMeta> kStartKinds = <KindMeta>[
  kKinds.firstWhere((e) => e.kind == DrawKind.zone),
  kKinds.firstWhere((e) => e.kind == DrawKind.transition),
];

KindMeta metaOf(DrawKind k) => kKinds.firstWhere((e) => e.kind == k);

/// ============================================================================
/// Screen
/// ============================================================================
class ManualControlScreen extends ConsumerStatefulWidget {
  const ManualControlScreen({super.key});

  @override
  ConsumerState<ManualControlScreen> createState() =>
      _ManualControlScreenState();
}

class _ManualControlScreenState extends ConsumerState<ManualControlScreen> {
  Future<void> _toggleWifiConnection() async {
    final wifi = ref.read(wifiConnectionProvider);
    final ctrl = ref.read(wifiConnectionProvider.notifier);

    if (wifi.isConnected) {
      await ctrl.disconnect();
      return;
    }

    // Подключаемся к WebSocket
    await ctrl.connect();
  }

  @override
  Widget build(BuildContext context) {
    final wifi = ref.watch(wifiConnectionProvider);
    final battery = ref.watch(batteryPercentProvider);
    final speed = ref.watch(manualSpeedProvider); // ✅ скорость
    final s = ref.watch(manualMapProvider);
    final notice = ref.watch(noticeProvider);

    return Scaffold(
      body: LayoutBuilder(builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final safeTop = media.padding.top;
        final safeBottom = media.padding.bottom;

        final scaleH = constraints.maxHeight / 820.0;
        final scaleW = constraints.maxWidth / 390.0;
        final uiScale = math.min(scaleH, scaleW).clamp(0.70, 1.0);
        double u(double v) => v * uiScale;

        final pad = u(16).clamp(12.0, 16.0);
        final gap = u(10).clamp(8.0, 10.0);

        final contentH = constraints.maxHeight - safeTop - safeBottom;

        final topBarH = u(54).clamp(46.0, 54.0);
        final statusH = u(72).clamp(62.0, 72.0);

        final baseControls = (contentH * 0.33);
        final controlsMax = u(270).clamp(220.0, 270.0);
        final controlsMin = u(215).clamp(190.0, 215.0);
        final controlsH = baseControls.clamp(controlsMin, controlsMax);

        return Stack(
          children: [
            Positioned.fill(child: _PremiumBG(isConnected: wifi.isConnected)),
            const Positioned.fill(child: _Vignette()),

            SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, pad, pad, pad),
                child: Column(
                  children: [
                    SizedBox(
                      height: topBarH,
                      child: _TopBar(
                        uiScale: uiScale,
                        title: _headerTitle(s),
                        onBack: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/');
                          }
                        },
                        onTerminal: () => _openTerminal(context),
                        onSettings: () => _openSettings(context), // ✅
                      ),
                    ),
                    SizedBox(height: gap),
                    SizedBox(
                      height: statusH,
                      child: _StatusPanel(
                        uiScale: uiScale,
                        wifi: wifi,
                        batteryPercent: battery,
                        onToggle: _toggleWifiConnection,
                      ),
                    ),
                    SizedBox(height: gap),
                    Expanded(
                      child: _MapCard(
                        uiScale: uiScale,
                        state: s,
                        onPan: (d) =>
                            ref.read(manualMapProvider.notifier).panBy(d),
                        onZoom: (z) =>
                            ref.read(manualMapProvider.notifier).setZoom(z),
                        onZoomIn: () =>
                            ref.read(manualMapProvider.notifier).zoomIn(),
                        onZoomOut: () =>
                            ref.read(manualMapProvider.notifier).zoomOut(),
                        onCenter: () => ref
                            .read(manualMapProvider.notifier)
                            .centerOnRobot(),
                      ),
                    ),
                    SizedBox(height: gap),
                    SizedBox(
                      height: controlsH,
                      child: _ControlsArea(
                        uiScale: uiScale,
                        speedFactor: speed, // ✅ передали скорость
                        wifiConnected: wifi.isConnected,
                        stage: s.stage,
                        mapName: s.mapName,
                        kind: s.kind,
                        onStartWizard: () => _startWizard(
                          context,
                          wifi,
                          s.mapName,
                        ),
                        onQuickStart: () =>
                            ref.read(manualMapProvider.notifier).startDrawing(),
                        onStop: () =>
                            ref.read(manualMapProvider.notifier).stopDrawing(),
                        onRedraw: () => ref
                            .read(manualMapProvider.notifier)
                            .redrawKeepName(),
                        onModify: () => _openModifiers(context),
                        onSave: () =>
                            ref.read(manualMapProvider.notifier).saveAndReset(),
                        onMove: (d) =>
                            ref.read(manualMapProvider.notifier).moveRobot(d),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // уведомления поверх всего
            Positioned(
              left: pad,
              right: pad,
              top: safeTop + u(110),
              child: IgnorePointer(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) {
                    final slide = Tween<Offset>(
                      begin: const Offset(0, -0.18),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                    );
                    final fade = CurvedAnimation(
                        parent: anim, curve: Curves.easeOutCubic);
                    return FadeTransition(
                      opacity: fade,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: notice == null
                      ? const SizedBox(key: ValueKey('no_notice'))
                      : _NoticeBanner(
                          key: ValueKey(
                              '${notice.kind}-${notice.title}-${notice.message}'),
                          uiScale: uiScale,
                          n: notice,
                        ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  String _headerTitle(ManualMapState s) {
    if (s.mapName == null) return 'Ручное Управление';
    return 'Создание Карты (${_cap(s.mapName!)})';
  }

  static String _cap(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  Future<void> _startWizard(BuildContext context, WifiConnectionState wifi,
      String? existingName) async {
    if (!wifi.isConnected) {
      ref.read(noticeProvider.notifier).show(const NoticeState(
            title: 'Подключение',
            message: 'Подключитесь к роботу.',
            kind: NoticeKind.danger,
          ));
      return;
    }

    // если имя уже задано — не спрашиваем снова
    String? name = existingName;
    if (name == null) {
      name = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        barrierColor: Colors.black.withOpacity(0.55),
        builder: (_) => const _NameMapSheet(),
      );
      if (name == null || name.trim().isEmpty) return;
      ref.read(manualMapProvider.notifier).setName(name.trim());
    }

    // ✅ выбор режима: только kStartKinds (без запретной зоны)
    final kind = await showModalBottomSheet<DrawKind>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (_) => _ModePickSheet(
        title: 'Выбор Режима',
        selected: ref.read(manualMapProvider).kind,
        kinds: kStartKinds,
      ),
    );
    if (kind == null) return;

    ref.read(manualMapProvider.notifier).setKind(kind);
    ref.read(manualMapProvider.notifier).startDrawing();
  }

  Future<void> _openModifiers(BuildContext context) async {
    final selected = ref.read(manualMapProvider).kind;
    final pick = await showModalBottomSheet<DrawKind>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (_) => _ModePickSheet(
        title: 'Модификаторы',
        selected: selected,
        kinds: kKinds, // здесь есть и запретная зона
      ),
    );
    if (pick == null) return;

    // ✅ после выбора модификатора возвращаем idle, чтобы были Старт + джойстик
    ref.read(manualMapProvider.notifier).armForNextStart(pick);

    final m = metaOf(pick);
    ref.read(noticeProvider.notifier).show(NoticeState(
          title: 'Режим Выбран',
          message: m.title,
          kind: NoticeKind.info,
        ));
  }

  void _openTerminal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (_) => const _TerminalSheet(),
    );
  }

  void _openSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (_) => const _SpeedSettingsSheet(),
    );
  }
}

/// ============================================================================
/// Controls (плавные переключения + аналоговый джойстик)
/// ============================================================================
class _ControlsArea extends ConsumerWidget {
  final double uiScale;
  final double speedFactor; // ✅ скорость
  final bool wifiConnected;

  final ManualStage stage;
  final String? mapName;
  final DrawKind? kind;

  final VoidCallback onStartWizard;
  final VoidCallback onQuickStart;
  final VoidCallback onStop;

  final VoidCallback onRedraw;
  final VoidCallback onModify;
  final VoidCallback onSave;

  final ValueChanged<Offset> onMove;

  const _ControlsArea({
    required this.uiScale,
    required this.speedFactor,
    required this.wifiConnected,
    required this.stage,
    required this.mapName,
    required this.kind,
    required this.onStartWizard,
    required this.onQuickStart,
    required this.onStop,
    required this.onRedraw,
    required this.onModify,
    required this.onSave,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double u(double v) => v * uiScale;
    final gap = u(10).clamp(8.0, 10.0);
    final mode = ref.watch(controlModeProvider);

    Widget body;

    if (stage == ManualStage.completed) {
      body = _VerticalActionsPanel(
        uiScale: uiScale,
        onRedraw: onRedraw,
        onModify: onModify,
        onSave: onSave,
      );
    } else if (stage == ManualStage.drawing) {
      body = SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          key: const ValueKey('drawing'),
          children: [
            _PrimaryBtn(
              uiScale: uiScale,
              text: 'Стоп',
              color: Color(0xFF6E6E6E),
              enabled: true,
              onTap: onStop,
            ),
            SizedBox(height: gap),
            mode == ControlMode.joystick
                ? _AnalogJoystick(
                    uiScale: uiScale,
                    enabled: wifiConnected,
                    speedFactor: speedFactor,
                    onMove: onMove,
                  )
                : _ArrowControls(
                    uiScale: uiScale,
                    enabled: wifiConnected,
                    speedFactor: speedFactor,
                  ),
          ],
        ),
      );
    } else {
      // idle
      body = SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          key: const ValueKey('idle'),
          children: [
            _PrimaryBtn(
              uiScale: uiScale,
              text: 'Старт',
              color: Colors.white,
              enabled: true,
              // ✅ если уже есть имя+режим (например после Модификаторов) — стартуем сразу
              onTap: (mapName != null && kind != null)
                  ? onQuickStart
                  : onStartWizard,
            ),
            SizedBox(height: gap),
            mode == ControlMode.joystick
                ? _AnalogJoystick(
                    uiScale: uiScale,
                    enabled: wifiConnected,
                    speedFactor: speedFactor,
                    onMove: onMove,
                  )
                : _ArrowControls(
                    uiScale: uiScale,
                    enabled: wifiConnected,
                    speedFactor: speedFactor,
                  ),
          ],
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        final fade = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        final scale = Tween<double>(begin: 0.98, end: 1.0).animate(fade);
        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      child: body,
    );
  }
}

class _VerticalActionsPanel extends StatelessWidget {
  final double uiScale;
  final VoidCallback onRedraw;
  final VoidCallback onModify;
  final VoidCallback onSave;

  const _VerticalActionsPanel({
    required this.uiScale,
    required this.onRedraw,
    required this.onModify,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final pad = (14 * uiScale).clamp(10.0, 14.0);
      final h = c.maxHeight - pad * 2;
      final gap = math.min(10.0 * uiScale, math.max(6.0, h * 0.06));
      final btnH = ((h - 2 * gap) / 3).clamp(34.0, 56.0);

      return _GlassCard(
        borderColor: Colors.white.withOpacity(0.18),
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            children: [
              _SecondaryBtn(
                uiScale: uiScale,
                height: btnH,
                text: 'Перерисовать',
                onTap: onRedraw,
              ),
              SizedBox(height: gap),
              _SecondaryBtn(
                uiScale: uiScale,
                height: btnH,
                text: 'Модифицировать',
                onTap: onModify,
              ),
              SizedBox(height: gap),
              _PrimaryBtn(
                uiScale: uiScale,
                text: 'Сохранить',
                color: Colors.white,
                enabled: true,
                onTap: onSave,
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// ============================================================================
/// ✅ Аналоговый джойстик (углы + скорость по отклонению)
/// ============================================================================
class _AnalogJoystick extends StatefulWidget {
  final double uiScale;
  final bool enabled;
  final double speedFactor; // ✅
  final ValueChanged<Offset> onMove;

  const _AnalogJoystick({
    required this.uiScale,
    required this.enabled,
    required this.speedFactor,
    required this.onMove,
  });

  @override
  State<_AnalogJoystick> createState() => _AnalogJoystickState();
}

class _AnalogJoystickState extends State<_AnalogJoystick>
    with SingleTickerProviderStateMixin {
  Offset _knob = Offset.zero; // px
  Timer? _ticker;

  late final AnimationController _returnCtrl;
  Tween<Offset>? _returnTween;

  @override
  void initState() {
    super.initState();
    _returnCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 140))
      ..addListener(() {
        if (_returnTween != null) {
          setState(() => _knob = _returnTween!.evaluate(_returnCtrl));
        }
      });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _returnCtrl.dispose();
    super.dispose();
  }

  void _startTick() {
    _ticker ??= Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!widget.enabled) {
        _stopTick();
        return;
      }

      final r = _radius();
      if (r <= 1) {
        _stopTick();
        return;
      }

      final v = _knob / r; // -1..1 нормализованный вектор направления
      final mag = v.distance.clamp(0.0, 1.0);

      // Если джойстик в центре (или очень близко), отправляем STOP
      if (mag < 0.03) {
        widget.onMove(Offset.zero);
        return;
      }

      // Отправляем нормализованный вектор направления (-1..1) напрямую
      // Контроллер сам применит экспоненциальную кривую и преобразует в протокол
      // speedFactor уже учтён в контроллере через настройки
      widget.onMove(Offset(v.dx, v.dy));
    });
  }

  void _stopTick() {
    _ticker?.cancel();
    _ticker = null;
    // при отпускании джойстика отправляем "ноль",
    // чтобы приложение послало STOP на робота
    if (widget.enabled) {
      widget.onMove(Offset.zero);
    }
  }

  double _radius() => (70 * widget.uiScale).clamp(56.0, 74.0);

  void _animateBack() {
    _returnCtrl.stop();
    _returnTween = Tween<Offset>(begin: _knob, end: Offset.zero);
    _returnCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final r = _radius();
    final size = r * 2;

    return Center(
      child: _GlassCard(
        borderColor: Colors.white.withOpacity(0.10),
        child: SizedBox(
          width: size + 48,
          height: size + 48,
          child: GestureDetector(
            onPanStart: widget.enabled
                ? (_) {
                    _returnCtrl.stop();
                    _startTick();
                  }
                : null,
            onPanUpdate: widget.enabled
                ? (d) {
                    final next = _knob + d.delta;
                    final clamped = _clampToRadius(next, r);
                    setState(() => _knob = clamped);
                  }
                : null,
            onPanEnd: widget.enabled
                ? (_) {
                    _stopTick();
                    _animateBack();
                  }
                : null,
            onPanCancel: () {
              _stopTick();
              _animateBack();
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(size: Size.infinite, painter: _JoyBasePainter()),
                Positioned(
                    top: 18,
                    child: Icon(Icons.keyboard_arrow_up_rounded,
                        color: Colors.white.withOpacity(0.35))),
                Positioned(
                    bottom: 18,
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.white.withOpacity(0.35))),
                Positioned(
                    left: 18,
                    child: Icon(Icons.keyboard_arrow_left_rounded,
                        color: Colors.white.withOpacity(0.35))),
                Positioned(
                    right: 18,
                    child: Icon(Icons.keyboard_arrow_right_rounded,
                        color: Colors.white.withOpacity(0.35))),
                Transform.translate(
                  offset: _knob,
                  child: _JoyKnob(
                    color: widget.enabled
                        ? Colors.white
                        : Colors.white.withOpacity(0.25),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Offset _clampToRadius(Offset v, double r) {
    final mag = v.distance;
    if (mag <= r) return v;
    if (mag < 0.0001) return Offset.zero;
    return v / mag * r;
  }
}

class _JoyBasePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.28;

    canvas.drawCircle(
        c, r * 1.45, Paint()..color = Colors.white.withOpacity(0.02));
    canvas.drawCircle(
        c, r * 0.95, Paint()..color = Colors.white.withOpacity(0.03));

    final ring = Paint()
      ..color = Colors.white.withOpacity(0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawCircle(c, r * 1.05, ring);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _JoyKnob extends StatelessWidget {
  final Color color;
  const _JoyKnob({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withOpacity(0.35), Colors.white.withOpacity(0.06)],
        ),
        border: Border.all(color: color.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.18), blurRadius: 18, spreadRadius: 1)
        ],
      ),
      child: Center(
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: Colors.white.withOpacity(0.82)),
        ),
      ),
    );
  }
}

/// ============================================================================
/// Управление стрелками (F/B/R/L/S)
/// ============================================================================
class _ArrowControls extends ConsumerWidget {
  final double uiScale;
  final bool enabled;
  final double speedFactor;

  const _ArrowControls({
    required this.uiScale,
    required this.enabled,
    required this.speedFactor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double u(double v) => v * uiScale;
    final btnSize = u(55).clamp(50.0, 65.0);
    final gap = u(6).clamp(4.0, 8.0);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Center(
        child: _GlassCard(
          borderColor: Colors.white.withOpacity(0.10),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: gap, vertical: gap),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Верхняя строка: только F (вперед)
                _ArrowButton(
                  size: btnSize,
                  icon: Icons.keyboard_arrow_up_rounded,
                  enabled: enabled,
                  color: Colors.white,
                  onPressed: () {
                    // Вперёд: M,50,50
                    ref.read(wifiConnectionProvider.notifier).sendMove(50, 50);
                  },
                  onReleased: () {
                    ref.read(wifiConnectionProvider.notifier).sendStop();
                  },
                ),
                SizedBox(height: gap),
                // Средняя строка: L, S, R
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ArrowButton(
                      size: btnSize,
                      icon: Icons.keyboard_arrow_left_rounded,
                      enabled: enabled,
                      color: Colors.white,
                      onPressed: () {
                        // Влево (поворот на месте): M,-50,50
                        ref
                            .read(wifiConnectionProvider.notifier)
                            .sendMove(-50, 50);
                      },
                      onReleased: () {
                        ref.read(wifiConnectionProvider.notifier).sendStop();
                      },
                    ),
                    SizedBox(width: gap),
                    _ArrowButton(
                      size: btnSize,
                      icon: Icons.stop_rounded,
                      enabled: enabled,
                      color: Color(0xFF6E6E6E),
                      onPressed: () {
                        ref.read(wifiConnectionProvider.notifier).sendStop();
                      },
                    ),
                    SizedBox(width: gap),
                    _ArrowButton(
                      size: btnSize,
                      icon: Icons.keyboard_arrow_right_rounded,
                      enabled: enabled,
                      color: Colors.white,
                      onPressed: () {
                        // Вправо (поворот на месте): M,50,-50
                        ref
                            .read(wifiConnectionProvider.notifier)
                            .sendMove(50, -50);
                      },
                      onReleased: () {
                        ref.read(wifiConnectionProvider.notifier).sendStop();
                      },
                    ),
                  ],
                ),
                SizedBox(height: gap),
                // Нижняя строка: только B (назад)
                _ArrowButton(
                  size: btnSize,
                  icon: Icons.keyboard_arrow_down_rounded,
                  enabled: enabled,
                  color: Color(0xFF6E6E6E),
                  onPressed: () {
                    // Назад: M,-50,-50
                    ref
                        .read(wifiConnectionProvider.notifier)
                        .sendMove(-50, -50);
                  },
                  onReleased: () {
                    ref.read(wifiConnectionProvider.notifier).sendStop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final double size;
  final IconData icon;
  final bool enabled;
  final Color color;
  final VoidCallback onPressed;
  final VoidCallback? onReleased;

  const _ArrowButton({
    required this.size,
    required this.icon,
    required this.enabled,
    required this.color,
    required this.onPressed,
    this.onReleased,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: enabled ? (_) => onPressed() : null,
      onTapUp: enabled && onReleased != null ? (_) => onReleased!() : null,
      onTapCancel: enabled && onReleased != null ? () => onReleased!() : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(enabled ? 0.28 : 0.14),
              Colors.white.withOpacity(0.06)
            ],
          ),
          border: Border.all(
            color: color.withOpacity(enabled ? 0.55 : 0.25),
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.22),
                    blurRadius: 18,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Center(
          child: Icon(
            icon,
            color: enabled ? color : Colors.white.withOpacity(0.4),
            size: size * 0.55,
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// Top Bar + Status
/// ============================================================================
class _TopBar extends StatelessWidget {
  final double uiScale;
  final String title;
  final VoidCallback onBack;
  final VoidCallback onTerminal;
  final VoidCallback onSettings;

  const _TopBar({
    required this.uiScale,
    required this.title,
    required this.onBack,
    required this.onTerminal,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    double u(double v) => v * uiScale;

    return Row(
      children: [
        _IconBtn(
            uiScale: uiScale, icon: Icons.arrow_back_rounded, onTap: onBack),
        SizedBox(width: u(10)),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontSize: u(16.5).clamp(14.0, 16.5),
              fontWeight: FontWeight.w900,
              letterSpacing: 0.10,
            ),
          ),
        ),
        SizedBox(width: u(10)),
        _IconBtn(uiScale: uiScale, icon: Icons.tune_rounded, onTap: onSettings),
        SizedBox(width: u(10)),
        _IconBtn(
            uiScale: uiScale, icon: Icons.terminal_rounded, onTap: onTerminal),
      ],
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final double uiScale;
  final WifiConnectionState wifi;
  final int batteryPercent;
  final VoidCallback onToggle;

  const _StatusPanel({
    required this.uiScale,
    required this.wifi,
    required this.batteryPercent,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    double u(double v) => v * uiScale;
    // Серые оттенки для UI, но статус подключения может быть цветным
    const accentGray = Color(0xFF6E6E6E);
    final accent = wifi.isConnected ? Colors.white : accentGray;

    String statusText;
    if (wifi.isConnecting) {
      statusText = 'Подключение…';
    } else if (wifi.isConnected) {
      statusText = 'Подключено';
    } else if (!wifi.isWifi) {
      statusText = 'Подключитесь к Wi-Fi робота';
    } else {
      statusText = 'Не подключено';
    }

    return _GlassCard(
      borderColor: accent.withOpacity(0.32),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: u(12).clamp(10.0, 12.0),
          vertical: u(10).clamp(8.0, 10.0),
        ),
        child: Row(
          children: [
            _BatteryChip(uiScale: uiScale, percent: batteryPercent),
            SizedBox(width: u(10)),
            Expanded(
              child: Row(
                children: [
                  Icon(
                    wifi.isConnected
                        ? Icons.wifi_rounded
                        : Icons.wifi_off_rounded,
                    color: accent,
                    size: u(18).clamp(16.0, 18.0),
                  ),
                  SizedBox(width: u(8)),
                  Expanded(
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: u(11.5).clamp(10.5, 11.5),
                      ),
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: u(10)),
            _ConnectBtn(
              uiScale: uiScale,
              accent: accent,
              busy: wifi.isConnecting,
              isConnected: wifi.isConnected,
              onTap: onToggle,
            ),
          ],
        ),
      ),
    );
  }
}

class _BatteryChip extends StatelessWidget {
  final double uiScale;
  final int percent;
  const _BatteryChip({required this.uiScale, required this.percent});

  @override
  Widget build(BuildContext context) {
    double u(double v) => v * uiScale;
    final p = percent.clamp(0, 100);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: u(10).clamp(8.0, 10.0),
        vertical: u(8).clamp(6.0, 8.0),
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Icon(Icons.battery_full_rounded,
              size: u(18).clamp(16.0, 18.0),
              color: Colors.white.withOpacity(0.88)),
          SizedBox(width: u(6)),
          Text('$p%',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: u(12.5).clamp(11.0, 12.5))),
        ],
      ),
    );
  }
}

class _ConnectBtn extends StatelessWidget {
  final double uiScale;
  final Color accent;
  final bool busy;
  final bool isConnected;
  final VoidCallback onTap;

  const _ConnectBtn({
    required this.uiScale,
    required this.accent,
    required this.busy,
    required this.isConnected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    double u(double v) => v * uiScale;
    final label = isConnected ? 'Отключить' : 'Подключить';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: busy ? null : onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: u(12).clamp(10.0, 12.0),
              vertical: u(10).clamp(8.0, 10.0),
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withOpacity(0.26),
                  Colors.white.withOpacity(0.05)
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withOpacity(0.45)),
            ),
            child: busy
                ? SizedBox(
                    width: u(14).clamp(12.0, 14.0),
                    height: u(14).clamp(12.0, 14.0),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(accent),
                    ),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: u(12.0).clamp(10.8, 12.0),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// Map + painter
/// ============================================================================
class _MapCard extends StatelessWidget {
  final double uiScale;
  final ManualMapState state;

  final ValueChanged<Offset> onPan;
  final ValueChanged<double> onZoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onCenter;

  const _MapCard({
    required this.uiScale,
    required this.state,
    required this.onPan,
    required this.onZoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onCenter,
  });

  @override
  Widget build(BuildContext context) {
    double u(double v) => v * uiScale;
    final pad = u(12).clamp(10.0, 12.0);

    return _GlassCard(
      borderColor: Colors.white.withOpacity(0.16),
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Positioned.fill(
                child: _PanZoomSurface(
                  zoom: state.zoom,
                  onPan: onPan,
                  onZoom: onZoom,
                  child: CustomPaint(
                    painter: _GridPainter(uiScale: uiScale, s: state),
                  ),
                ),
              ),
              Positioned(
                right: u(10),
                top: u(10),
                child: Column(
                  children: [
                    _MiniGlassIcon(
                        uiScale: uiScale,
                        icon: Icons.add_rounded,
                        onTap: onZoomIn),
                    SizedBox(height: u(8).clamp(6.0, 8.0)),
                    _MiniGlassIcon(
                        uiScale: uiScale,
                        icon: Icons.remove_rounded,
                        onTap: onZoomOut),
                    SizedBox(height: u(8).clamp(6.0, 8.0)),
                    _MiniGlassIcon(
                        uiScale: uiScale,
                        icon: Icons.center_focus_strong_rounded,
                        onTap: onCenter),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanZoomSurface extends StatefulWidget {
  final double zoom;
  final ValueChanged<Offset> onPan;
  final ValueChanged<double> onZoom;
  final Widget child;

  const _PanZoomSurface({
    required this.zoom,
    required this.onPan,
    required this.onZoom,
    required this.child,
  });

  @override
  State<_PanZoomSurface> createState() => _PanZoomSurfaceState();
}

class _PanZoomSurfaceState extends State<_PanZoomSurface> {
  double _startZoom = 1;
  Offset _lastFocal = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: (d) {
        _startZoom = widget.zoom;
        _lastFocal = d.focalPoint;
      },
      onScaleUpdate: (d) {
        final nextZoom = (_startZoom * d.scale).clamp(0.55, 2.6);
        widget.onZoom(nextZoom);

        final delta = d.focalPoint - _lastFocal;
        _lastFocal = d.focalPoint;
        widget.onPan(delta);
      },
      child: widget.child,
    );
  }
}

class _GridPainter extends CustomPainter {
  final double uiScale;
  final ManualMapState s;

  _GridPainter({required this.uiScale, required this.s});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);

    // масштаб клетки меняется вместе с zoom
    final baseCell = (18 * uiScale).clamp(14.0, 20.0);
    final cell = baseCell * s.zoom;

    Offset w2s(Offset w) => center + s.pan + Offset(w.dx * cell, w.dy * cell);

    canvas.drawRect(
        Offset.zero & size, Paint()..color = Colors.white.withOpacity(0.03));

    final leftWorld = ((-center.dx - s.pan.dx) / cell) - 2;
    final rightWorld = (((size.width - center.dx) - s.pan.dx) / cell) + 2;
    final topWorld = ((-center.dy - s.pan.dy) / cell) - 2;
    final bottomWorld = (((size.height - center.dy) - s.pan.dy) / cell) + 2;

    final x0 = leftWorld.floor().clamp(-2000, 2000);
    final x1 = rightWorld.ceil().clamp(-2000, 2000);
    final y0 = topWorld.floor().clamp(-2000, 2000);
    final y1 = bottomWorld.ceil().clamp(-2000, 2000);

    final gPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1;

    for (int x = x0; x <= x1; x++) {
      canvas.drawLine(w2s(Offset(x.toDouble(), y0.toDouble())),
          w2s(Offset(x.toDouble(), y1.toDouble())), gPaint);
    }
    for (int y = y0; y <= y1; y++) {
      canvas.drawLine(w2s(Offset(x0.toDouble(), y.toDouble())),
          w2s(Offset(x1.toDouble(), y.toDouble())), gPaint);
    }

    final zoneFill = Paint()..color = _kGood.withOpacity(0.20);
    final zoneStroke = Paint()
      ..color = _kGood.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final z in s.zones) {
      final path = _polyPath(z.points, w2s);
      canvas.drawPath(path, zoneFill);
      canvas.drawPath(path, zoneStroke);
    }

    final forbFill = Paint()..color = _kBad.withOpacity(0.22);
    final forbStroke = Paint()
      ..color = _kBad.withOpacity(0.90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final f in s.forbiddens) {
      final path = _polyPath(f.points, w2s);
      canvas.drawPath(path, forbFill);
      canvas.drawPath(path, forbStroke);
    }

    for (final t in s.transitions) {
      _drawDashedPolyline(
        canvas,
        t.map(w2s).toList(growable: false),
        color: _kNeon.withOpacity(0.9),
        stroke: 2,
      );
    }

    if (s.stroke.isNotEmpty && s.kind != null) {
      final pts = s.stroke.map(w2s).toList(growable: false);
      final c = metaOf(s.kind!).color;

      if (s.kind == DrawKind.transition) {
        _drawDashedPolyline(canvas, pts, color: c.withOpacity(0.95), stroke: 2);
      } else {
        final p = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (int i = 1; i < pts.length; i++) {
          p.lineTo(pts[i].dx, pts[i].dy);
        }
        final st = Paint()
          ..color = c.withOpacity(0.92)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2;
        canvas.drawPath(p, st);
      }
    }

    // робот — белый круг
    final rp = w2s(s.robot);
    final r = (6 * uiScale).clamp(5.0, 7.0);
    canvas.drawCircle(
        rp, r + 6, Paint()..color = Colors.black.withOpacity(0.25));
    canvas.drawCircle(rp, r, Paint()..color = Colors.white.withOpacity(0.95));
  }

  Path _polyPath(List<Offset> worldPts, Offset Function(Offset) w2s) {
    final pts = worldPts.map(w2s).toList(growable: false);
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      p.lineTo(pts[i].dx, pts[i].dy);
    }
    p.close();
    return p;
  }

  void _drawDashedPolyline(Canvas canvas, List<Offset> pts,
      {required Color color, required double stroke}) {
    if (pts.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke;

    const dash = 8.0;
    const gap = 6.0;

    for (int i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      final d = (b - a).distance;
      if (d <= 0.001) continue;

      final dir = (b - a) / d;
      double t = 0;
      while (t < d) {
        final seg = math.min(dash, d - t);
        final p1 = a + dir * t;
        final p2 = a + dir * (t + seg);
        canvas.drawLine(p1, p2, paint);
        t += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.s != s || oldDelegate.uiScale != uiScale;
  }
}

/// ============================================================================
/// Sheets
/// ============================================================================
class _NameMapSheet extends ConsumerStatefulWidget {
  const _NameMapSheet();

  @override
  ConsumerState<_NameMapSheet> createState() => _NameMapSheetState();
}

class _NameMapSheetState extends ConsumerState<_NameMapSheet> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = mq.viewInsets.bottom;
    final maxH = mq.size.height * 0.65;

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 14 + bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 6),
          child: _GlassSheet(
            title: 'Название Карты',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Например: Двор',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.70),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _c,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.10)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.10)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: _kNeon),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _c.text),
                    child: const Text('Далее'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModePickSheet extends StatelessWidget {
  final String title;
  final DrawKind? selected;
  final List<KindMeta> kinds;

  const _ModePickSheet({
    required this.title,
    required this.selected,
    required this.kinds,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxH = mq.size.height * 0.7;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          child: _GlassSheet(
            title: title,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < kinds.length; i++) ...[
                  _PickRow(
                    meta: kinds[i],
                    selected: selected == kinds[i].kind,
                    onTap: () => Navigator.pop(context, kinds[i].kind),
                  ),
                  if (i != kinds.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  final KindMeta meta;
  final bool selected;
  final VoidCallback onTap;

  const _PickRow({
    required this.meta,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = meta.color;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.withOpacity(selected ? 0.38 : 0.18)),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.withOpacity(0.14),
                    blurRadius: 18,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: c.withOpacity(selected ? 0.18 : 0.12),
                border:
                    Border.all(color: c.withOpacity(selected ? 0.35 : 0.20)),
              ),
              child: Icon(meta.icon, color: c),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(meta.title,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(
                    meta.subtitle,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withOpacity(0.72),
                      height: 1.15,
                    ),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: selected
                  ? Icon(Icons.check_circle_rounded,
                      key: const ValueKey('on'), color: c)
                  : Icon(Icons.circle_outlined,
                      key: const ValueKey('off'), color: c.withOpacity(0.55)),
            ),
          ],
        ),
      ),
    );
  }
}

/// ============================================================================
/// ✅ Speed Settings sheet
/// ============================================================================
class _SpeedSettingsSheet extends ConsumerWidget {
  const _SpeedSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(manualSpeedProvider).clamp(0.15, 1.20);
    final mode = ref.watch(controlModeProvider);

    String pct(double x) => '${(x * 100).round()}%';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: _GlassSheet(
        title: 'Настройки',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Режим управления
            _GlassCard(
              borderColor: Colors.white.withOpacity(0.18),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.gamepad_rounded, color: Colors.white),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Режим Управления',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _ModeOption(
                            title: 'Джойстик',
                            icon: Icons.control_camera_rounded,
                            selected: mode == ControlMode.joystick,
                            onTap: () => ref
                                .read(controlModeProvider.notifier)
                                .state = ControlMode.joystick,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ModeOption(
                            title: 'Стрелки',
                            icon: Icons.keyboard_arrow_up_rounded,
                            selected: mode == ControlMode.arrows,
                            onTap: () => ref
                                .read(controlModeProvider.notifier)
                                .state = ControlMode.arrows,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Скорость движения
            _GlassCard(
              borderColor: Colors.white.withOpacity(0.18),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.speed_rounded, color: Colors.white),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Скорость Движения',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        Text(
                          pct(v),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.white.withOpacity(0.88),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white.withOpacity(0.12),
                        thumbColor: Colors.white,
                        overlayColor: Colors.white.withOpacity(0.14),
                        trackHeight: 3.2,
                      ),
                      child: Slider(
                        min: 0.15,
                        max: 1.20,
                        value: v,
                        onChanged: (nv) =>
                            ref.read(manualSpeedProvider.notifier).state = nv,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      mode == ControlMode.joystick
                          ? 'Совет: 33% — плавно и точно. 60–90% — быстрее, но сложнее рисовать.'
                          : 'Скорость для команд стрелок (F/B/R/L).',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.70),
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                      softWrap: true,
                      overflow: TextOverflow.visible,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Закрыть'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeOption({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withOpacity(selected ? 0.10 : 0.05),
          border: Border.all(
            color: selected
                ? Colors.white.withOpacity(0.45)
                : Colors.white.withOpacity(0.10),
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: selected ? Colors.white : Colors.white.withOpacity(0.6),
                size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: selected ? Colors.white : Colors.white.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ============================================================================
/// Terminal sheet
/// ============================================================================
class _TerminalSheet extends ConsumerStatefulWidget {
  const _TerminalSheet();

  @override
  ConsumerState<_TerminalSheet> createState() => _TerminalSheetState();
}

class _TerminalSheetState extends ConsumerState<_TerminalSheet> {
  final _c = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(terminalProvider);
    final mq = MediaQuery.of(context);
    final bottom = mq.viewInsets.bottom;
    final maxH = mq.size.height * 0.75;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 14 + bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 6),
          child: _GlassSheet(
            title: 'Терминал',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.black.withOpacity(0.25),
                    border: Border.all(color: Colors.white.withOpacity(0.10)),
                  ),
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(10),
                    itemCount: t.lines.length,
                    itemBuilder: (_, i) {
                      final line = t.lines[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          line,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withOpacity(0.88),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _c,
                        decoration: InputDecoration(
                          hintText: 'Команда…',
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.10)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.10)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: () async {
                        final text = _c.text;
                        _c.clear();
                        await ref.read(terminalProvider.notifier).send(text);
                      },
                      child: const Text('Отправить'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () =>
                        ref.read(terminalProvider.notifier).clear(),
                    child: const Text('Очистить'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// UI helpers
/// ============================================================================
class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color borderColor;

  const _GlassCard({required this.child, required this.borderColor});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassSheet extends StatelessWidget {
  final String title;
  final Widget child;

  const _GlassSheet({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(0.22)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: Colors.white.withOpacity(0.18),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.layers_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final double uiScale;
  final IconData icon;
  final VoidCallback onTap;

  const _IconBtn(
      {required this.uiScale, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    double u(double v) => v * uiScale;
    final s = u(42).clamp(36.0, 42.0);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child:
                Icon(icon, color: Colors.white, size: u(20).clamp(18.0, 20.0)),
          ),
        ),
      ),
    );
  }
}

class _MiniGlassIcon extends StatelessWidget {
  final double uiScale;
  final IconData icon;
  final VoidCallback onTap;

  const _MiniGlassIcon(
      {required this.uiScale, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    double u(double v) => v * uiScale;
    final s = u(44).clamp(38.0, 44.0);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Icon(icon, color: Colors.white.withOpacity(0.92)),
          ),
        ),
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final double uiScale;
  final String text;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _PrimaryBtn({
    required this.uiScale,
    required this.text,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    double u(double v) => v * uiScale;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: enabled ? onTap : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            height: u(54).clamp(44.0, 54.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withOpacity(enabled ? 0.28 : 0.14),
                  Colors.white.withOpacity(0.06)
                ],
              ),
              border:
                  Border.all(color: color.withOpacity(enabled ? 0.55 : 0.25)),
            ),
            child: Center(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: u(14.5).clamp(12.0, 14.5),
                  fontWeight: FontWeight.w900,
                  color: enabled
                      ? Colors.white.withOpacity(0.95)
                      : Colors.white.withOpacity(0.45),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryBtn extends StatelessWidget {
  final double uiScale;
  final double height;
  final String text;
  final VoidCallback onTap;

  const _SecondaryBtn(
      {required this.uiScale,
      required this.height,
      required this.text,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    double u(double v) => v * uiScale;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Colors.white.withOpacity(0.06),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Center(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: u(13.5).clamp(11.5, 13.5),
                  fontWeight: FontWeight.w900,
                  color: Colors.white.withOpacity(0.92),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  final double uiScale;
  final NoticeState n;

  const _NoticeBanner({super.key, required this.uiScale, required this.n});

  @override
  Widget build(BuildContext context) {
    double u(double v) => v * uiScale;

    Color c;
    Color bg;
    switch (n.kind) {
      case NoticeKind.success:
        c = _kGood;
        bg = _kGood.withOpacity(0.16);
        break;
      case NoticeKind.warning:
        c = const Color(0xFFFFD166);
        bg = const Color(0xFFFFD166).withOpacity(0.16);
        break;
      case NoticeKind.danger:
        c = _kBad;
        bg = _kBad.withOpacity(0.18);
        break;
      case NoticeKind.info:
        c = _kNeon;
        bg = _kNeon.withOpacity(0.14);
        break;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.all(u(14).clamp(12.0, 14.0)),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.withOpacity(0.45)),
            boxShadow: [
              BoxShadow(
                  color: c.withOpacity(0.14), blurRadius: 18, spreadRadius: 1)
            ],
          ),
          child: Row(
            children: [
              Container(
                width: u(36).clamp(32.0, 36.0),
                height: u(36).clamp(32.0, 36.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: c.withOpacity(0.14),
                  border: Border.all(color: c.withOpacity(0.22)),
                ),
                child: Icon(Icons.priority_high_rounded,
                    color: c, size: u(20).clamp(18.0, 20.0)),
              ),
              SizedBox(width: u(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.title,
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: u(13.0).clamp(12.0, 13.0))),
                    SizedBox(height: u(5).clamp(4.0, 5.0)),
                    Text(
                      n.message,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withOpacity(0.88),
                        height: 1.15,
                        fontSize: u(12.0).clamp(11.0, 12.0),
                      ),
                      softWrap: true,
                      overflow: TextOverflow.visible,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// Background
/// ============================================================================
class _PremiumBG extends StatelessWidget {
  final bool isConnected;
  const _PremiumBG({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    // Черно-белый фон
    const bg0 = Color(0xFF000000);
    const bg1 = Color(0xFF1A1A1A);
    const bg2 = Color(0xFF2A2A2A);

    // Серый оттенок вместо цветного
    const tintGray = Color(0xFF6E6E6E);

    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-0.9, -1.0),
                end: Alignment(1.0, 1.0),
                colors: [bg0, bg1, bg2],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
        // Светлый градиент сверху
        Positioned.fill(
          child: Opacity(
            opacity: 0.18,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(0.35),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.30],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0.18,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.62, 0.40),
                  radius: 1.30,
                  colors: [tintGray, Colors.transparent],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.0, -0.1),
          radius: 1.15,
          colors: [Colors.transparent, Colors.black.withOpacity(0.58)],
          stops: const [0.55, 1.0],
        ),
      ),
    );
  }
}
