import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:hello_flutter/core/bt_connection.dart';

/// ============================================================
/// Core picker
/// ============================================================
final controlCoreProvider = StateProvider<String>((ref) => 'Модуль Для Снега');

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _flareCtrl;
  late final AnimationController _robotCtrl;

  late final Animation<double> _flareIntensity;
  late final Animation<double> _robotScale;
  late final Animation<double> _robotGlowBoost;

  @override
  void initState() {
    super.initState();

    _flareCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _flareIntensity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 65,
      ),
    ]).animate(_flareCtrl);

    _robotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );

    _robotScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.03)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.03, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 45,
      ),
    ]).animate(_robotCtrl);

    _robotGlowBoost = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 50,
      ),
    ]).animate(_robotCtrl);
  }

  @override
  void dispose() {
    _flareCtrl.dispose();
    _robotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bt = ref.watch(btConnectionProvider);
    final core = ref.watch(controlCoreProvider);

    ref.listen<BtConnectionState>(btConnectionProvider, (prev, next) {
      if (prev == null) return;
      if (prev.isConnected != next.isConnected && !next.isConnecting) {
        _flareCtrl.forward(from: 0);
        _robotCtrl.forward(from: 0);
      }
    });

    const neonBlue = Color(0xFF3DE7FF);
    const goodGreen = Color(0xFF38F6A7);
    const badRed = Color(0xFFFF4D6D);

    final accent = bt.isConnected ? goodGreen : badRed;

    String statusTitle;
    String statusSubtitle;

    if (!bt.isSupported) {
      statusTitle = 'Bluetooth LE Недоступен';
      statusSubtitle = 'Устройство не поддерживает BLE.';
    } else if (!bt.isBluetoothOn) {
      statusTitle = 'Bluetooth Выключен';
      statusSubtitle = 'Включите Bluetooth и нажмите «Подключить».';
    } else if (bt.isConnected) {
      statusTitle = 'Готов К Работе';
      statusSubtitle =
          'Подключено к ${bt.deviceName}. Можно управлять роботом.';
    } else if (bt.isScanning) {
      statusTitle = 'Поиск Устройств…';
      statusSubtitle = 'Сканируем доступные BLE устройства рядом.';
    } else {
      statusTitle = 'Ожидает Подключения';
      statusSubtitle = 'Подключите робота по Bluetooth, затем выберите режим.';
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final scaleH = constraints.maxHeight / 820.0;
          final scaleW = constraints.maxWidth / 390.0;
          final uiScale = math.min(scaleH, scaleW).clamp(0.78, 1.0);

          double s(double v) => v * uiScale;

          final padH = s(18).clamp(12.0, 18.0);
          final padTop = s(14).clamp(10.0, 14.0);

          final gapS = s(10).clamp(6.0, 10.0);
          final gapM = s(14).clamp(9.0, 14.0);
          final gapL = s(16).clamp(10.0, 16.0);

          final topIconSize = s(44).clamp(36.0, 44.0);
          final topIconGlyph = s(20).clamp(17.0, 20.0);

          final brandSize = s(34).clamp(28.0, 34.0);

          return Stack(
            children: [
              Positioned.fill(
                child: _PremiumStaticBackground(isConnected: bt.isConnected),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _flareCtrl,
                    builder: (_, __) => _ConnectionFlareOverlay(
                      isConnected: bt.isConnected,
                      intensity: _flareIntensity.value,
                    ),
                  ),
                ),
              ),
              const Positioned.fill(child: _VignetteOverlay()),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(padH, padTop, padH, padTop),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // TOP BAR
                      Row(
                        children: [
                          _BrandMark(size: brandSize),
                          SizedBox(width: s(10)),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AutoBot',
                                style: TextStyle(
                                  fontSize: s(20).clamp(16.5, 20.0),
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.35,
                                ),
                              ),
                              SizedBox(height: s(2).clamp(1.0, 2.0)),
                              Row(
                                children: [
                                  Text(
                                    'Premium Control',
                                    style: TextStyle(
                                      fontSize: s(12).clamp(10.0, 12.0),
                                      color: Colors.white.withOpacity(0.68),
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  SizedBox(width: s(8).clamp(6.0, 8.0)),
                                  _BluetoothStatusIndicator(
                                    isConnected: bt.isConnected,
                                    isBusy: bt.isBusy,
                                    deviceName: bt.deviceName,
                                    size: s(14).clamp(12.0, 14.0),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Spacer(),
                          _IconGlassButton(
                            size: topIconSize,
                            glyphSize: topIconGlyph,
                            icon: Icons.map_rounded,
                            tooltip: 'Карты',
                            iconColor: neonBlue,
                            onTap: () => context.go('/maps'),
                          ),
                          SizedBox(width: s(10)),
                          _IconGlassButton(
                            size: topIconSize,
                            glyphSize: topIconGlyph,
                            icon: Icons.tune_rounded,
                            tooltip: 'Настройки',
                            iconColor: neonBlue,
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: Colors.transparent,
                                barrierColor: Colors.black.withOpacity(0.55),
                                builder: (_) => const _QuickSheet(),
                              );
                            },
                          ),
                        ],
                      ),

                      SizedBox(height: gapM),

                      // STATUS CARD
                      _GlassCard(
                        borderColor: accent.withOpacity(0.55),
                        child: Padding(
                          padding: EdgeInsets.all(s(14).clamp(9.0, 14.0)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _BtStatusOrb(
                                size: s(44).clamp(36.0, 44.0),
                                isConnected: bt.isConnected,
                                isBusy: bt.isBusy,
                              ),
                              SizedBox(width: s(12)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    LayoutBuilder(
                                      builder: (context, c) {
                                        final btnW = (c.maxWidth * 0.46)
                                            .clamp(s(155), s(245));
                                        return Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: AdaptiveText(
                                                statusTitle,
                                                maxLines: 2,
                                                minFontSize:
                                                    s(12.0).clamp(10.0, 12.0),
                                                maxFontSize:
                                                    s(17.0).clamp(13.0, 17.0),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.10,
                                                  height: 1.08,
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: s(10)),
                                            _BigConnectButton(
                                              width: btnW,
                                              height: s(52).clamp(42.0, 52.0),
                                              isConnected: bt.isConnected,
                                              isBusy: bt.isBusy,
                                              color: accent,
                                              minText: s(10).clamp(9.0, 10.0),
                                              maxText: s(15).clamp(12.0, 15.0),
                                              onTap: () async {
                                                final ctrl = ref.read(
                                                    btConnectionProvider
                                                        .notifier);

                                                if (bt.isConnected) {
                                                  await ctrl.disconnect();
                                                  return;
                                                }

                                                final picked =
                                                    await showModalBottomSheet<
                                                        BtDeviceInfo>(
                                                  context: context,
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  barrierColor: Colors.black
                                                      .withOpacity(0.55),
                                                  isScrollControlled: true,
                                                  builder: (_) =>
                                                      const _BtDevicePickerSheet(),
                                                );

                                                if (picked != null) {
                                                  await ctrl.connectTo(picked);
                                                }
                                              },
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                    SizedBox(height: s(8).clamp(5.0, 8.0)),
                                    AdaptiveText(
                                      bt.error == null
                                          ? statusSubtitle
                                          : (bt.error!),
                                      maxLines: 3,
                                      minFontSize: s(10.0).clamp(9.0, 10.0),
                                      maxFontSize: s(13.0).clamp(11.0, 13.0),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.05,
                                        height: 1.18,
                                        color: Colors.white.withOpacity(0.76),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(height: gapL),

                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: 360,
                              height: 380,
                              child: RepaintBoundary(
                                child: AnimatedBuilder(
                                  animation: _robotCtrl,
                                  builder: (_, __) {
                                    return Transform.scale(
                                      scale: _robotScale.value,
                                      child: _RobotStable(
                                        neon: neonBlue,
                                        boost: _robotGlowBoost.value,
                                        boostColor:
                                            bt.isConnected ? goodGreen : badRed,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: gapS),

                      Row(
                        children: [
                          Expanded(
                            child: _BigActionCard(
                              uiScale: uiScale,
                              title: 'Ручное Управление',
                              subtitle:
                                  'Джойстик + запись маршрута (реальные команды)',
                              icon: Icons.sports_esports_rounded,
                              border: neonBlue.withOpacity(0.22),
                              glow: neonBlue.withOpacity(0.12),
                              onTap: () => context.go('/manual'),
                            ),
                          ),
                          SizedBox(width: s(12)),
                          Expanded(
                            child: _BigActionCard(
                              uiScale: uiScale,
                              title: 'Автоматический Режим',
                              subtitle: 'Пока заглушка — позже добавим',
                              icon: Icons.route_rounded,
                              border: neonBlue.withOpacity(0.22),
                              glow: neonBlue.withOpacity(0.12),
                              onTap: () => context.go('/auto'),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: gapS),

                      Center(
                        child: _CapsuleGlassButton(
                          uiScale: uiScale,
                          text: core,
                          border: neonBlue.withOpacity(0.22),
                          onTap: () => _showCorePicker(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCorePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (_) {
        final selected = ref.read(controlCoreProvider);
        return _CorePickerSheet(
          selected: selected,
          onSelect: (value) {
            ref.read(controlCoreProvider.notifier).state = value;
            Navigator.pop(context);
          },
        );
      },
    );
  }
}

/// ============================================================
/// Device picker sheet (в вашем стиле)
/// ============================================================
class _BtDevicePickerSheet extends ConsumerStatefulWidget {
  const _BtDevicePickerSheet();

  @override
  ConsumerState<_BtDevicePickerSheet> createState() =>
      _BtDevicePickerSheetState();
}

class _BtDevicePickerSheetState extends ConsumerState<_BtDevicePickerSheet> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(btConnectionProvider.notifier).startScan());
  }

  @override
  Widget build(BuildContext context) {
    final bt = ref.watch(btConnectionProvider);
    const neon = Color(0xFF3DE7FF);

    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 14 + bottom),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: neon.withOpacity(0.22)),
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
                    const Icon(Icons.bluetooth_searching_rounded, color: neon),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Выбор Устройства',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (!bt.isBluetoothOn) ...[
                  Text(
                    'Bluetooth выключен. Включите его и нажмите «Сканировать».',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () => ref
                              .read(btConnectionProvider.notifier)
                              .turnOnAdapterAndroid(),
                          child: const Text('Включить'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => ref
                              .read(btConnectionProvider.notifier)
                              .startScan(),
                          child: const Text('Сканировать'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () => ref
                              .read(btConnectionProvider.notifier)
                              .startScan(),
                          child: Text(
                              bt.isScanning ? 'Сканируем…' : 'Сканировать'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => ref
                              .read(btConnectionProvider.notifier)
                              .stopScan(),
                          child: const Text('Стоп'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                if (bt.error != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      bt.error!,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.78),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 340),
                  child: bt.devices.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: Text(
                            bt.isScanning
                                ? 'Идёт поиск устройств…'
                                : 'Устройств не найдено. Нажмите «Сканировать».',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.70),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: bt.devices.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final d = bt.devices[i];
                            return InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => Navigator.pop(context, d),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(18),
                                  border:
                                      Border.all(color: neon.withOpacity(0.18)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        color: neon.withOpacity(0.12),
                                        border: Border.all(
                                            color: neon.withOpacity(0.20)),
                                      ),
                                      child: const Icon(
                                        Icons.bluetooth_rounded,
                                        color: neon,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            d.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            d.id,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white
                                                  .withOpacity(0.70),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${d.rssi} dBm',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color:
                                                Colors.white.withOpacity(0.88),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Icon(
                                          Icons.wifi_tethering_rounded,
                                          size: 18,
                                          color: Colors.white.withOpacity(
                                            (d.rssi > -60)
                                                ? 0.9
                                                : (d.rssi > -80 ? 0.65 : 0.35),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
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

/// ============================================================
/// AdaptiveText — без троеточий, подбирает размер шрифта
/// ============================================================
class AdaptiveText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final int maxLines;
  final double minFontSize;
  final double maxFontSize;
  final TextAlign align;

  const AdaptiveText(
    this.text, {
    super.key,
    required this.style,
    required this.maxLines,
    required this.minFontSize,
    required this.maxFontSize,
    this.align = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 300.0;

        double lo = minFontSize;
        double hi = maxFontSize;
        double best = minFontSize;

        for (int i = 0; i < 14; i++) {
          final mid = (lo + hi) / 2;

          final tp = TextPainter(
            text: TextSpan(text: text, style: style.copyWith(fontSize: mid)),
            textDirection: TextDirection.ltr,
            maxLines: maxLines,
            textAlign: align,
            textScaler: scaler,
          )..layout(maxWidth: width);

          final fits = !tp.didExceedMaxLines;
          if (fits) {
            best = mid;
            lo = mid;
          } else {
            hi = mid;
          }
        }

        return Text(
          text,
          textAlign: align,
          maxLines: maxLines,
          softWrap: true,
          overflow: TextOverflow.visible,
          style: style.copyWith(fontSize: best),
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        );
      },
    );
  }
}

/// ============================================================
/// BIG Connect Button
/// ============================================================
class _BigConnectButton extends StatelessWidget {
  final double width;
  final double height;
  final bool isConnected;
  final bool isBusy;
  final Color color;
  final double minText;
  final double maxText;
  final VoidCallback onTap;

  const _BigConnectButton({
    required this.width,
    required this.height,
    required this.isConnected,
    required this.isBusy,
    required this.color,
    required this.minText,
    required this.maxText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = isConnected ? 'Отключить' : 'Подключить';

    return SizedBox(
      width: width,
      height: height,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: isBusy ? null : onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withOpacity(0.28),
                    Colors.white.withOpacity(0.06),
                  ],
                ),
                border: Border.all(color: color.withOpacity(0.55)),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.22),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Center(
                child: isBusy
                    ? SizedBox(
                        width: height * 0.34,
                        height: height * 0.34,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: AdaptiveText(
                          label,
                          maxLines: 1,
                          minFontSize: minText,
                          maxFontSize: maxText,
                          align: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.15,
                            height: 1.0,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ============================================================
/// Action card
/// ============================================================
class _BigActionCard extends StatelessWidget {
  final double uiScale;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color border;
  final Color glow;
  final VoidCallback onTap;

  const _BigActionCard({
    required this.uiScale,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.border,
    required this.glow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => v * uiScale;
    final pad = s(14).clamp(9.0, 14.0);
    final minH = s(118).clamp(92.0, 118.0);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minH),
            child: Container(
              padding: EdgeInsets.all(pad),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(color: glow, blurRadius: 18, spreadRadius: 1)
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NeonIconBadge(icon: icon, size: s(44).clamp(36.0, 44.0)),
                  SizedBox(height: s(10).clamp(6.0, 10.0)),
                  AdaptiveText(
                    title,
                    maxLines: 2,
                    minFontSize: s(12.0).clamp(10.5, 12.0),
                    maxFontSize: s(14.5).clamp(12.0, 14.5),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.1,
                      height: 1.10,
                    ),
                  ),
                  SizedBox(height: s(6).clamp(4.0, 6.0)),
                  AdaptiveText(
                    subtitle,
                    maxLines: 2,
                    minFontSize: s(10.5).clamp(9.5, 10.5),
                    maxFontSize: s(12.0).clamp(10.5, 12.0),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      color: Colors.white.withOpacity(0.72),
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

/// ============================================================
/// Background
/// ============================================================
class _PremiumStaticBackground extends StatelessWidget {
  final bool isConnected;
  const _PremiumStaticBackground({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    const bg0 = Color(0xFF070910);
    const bg1 = Color(0xFF0B1426);
    const bg2 = Color(0xFF081633);

    const tintRed = Color(0xFFFF4D6D);
    const tintGreen = Color(0xFF38F6A7);
    final tint = isConnected ? tintGreen : tintRed;

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
            opacity: 0.36,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.55, -0.65),
                  radius: 1.10,
                  colors: [const Color(0xFF3DE7FF), Colors.transparent],
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

class _ConnectionFlareOverlay extends StatelessWidget {
  final bool isConnected;
  final double intensity;

  const _ConnectionFlareOverlay({
    required this.isConnected,
    required this.intensity,
  });

  @override
  Widget build(BuildContext context) {
    if (intensity <= 0.001) return const SizedBox.shrink();

    const green = Color(0xFF38F6A7);
    const red = Color(0xFFFF4D6D);
    final c = isConnected ? green : red;

    final op = (0.60 * intensity).clamp(0.0, 0.60);

    return Opacity(
      opacity: op,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.62, 0.30),
            radius: 1.25,
            colors: [c, Colors.transparent],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
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

/// ============================================================
/// Glass card
/// ============================================================
class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color borderColor;

  const _GlassCard({
    required this.child,
    required this.borderColor,
  });

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

/// ============================================================
/// BT orb
/// ============================================================
class _BtStatusOrb extends StatelessWidget {
  final double size;
  final bool isConnected;
  final bool isBusy;

  const _BtStatusOrb({
    required this.size,
    required this.isConnected,
    required this.isBusy,
  });

  @override
  Widget build(BuildContext context) {
    const good = Color(0xFF38F6A7);
    const bad = Color(0xFFFF4D6D);
    final c = isConnected ? good : bad;

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: c.withOpacity(0.48),
                blurRadius: 22,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Center(
                child: isBusy
                    ? SizedBox(
                        width: size * 0.40,
                        height: size * 0.40,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(c),
                        ),
                      )
                    : Icon(
                        isConnected
                            ? Icons.bluetooth_connected_rounded
                            : Icons.bluetooth_disabled_rounded,
                        size: size * 0.45,
                        color: c,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// ============================================================
/// Robot hero
/// ============================================================
class _RobotStable extends StatelessWidget {
  final Color neon;
  final double boost;
  final Color boostColor;

  const _RobotStable({
    required this.neon,
    required this.boost,
    required this.boostColor,
  });

  @override
  Widget build(BuildContext context) {
    const double glowSize = 320;
    const double robotHeight = 330;

    final extra = (0.22 * boost).clamp(0.0, 0.22);

    return SizedBox(
      width: 360,
      height: 380,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: glowSize,
            height: glowSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: neon.withOpacity(0.20 + extra),
                    blurRadius: 60 + (18 * boost),
                    spreadRadius: 10,
                  ),
                  BoxShadow(
                    color: boostColor.withOpacity(0.13 * boost),
                    blurRadius: 90,
                    spreadRadius: 14,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: robotHeight,
            child: Image.asset(
              'assets/images/robot.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Icon(
                Icons.image_not_supported_outlined,
                size: 46,
                color: Colors.white.withOpacity(0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ============================================================
/// Top UI pieces
/// ============================================================
class _BrandMark extends StatelessWidget {
  final double size;
  const _BrandMark({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3DE7FF), Color(0xFF6D5BFF)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3DE7FF).withOpacity(0.30),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: size * 0.47,
          height: size * 0.47,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Icon(Icons.ac_unit_rounded, size: size * 0.35),
          ),
        ),
      ),
    );
  }
}

class _IconGlassButton extends StatelessWidget {
  final double size;
  final double glyphSize;
  final IconData icon;
  final String tooltip;
  final Color iconColor;
  final VoidCallback onTap;

  const _IconGlassButton({
    required this.size,
    required this.glyphSize,
    required this.icon,
    required this.tooltip,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: Icon(icon, size: glyphSize, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _NeonIconBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  const _NeonIconBadge({required this.icon, required this.size});

  @override
  Widget build(BuildContext context) {
    const neon = Color(0xFF3DE7FF);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            neon.withOpacity(0.30),
            const Color(0xFF6D5BFF).withOpacity(0.12),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            color: neon.withOpacity(0.16),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child:
          Icon(icon, size: size * 0.50, color: Colors.white.withOpacity(0.92)),
    );
  }
}

/// ============================================================
/// Core selector
/// ============================================================
class _CapsuleGlassButton extends StatelessWidget {
  final double uiScale;
  final String text;
  final Color border;
  final VoidCallback onTap;

  const _CapsuleGlassButton({
    required this.uiScale,
    required this.text,
    required this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => v * uiScale;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: s(14).clamp(10.0, 14.0),
              vertical: s(10).clamp(8.0, 10.0),
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: s(12).clamp(10.0, 12.0),
                    letterSpacing: 0.35,
                    color: Colors.white.withOpacity(0.86),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(width: s(8).clamp(6.0, 8.0)),
                Icon(Icons.expand_more_rounded,
                    size: s(18).clamp(16.0, 18.0),
                    color: Colors.white.withOpacity(0.70)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ============================================================
/// Sheets
/// ============================================================
class _CorePickerSheet extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const _CorePickerSheet({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    const neon = Color(0xFF3DE7FF);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: neon.withOpacity(0.22)),
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
                    const Icon(Icons.layers_rounded, color: neon),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Выбор Модуля',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _CoreOption(
                  title: 'Модуль Для Снега',
                  selected: selected == 'Модуль Для Снега',
                  onTap: () => onSelect('Модуль Для Снега'),
                ),
                const SizedBox(height: 10),
                _CoreOption(
                  title: 'Модуль Для Газона',
                  selected: selected == 'Модуль Для Газона',
                  onTap: () => onSelect('Модуль Для Газона'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoreOption extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _CoreOption({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const neon = Color(0xFF3DE7FF);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withOpacity(0.05),
          border: Border.all(
            color: selected ? neon.withOpacity(0.35) : neon.withOpacity(0.14),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: neon.withOpacity(0.14),
                    blurRadius: 18,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: neon.withOpacity(selected ? 0.14 : 0.10),
                border:
                    Border.all(color: neon.withOpacity(selected ? 0.28 : 0.18)),
              ),
              child: Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: neon,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickSheet extends StatelessWidget {
  const _QuickSheet();

  @override
  Widget build(BuildContext context) {
    const neon = Color(0xFF3DE7FF);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: neon.withOpacity(0.22)),
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
                    const Icon(Icons.tune_rounded, color: neon),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Настройки (пока базовые)',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Дальше добавим выбор сервиса/характеристик, автоподключение и телеметрию.',
                  style: TextStyle(color: Colors.white.withOpacity(0.72)),
                ),
                const SizedBox(height: 12),
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
        ),
      ),
    );
  }
}

/// ============================================================
/// Bluetooth Status Indicator
/// ============================================================
class _BluetoothStatusIndicator extends StatelessWidget {
  final bool isConnected;
  final bool isBusy;
  final String? deviceName;
  final double size;

  const _BluetoothStatusIndicator({
    required this.isConnected,
    required this.isBusy,
    this.deviceName,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    const goodGreen = Color(0xFF38F6A7);
    const badRed = Color(0xFFFF4D6D);
    const neonBlue = Color(0xFF3DE7FF);

    final color = isConnected ? goodGreen : (isBusy ? neonBlue : badRed);
    final icon = isConnected
        ? Icons.bluetooth_connected_rounded
        : (isBusy
            ? Icons.bluetooth_searching_rounded
            : Icons.bluetooth_disabled_rounded);

    return Tooltip(
      message: isConnected
          ? (deviceName != null ? 'Подключено: $deviceName' : 'Подключено')
          : (isBusy ? 'Поиск устройств...' : 'Не подключено'),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: size * 0.4,
          vertical: size * 0.2,
        ),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(size * 0.5),
          border: Border.all(
            color: color.withOpacity(0.4),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: size,
              color: color,
            ),
            if (isConnected && deviceName != null) ...[
              SizedBox(width: size * 0.3),
              SizedBox(
                width: size * 4,
                child: Text(
                  deviceName!,
                  style: TextStyle(
                    fontSize: size * 0.75,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
