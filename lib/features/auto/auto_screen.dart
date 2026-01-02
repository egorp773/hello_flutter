import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/wifi_connection.dart';
import '../../core/map_storage.dart';
import '../maps/maps_screen.dart';
import '../manual/manual_control_screen.dart';

class AutoScreen extends ConsumerStatefulWidget {
  const AutoScreen({super.key});

  @override
  ConsumerState<AutoScreen> createState() => _AutoScreenState();
}

class _AutoScreenState extends ConsumerState<AutoScreen> {
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
    // Черно-белая цветовая схема
    const accentWhite = Colors.white;
    const accentGray = Color(0xFF6E6E6E);

    final wifi = ref.watch(wifiConnectionProvider);
    final accent = wifi.isConnected ? accentWhite : accentGray;
    final notice = ref.watch(noticeProvider);
    final media = MediaQuery.of(context);
    final safeTop = media.padding.top;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _PremiumStaticBackground(isConnected: wifi.isConnected),
          ),
          const Positioned.fill(child: _VignetteOverlay()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      _IconBtn(
                          icon: Icons.arrow_back_rounded,
                          onTap: () {
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go('/');
                            }
                          }),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Автоматический режим',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Bluetooth статус панель
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: accent.withOpacity(0.32)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: accent.withOpacity(0.12),
                                border:
                                    Border.all(color: accent.withOpacity(0.35)),
                              ),
                              child: Icon(
                                wifi.isConnected
                                    ? Icons.wifi_rounded
                                    : Icons.wifi_off_rounded,
                                color: accent,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    wifi.isConnecting
                                        ? 'Подключение…'
                                        : (wifi.isConnected
                                            ? 'Подключено'
                                            : 'Не подключено'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                      color: wifi.isConnecting
                                          ? Colors.white
                                          : (wifi.isConnected
                                              ? Colors.green
                                              : Colors.red),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    wifi.isConnected
                                        ? 'Робот подключен'
                                        : (wifi.error != null
                                            ? wifi.error!
                                            : 'Подключите робота для автоматического режима'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.72),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: wifi.isConnecting
                                  ? null
                                  : _toggleWifiConnection,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: BackdropFilter(
                                  filter:
                                      ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
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
                                      border: Border.all(
                                          color: accent.withOpacity(0.45)),
                                    ),
                                    child: wifi.isConnecting
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Text(
                                            wifi.isConnected
                                                ? 'Отключить'
                                                : 'Подключить',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
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
                  const SizedBox(height: 14),
                  // Заголовок выбора карты
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: accentWhite.withOpacity(0.18)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.map_rounded,
                              color: accentWhite,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                        child: Text(
                                'Выберите карту, на которой робот начнет уборку',
                          style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  height: 1.2,
                                ),
                              ),
                          ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Список карт
                  Expanded(
                    child: Consumer(
                      builder: (context, ref, _) {
                        final mapsAsync = ref.watch(mapsListProvider);
                        return mapsAsync.when(
                          data: (maps) {
                            if (maps.isEmpty) {
                              return Center(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(22),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                                    child: Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(22),
                                        border: Border.all(
                                          color: accentWhite.withOpacity(0.18),
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.map_outlined,
                                            size: 48,
                                            color: Colors.white.withOpacity(0.4),
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'Нет сохраненных карт',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.82),
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 20),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(18),
                                            child: BackdropFilter(
                                              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                                              child: InkWell(
                                                onTap: () {
                                                  // Устанавливаем флаг для автоматического открытия окна ввода названия
                                                  ref
                                                      .read(autoOpenNameSheetProvider.notifier)
                                                      .state = true;
                                                  context.go('/manual');
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 20,
                                                    vertical: 16,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withOpacity(0.06),
                                                    borderRadius: BorderRadius.circular(18),
                                                    border: Border.all(
                                                      color: accentWhite.withOpacity(0.18),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.add_rounded,
                                                        color: accentWhite,
                                                        size: 20,
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Text(
                                                        'Создать карту',
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.w900,
                                                          fontSize: 15,
                                                          color: accentWhite,
                                                        ),
                                                      ),
                                                    ],
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
                              );
                            }
                            return Column(
                              children: [
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: maps.length,
                                    itemBuilder: (context, index) {
                                      return _AutoMapListItem(
                                        mapInfo: maps[index],
                                        onSelect: (mapInfo) {
                                          // Проверяем подключение перед выбором карты
                                          final wifi = ref.read(wifiConnectionProvider);
                                          if (!wifi.isConnected) {
                                            ref.read(noticeProvider.notifier).show(
                                                  const NoticeState(
                                                    title: 'Подключение',
                                                    message: 'Подключитесь к роботу для выбора карты.',
                                                    kind: NoticeKind.danger,
                                                  ),
                                                );
                                            return;
                                          }
                                          // Переход на экран выбранной карты
                                          context.go('/auto/map/${mapInfo.id}');
                                        },
                                        onRefresh: () => ref.refresh(mapsListProvider),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // Кнопка "Создать карту"
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                                    child: InkWell(
                                      onTap: () {
                                        // Устанавливаем флаг для автоматического открытия окна ввода названия
                                        ref
                                            .read(autoOpenNameSheetProvider.notifier)
                                            .state = true;
                                        context.go('/manual');
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 16,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.06),
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(
                                            color: accentWhite.withOpacity(0.18),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.add_rounded,
                                              color: accentWhite,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              'Создать карту',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 15,
                                                color: accentWhite,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                          loading: () => Center(
                            child: CircularProgressIndicator(color: accentWhite),
                          ),
                          error: (error, stack) => Center(
                            child: Text(
                              'Ошибка загрузки карт: $error',
                              style: TextStyle(
                                color: Colors.red.withOpacity(0.8),
                                fontWeight: FontWeight.w800,
                              ),
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
          // Уведомления поверх всего
          if (notice != null)
            Positioned(
              left: 14,
              right: 14,
              top: safeTop + 80,
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
                  child: _NoticeBanner(
                    key: ValueKey(
                        '${notice.kind}-${notice.title}-${notice.message}'),
                    notice: notice,
                  ),
              ),
            ),
          ),
        ],
      ),
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
          padding: const EdgeInsets.all(14),
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: c.withOpacity(0.14),
                  border: Border.all(color: c.withOpacity(0.22)),
                ),
                child: Icon(Icons.priority_high_rounded, color: c, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(notice.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 13)),
                    const SizedBox(height: 5),
                    Text(
                      notice.message,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withOpacity(0.88),
                        height: 1.15,
                        fontSize: 12,
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
/// Элемент списка карт для автономного режима (такой же как на странице карт)
/// ============================================================================
class _AutoMapListItem extends ConsumerWidget {
  final MapInfo mapInfo;
  final ValueChanged<MapInfo> onSelect;
  final VoidCallback onRefresh;

  const _AutoMapListItem({
    required this.mapInfo,
    required this.onSelect,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const accentWhite = Colors.white;
    final wifi = ref.watch(wifiConnectionProvider);
    final isConnected = wifi.isConnected;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: InkWell(
            onTap: isConnected ? () => onSelect(mapInfo) : null,
            child: Opacity(
              opacity: isConnected ? 1.0 : 0.5,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: accentWhite.withOpacity(0.18),
                  ),
                ),
                child: Row(
                children: [
                  // Превью карты (квадрат)
                  _MapPreview(mapData: mapInfo.mapData),
                  const SizedBox(width: 12),
                  // Название карты
                  Expanded(
                    child: Text(
                      mapInfo.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: accentWhite,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Кнопки редактирования и удаления
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ActionButton(
                        icon: Icons.edit_rounded,
                        color: accentWhite,
                        onTap: () => _editMap(context, ref),
                      ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        icon: Icons.delete_rounded,
                        color: Colors.red,
                        onTap: () => _deleteMap(context, ref),
                      ),
                    ],
                  ),
                ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editMap(BuildContext context, WidgetRef ref) async {
    // Сначала переходим на экран, затем загружаем карту
    if (!context.mounted) return;

    // Переход на экран ручного управления
    context.go('/manual');

    // Загружаем карту после навигации
    final map = await mapInfo.load();
    if (map != null) {
      // Используем Future.microtask для загрузки после завершения навигации
      Future.microtask(() {
        ref.read(manualMapProvider.notifier).loadMap(map);
      });
    }
  }

  Future<void> _deleteMap(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (context) => ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withOpacity(0.18),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red.withOpacity(0.9),
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Удалить карту?',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Карта "${mapInfo.name}" будет удалена безвозвратно.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.82),
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.pop(context, false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.12),
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                'Отмена',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.pop(context, true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.red.withOpacity(0.45),
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                'Удалить',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      final success = await MapStorage.deleteMap(mapInfo.id);
      if (success) {
        onRefresh();
        if (context.mounted) {
          // Используем noticeProvider для красивого уведомления
          ref.read(noticeProvider.notifier).show(
                NoticeState(
                  title: 'Карта удалена',
                  message: 'Карта "${mapInfo.name}" успешно удалена.',
                  kind: NoticeKind.success,
                ),
              );
        }
      }
    }
  }
}

/// ============================================================================
/// Кнопка действия (редактирование/удаление)
/// ============================================================================
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withOpacity(0.25),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          color: color,
          size: 20,
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
/// Превью карты (такой же как на странице карт)
/// ============================================================================
class _MapPreview extends StatelessWidget {
  final Map<String, dynamic> mapData;

  const _MapPreview({required this.mapData});

  @override
  Widget build(BuildContext context) {
    // Создаем временное состояние карты для превью
    try {
      final robotJson = mapData['robot'] as Map<String, dynamic>;
      final robot = Offset(
        (robotJson['x'] as num).toDouble(),
        (robotJson['y'] as num).toDouble(),
      );

      final zones = (mapData['zones'] as List).map((z) {
        final points = (z as List).map((p) {
          final pointJson = p as Map<String, dynamic>;
          return Offset(
            (pointJson['x'] as num).toDouble(),
            (pointJson['y'] as num).toDouble(),
          );
        }).toList();
        return PolyShape(points);
      }).toList();

      final forbiddens = (mapData['forbiddens'] as List).map((f) {
        final points = (f as List).map((p) {
          final pointJson = p as Map<String, dynamic>;
          return Offset(
            (pointJson['x'] as num).toDouble(),
            (pointJson['y'] as num).toDouble(),
          );
        }).toList();
        return PolyShape(points);
      }).toList();

      final transitions = (mapData['transitions'] as List).map((t) {
        return (t as List).map((p) {
          final pointJson = p as Map<String, dynamic>;
          return Offset(
            (pointJson['x'] as num).toDouble(),
            (pointJson['y'] as num).toDouble(),
          );
        }).toList();
      }).toList();

      final previewState = ManualMapState(
        stage: ManualStage.idle,
        mapName: mapData['name'] as String?,
        kind: null,
        robot: robot,
        zoom: 1.0,
        pan: Offset.zero,
        zones: zones,
        forbiddens: forbiddens,
        transitions: transitions,
        stroke: const [],
      );

      return SizedBox(
        width: 80,
        height: 80,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CustomPaint(
            painter: _MapPreviewPainter(state: previewState),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withOpacity(0.12),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      // Если ошибка - показываем заглушку
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withOpacity(0.12),
          ),
        ),
        child: Icon(
          Icons.map_outlined,
          color: Colors.white.withOpacity(0.4),
          size: 32,
        ),
      );
    }
  }
}

class _MapPreviewPainter extends CustomPainter {
  final ManualMapState state;

  _MapPreviewPainter({required this.state});

  @override
  void paint(Canvas canvas, Size size) {
    // Фон
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white.withOpacity(0.03),
    );

    // Собираем все точки для вычисления bounding box
    final allPoints = <Offset>[];
    for (final z in state.zones) {
      allPoints.addAll(z.points);
    }
    for (final f in state.forbiddens) {
      allPoints.addAll(f.points);
    }
    for (final t in state.transitions) {
      allPoints.addAll(t);
    }

    // Если нет элементов, ничего не рисуем
    if (allPoints.isEmpty) return;

    // Вычисляем bounding box
    double minX = allPoints.first.dx;
    double maxX = allPoints.first.dx;
    double minY = allPoints.first.dy;
    double maxY = allPoints.first.dy;

    for (final pt in allPoints) {
      if (pt.dx < minX) minX = pt.dx;
      if (pt.dx > maxX) maxX = pt.dx;
      if (pt.dy < minY) minY = pt.dy;
      if (pt.dy > maxY) maxY = pt.dy;
    }

    final worldWidth = maxX - minX;
    final worldHeight = maxY - minY;

    // Если карта пустая (нулевой размер), ничего не рисуем
    if (worldWidth <= 0.001 || worldHeight <= 0.001) return;

    // Вычисляем масштаб с отступами (padding 10%)
    final padding = 0.1;
    final availableWidth = size.width * (1 - 2 * padding);
    final availableHeight = size.height * (1 - 2 * padding);

    final scaleX = availableWidth / worldWidth;
    final scaleY = availableHeight / worldHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    // Центр карты в мировых координатах
    final worldCenterX = (minX + maxX) / 2;
    final worldCenterY = (minY + maxY) / 2;

    // Центр экрана
    final screenCenter = size.center(Offset.zero);

    // Функция преобразования мировых координат в экранные
    Offset w2s(Offset w) {
      final dx = (w.dx - worldCenterX) * scale;
      final dy = (w.dy - worldCenterY) * scale;
      return screenCenter + Offset(dx, dy);
    }

    // Зоны уборки
    const zoneColor = Color(0xFF38F6A7);
    for (final z in state.zones) {
      final path = _polyPath(z.points, w2s);
      canvas.drawPath(
        path,
        Paint()
          ..color = zoneColor.withOpacity(0.25)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = zoneColor.withOpacity(0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // Запретные зоны
    const forbiddenColor = Color(0xFFFF4D6D);
    for (final f in state.forbiddens) {
      final path = _polyPath(f.points, w2s);
      canvas.drawPath(
        path,
        Paint()
          ..color = forbiddenColor.withOpacity(0.25)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = forbiddenColor.withOpacity(0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // Переходы
    const transitionColor = Color(0xFF3DE7FF);
    for (final t in state.transitions) {
      if (t.length < 2) continue;
      final paint = Paint()
        ..color = transitionColor.withOpacity(0.8)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final pts = t.map(w2s).toList();
      for (int i = 0; i < pts.length - 1; i++) {
        canvas.drawLine(pts[i], pts[i + 1], paint);
      }
    }
  }

  Path _polyPath(List<Offset> worldPts, Offset Function(Offset) w2s) {
    final pts = worldPts.map(w2s).toList();
    if (pts.isEmpty) return Path();
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      p.lineTo(pts[i].dx, pts[i].dy);
    }
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(covariant _MapPreviewPainter oldDelegate) {
    return oldDelegate.state != state;
  }
}
