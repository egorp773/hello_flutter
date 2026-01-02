import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/wifi_connection.dart';
import '../../core/map_storage.dart';
import '../../core/route_builder.dart' as route_builder;
import '../manual/manual_control_screen.dart';

class AutoMapScreen extends ConsumerStatefulWidget {
  final String mapId;
  const AutoMapScreen({super.key, required this.mapId});

  @override
  ConsumerState<AutoMapScreen> createState() => _AutoMapScreenState();
}

class _AutoMapScreenState extends ConsumerState<AutoMapScreen> {
  ManualMapState? _mapState;
  bool _isLoading = true;
  String? _error;
  List<Offset> _route = []; // Построенный маршрут

  // Состояние для управления картой
  double _zoom = 1.0;
  Offset _pan = Offset.zero;

  @override
  void initState() {
    super.initState();
    _loadMap();
  }

  Future<void> _loadMap() async {
    // Проверяем подключение перед загрузкой карты
    final wifi = ref.read(wifiConnectionProvider);
    if (!wifi.isConnected && !wifi.isConnecting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(noticeProvider.notifier).show(
              const NoticeState(
                title: 'Не подключено',
                message: 'Подключитесь к роботу для работы с картой.',
                kind: NoticeKind.warning,
              ),
            );
        // Возвращаемся назад
        Future.microtask(() {
          if (mounted) {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/auto');
            }
          }
        });
      });
      return;
    }

    try {
      final map = await MapStorage.loadMap(widget.mapId);
      if (map == null) {
        setState(() {
          _error = 'Карта не найдена';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _mapState = map;
        _zoom = map.zoom;
        _pan = map.pan;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Ошибка загрузки: $e';
        _isLoading = false;
      });
    }
  }

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

  void _buildRoute(BuildContext context, WidgetRef ref) {
    if (_mapState == null) return;

    // Реализуем алгоритм построения маршрута
    final (route, errorCode) =
        route_builder.RouteBuilder.buildRoute(_mapState!);

    if (route.isEmpty) {
      String errorMsg = 'Не удалось построить маршрут. Проверьте карту.';
      if (errorCode != null) {
        switch (errorCode) {
          case route_builder.RouteErrorCode.noStart:
            errorMsg = 'Стартовая точка не задана.';
            break;
          case route_builder.RouteErrorCode.noTransitions:
            errorMsg = 'Нет синих полос (transitions) на карте.';
            break;
          case route_builder.RouteErrorCode.blueIntersectsForbidden:
            errorMsg = 'Синяя полоса пересекает запрещенные зоны.';
            break;
          case route_builder.RouteErrorCode.startToBlueBlocked:
            errorMsg = 'Стартовая точка недостижима до синей полосы.';
            break;
          case route_builder.RouteErrorCode.mowingFailed:
            errorMsg =
                'Не удалось построить маршрут уборки (нет доступных проходов).';
            break;
        }
      }
      ref.read(noticeProvider.notifier).show(
            NoticeState(
              title: 'Ошибка',
              message: errorMsg,
              kind: NoticeKind.danger,
            ),
          );
      return;
    }

    // Сохраняем маршрут в состояние
    setState(() {
      _route = route;
    });

    ref.read(noticeProvider.notifier).show(
          NoticeState(
            title: 'Маршрут построен',
            message: 'Маршрут из ${route.length} точек успешно построен.',
            kind: NoticeKind.success,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final wifi = ref.watch(wifiConnectionProvider);
    final accent = wifi.isConnected ? Colors.white : const Color(0xFF6E6E6E);
    final notice = ref.watch(noticeProvider);
    final media = MediaQuery.of(context);
    final safeTop = media.padding.top;

    return Scaffold(
      body: LayoutBuilder(builder: (context, constraints) {
        final scaleH = constraints.maxHeight / 820.0;
        final scaleW = constraints.maxWidth / 390.0;
        final uiScale = math.min(scaleH, scaleW).clamp(0.70, 1.0);
        double u(double v) => v * uiScale;

        final pad = u(16).clamp(12.0, 16.0);
        final gap = u(10).clamp(8.0, 10.0);

        final topBarH = u(54).clamp(46.0, 54.0);
        final statusH = u(72).clamp(62.0, 72.0);

        return Stack(
          children: [
            Positioned.fill(
              child: _PremiumStaticBackground(isConnected: wifi.isConnected),
            ),
            const Positioned.fill(child: _VignetteOverlay()),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, pad, pad, pad),
                child: Column(
                  children: [
                    SizedBox(
                      height: topBarH,
                      child: Row(
                        children: [
                          _IconBtn(
                            icon: Icons.arrow_back_rounded,
                            onTap: () {
                              if (context.canPop()) {
                                context.pop();
                              } else {
                                context.go('/auto');
                              }
                            },
                          ),
                          SizedBox(width: gap),
                          Expanded(
                            child: Text(
                              _mapState?.mapName ?? 'Загрузка...',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: u(18).clamp(16.0, 18.0),
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: gap),
                    SizedBox(
                      height: statusH,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(u(14).clamp(12.0, 14.0)),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withOpacity(0.12),
                                  Colors.white.withOpacity(0.06),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(22),
                              border:
                                  Border.all(color: accent.withOpacity(0.32)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: u(40).clamp(36.0, 40.0),
                                  height: u(40).clamp(36.0, 40.0),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        accent.withOpacity(0.20),
                                        accent.withOpacity(0.08),
                                      ],
                                    ),
                                    border: Border.all(
                                        color: accent.withOpacity(0.35)),
                                  ),
                                  child: Icon(
                                    wifi.isConnected
                                        ? Icons.wifi_rounded
                                        : Icons.wifi_off_rounded,
                                    color: accent,
                                    size: u(22).clamp(20.0, 22.0),
                                  ),
                                ),
                                SizedBox(width: u(10).clamp(8.0, 10.0)),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        wifi.isConnecting
                                            ? 'Подключение…'
                                            : (wifi.isConnected
                                                ? 'Подключено'
                                                : 'Не подключено'),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: u(14).clamp(12.0, 14.0),
                                          color: wifi.isConnecting
                                              ? Colors.white
                                              : (wifi.isConnected
                                                  ? Colors.green
                                                  : Colors.red),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      SizedBox(height: u(3).clamp(2.0, 3.0)),
                                      Text(
                                        wifi.isConnected
                                            ? 'Робот подключен'
                                            : (wifi.error != null
                                                ? wifi.error!
                                                : 'Подключите робота'),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: u(11).clamp(10.0, 11.0),
                                          color: Colors.white.withOpacity(0.72),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: u(8).clamp(6.0, 8.0)),
                                InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: wifi.isConnecting
                                      ? null
                                      : _toggleWifiConnection,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                          sigmaX: 14, sigmaY: 14),
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: u(12).clamp(10.0, 12.0),
                                          vertical: u(8).clamp(6.0, 8.0),
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
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                              color: accent.withOpacity(0.45)),
                                        ),
                                        child: wifi.isConnecting
                                            ? SizedBox(
                                                width: u(16).clamp(14.0, 16.0),
                                                height: u(16).clamp(14.0, 16.0),
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : Text(
                                                wifi.isConnected
                                                    ? 'Отключить'
                                                    : 'Подключить',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize:
                                                      u(12).clamp(11.0, 12.0),
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: gap),
                    // Карта (уменьшенная)
                    Expanded(
                      flex: 2,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return _isLoading
                              ? Center(
                                  child:
                                      CircularProgressIndicator(color: accent),
                                )
                              : _error != null
                                  ? Center(
                                      child: Text(
                                        _error!,
                                        style: TextStyle(
                                          color: Colors.red.withOpacity(0.8),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    )
                                  : _mapState == null
                                      ? const Center(
                                          child: Text(
                                            'Карта не загружена',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        )
                                      : _MapCardView(
                                          uiScale: uiScale,
                                          state: _mapState!,
                                          mapSize: constraints.biggest,
                                          route: _route,
                                          zoom: _zoom,
                                          pan: _pan,
                                          onPan: (delta) {
                                            setState(() {
                                              _pan = _pan + delta;
                                            });
                                          },
                                          onZoom: (z) {
                                            setState(() {
                                              _zoom = z.clamp(0.55, 48.0);
                                            });
                                          },
                                          onZoomIn: () {
                                            setState(() {
                                              _zoom = (_zoom * 1.12)
                                                  .clamp(0.55, 48.0);
                                            });
                                          },
                                          onZoomOut: () {
                                            setState(() {
                                              _zoom = (_zoom / 1.12)
                                                  .clamp(0.55, 48.0);
                                            });
                                          },
                                          onCenter: () {
                                            // Центрирование на роботе
                                            final center = constraints.biggest
                                                .center(Offset.zero);
                                            final baseCell = (18 * uiScale)
                                                .clamp(14.0, 20.0);
                                            final cell = baseCell * _zoom;
                                            // Текущая позиция робота на экране
                                            final robotScreenPos = center +
                                                _pan +
                                                Offset(
                                                  _mapState!.robot.dx * cell,
                                                  _mapState!.robot.dy * cell,
                                                );
                                            // Вычисляем нужный pan, чтобы робот был в центре
                                            final newPan = _pan -
                                                (robotScreenPos - center);
                                            setState(() {
                                              _pan = newPan;
                                            });
                                          },
                                        );
                        },
                      ),
                    ),
                    SizedBox(height: gap),
                    // Кнопка Построить маршрут
                    _ActionButton(
                      icon: Icons.route_rounded,
                      label: 'Построить маршрут',
                      onTap: () {
                        if (_mapState != null) {
                          _buildRoute(context, ref);
                        }
                      },
                      isPrimary: true,
                    ),
                  ],
                ),
              ),
            ),
            // Уведомления поверх всего
            if (notice != null)
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
                        CurvedAnimation(
                            parent: anim, curve: Curves.easeOutCubic),
                      );
                      final fade = CurvedAnimation(
                          parent: anim, curve: Curves.easeOutCubic);
                      return FadeTransition(
                        opacity: fade,
                        child: SlideTransition(position: slide, child: child),
                      );
                    },
                    child: _NoticeBanner(
                      key: ValueKey(
                          '${notice.kind}-${notice.title}-${notice.message}'),
                      notice: notice,
                    ),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// ============================================================================
/// Баннер уведомлений
/// ============================================================================
class _NoticeBanner extends StatelessWidget {
  final NoticeState notice;

  const _NoticeBanner({super.key, required this.notice});

  @override
  Widget build(BuildContext context) {
    const _kGood = Color(0xFF38F6A7);
    const _kBad = Color(0xFFFF4D6D);
    const _kNeon = Color(0xFF3DE7FF);

    Color c;
    Color bg;
    switch (notice.kind) {
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      notice.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: c,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notice.message,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.88),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const accentWhite = Colors.white;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child: Icon(icon, color: accentWhite),
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// Кнопка действия (Настройки / Построить маршрут)
/// ============================================================================
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    const accentWhite = Colors.white;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isPrimary ? 20 : 16,
              vertical: 16,
            ),
            decoration: BoxDecoration(
              gradient: isPrimary
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.95),
                        Colors.white.withOpacity(0.85),
                      ],
                    )
                  : null,
              color: isPrimary ? null : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isPrimary
                    ? Colors.white.withOpacity(0.95)
                    : accentWhite.withOpacity(0.18),
                width: isPrimary ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isPrimary ? Colors.black : accentWhite,
                  size: isPrimary ? 20 : 18,
                ),
                if (isPrimary) ...[
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: Colors.black.withOpacity(0.92),
                    ),
                  ),
                ] else
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: Center(
                      child: Icon(
                        icon,
                        color: accentWhite,
                        size: 20,
                      ),
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
/// Background (такой же как на главном экране)
/// ============================================================================
class _PremiumStaticBackground extends StatelessWidget {
  final bool isConnected;
  const _PremiumStaticBackground({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    // Черно-белый фон
    const bg0 = Color(0xFF000000);
    const bg1 = Color(0xFF1A1A1A);
    const bg2 = Color(0xFF2A2A2A);

    const tintWhite = Colors.white;
    const tintGray = Color(0xFF6E6E6E);
    final tint = isConnected ? tintWhite : tintGray;

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
            opacity: 0.14,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.2),
                  radius: 1.15,
                  colors: [Colors.white, Colors.transparent],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0.20,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.55, -0.65),
                  radius: 1.10,
                  colors: [Colors.white.withOpacity(0.15), Colors.transparent],
                  stops: const [0.0, 1.0],
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
                  center: const Alignment(0.65, 0.55),
                  radius: 1.25,
                  colors: [tint, Colors.transparent],
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

class _VignetteOverlay extends StatelessWidget {
  const _VignetteOverlay();

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

/// ============================================================================
/// Карта для отображения
/// ============================================================================
class _MapCardView extends StatelessWidget {
  final double uiScale;
  final ManualMapState state;
  final Size mapSize;
  final List<Offset> route;
  final double zoom;
  final Offset pan;
  final ValueChanged<Offset> onPan;
  final ValueChanged<double> onZoom;

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onCenter;

  const _MapCardView({
    required this.uiScale,
    required this.state,
    required this.mapSize,
    this.route = const [],
    required this.zoom,
    required this.pan,
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.16)),
          ),
          child: Padding(
            padding: EdgeInsets.all(pad),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _PanZoomSurface(
                      zoom: zoom,
                      onPan: onPan,
                      onZoom: onZoom,
                      child: CustomPaint(
                        size: mapSize,
                        painter: _GridPainter(
                          uiScale: uiScale,
                          s: state,
                          route: route,
                          zoom: zoom,
                          pan: pan,
                        ),
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
                          onTap: onZoomIn,
                        ),
                        SizedBox(height: u(8).clamp(6.0, 8.0)),
                        _MiniGlassIcon(
                          uiScale: uiScale,
                          icon: Icons.remove_rounded,
                          onTap: onZoomOut,
                        ),
                        SizedBox(height: u(8).clamp(6.0, 8.0)),
                        _MiniGlassIcon(
                          uiScale: uiScale,
                          icon: Icons.center_focus_strong_rounded,
                          onTap: onCenter,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// Отрисовка карты
/// ============================================================================
class _GridPainter extends CustomPainter {
  final double uiScale;
  final ManualMapState s;
  final List<Offset> route;
  final double zoom;
  final Offset pan;

  _GridPainter({
    required this.uiScale,
    required this.s,
    this.route = const [],
    required this.zoom,
    required this.pan,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);

    // масштаб клетки
    final baseCell = (18 * uiScale).clamp(14.0, 20.0);
    final cell = baseCell * zoom;

    Offset w2s(Offset w) => center + pan + Offset(w.dx * cell, w.dy * cell);

    canvas.drawRect(
        Offset.zero & size, Paint()..color = Colors.white.withOpacity(0.03));

    final leftWorld = ((-center.dx - pan.dx) / cell) - 2;
    final rightWorld = (((size.width - center.dx) - pan.dx) / cell) + 2;
    final topWorld = ((-center.dy - pan.dy) / cell) - 2;
    final bottomWorld = (((size.height - center.dy) - pan.dy) / cell) + 2;

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

    const _kGood = Color(0xFF38F6A7);
    const _kBad = Color(0xFFFF4D6D);
    const _kNeon = Color(0xFF3DE7FF);

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

    // Начальная точка — черный квадрат
    if (s.startPoint != null) {
      final sp = w2s(s.startPoint!);
      final squareSize = (12 * uiScale * zoom).clamp(8.0, 16.0);
      final squarePaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromCenter(
          center: sp,
          width: squareSize,
          height: squareSize,
        ),
        squarePaint,
      );
      // Обводка квадрата
      final borderPaint = Paint()
        ..color = Colors.white.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawRect(
        Rect.fromCenter(
          center: sp,
          width: squareSize,
          height: squareSize,
        ),
        borderPaint,
      );
    }

    // Маршрут (если построен)
    if (route.isNotEmpty) {
      final routePaint = Paint()
        ..color = const Color(0xFFFFD700)
            .withOpacity(0.8) // Золотой цвет для маршрута
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final routePath = Path();
      final routePoints = route.map(w2s).toList();
      if (routePoints.isNotEmpty) {
        routePath.moveTo(routePoints.first.dx, routePoints.first.dy);
        for (int i = 1; i < routePoints.length; i++) {
          routePath.lineTo(routePoints[i].dx, routePoints[i].dy);
        }
      }
      canvas.drawPath(routePath, routePaint);
    }

    // робот — белый круг
    final rp = w2s(s.robot);
    final r = (6 * uiScale).clamp(5.0, 7.0);
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
    return oldDelegate.s != s ||
        oldDelegate.uiScale != uiScale ||
        oldDelegate.route.length != route.length ||
        oldDelegate.zoom != zoom ||
        oldDelegate.pan != pan;
  }
}

/// ============================================================================
/// Поверхность для панорамирования и зума
/// ============================================================================
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
        final nextZoom = (_startZoom * d.scale).clamp(0.55, 48.0);
        widget.onZoom(nextZoom);

        final delta = d.focalPoint - _lastFocal;
        _lastFocal = d.focalPoint;
        widget.onPan(delta);
      },
      child: widget.child,
    );
  }
}

/// ============================================================================
/// Мини-иконка для управления картой
/// ============================================================================
class _MiniGlassIcon extends StatelessWidget {
  final double uiScale;
  final IconData icon;
  final VoidCallback onTap;

  const _MiniGlassIcon({
    required this.uiScale,
    required this.icon,
    required this.onTap,
  });

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
