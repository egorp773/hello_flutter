// lib/core/route_builder.dart
import 'dart:math' as math;
import 'dart:ui';

import '../features/manual/manual_control_screen.dart';

enum RouteErrorCode {
  noStart,
  noTransitions,
  blueIntersectsForbidden,
  startToBlueBlocked,
  mowingFailed,
}

class _Poly {
  final List<Offset> points;
  const _Poly(this.points);
}

class _PickTransitionResult {
  final int transitionIndex;
  final int segIndex; // segment i -> i+1
  final Offset snapPoint; // nearest point on polyline
  const _PickTransitionResult(
      this.transitionIndex, this.segIndex, this.snapPoint);
}

class _Traversal {
  final List<Offset>
      pts; // pts[0] = snapPoint, далее точки синей линии в выбранном направлении
  final List<double> cum; // cum[i] = длина от pts[0] до pts[i]
  const _Traversal(this.pts, this.cum);
  double get total => cum.isEmpty ? 0.0 : cum.last;
}

class _Proj {
  final int segIndex;
  final double t;
  final Offset point;
  final double progress;
  final double dist;
  const _Proj({
    required this.segIndex,
    required this.t,
    required this.point,
    required this.progress,
    required this.dist,
  });
}

class RouteBuilder {
  static (List<Offset>, RouteErrorCode?) buildRoute(
    ManualMapState mapState, {
    double lineStepCells = 0.8,
    double turnRadiusCells = 1.0,
    double cellSize = 1.0,
    bool debugPrint = false,
  }) {
    void log(String s) {
      if (debugPrint) {
        // ignore: avoid_print
        print('[RouteBuilder] $s');
      }
    }

    final start = mapState.startPoint ?? mapState.robot;
    final greens = mapState.zones.map((z) => _Poly(z.points)).toList();
    final reds = mapState.forbiddens.map((f) => _Poly(f.points)).toList();
    final transitions = mapState.transitions;

    if (_pointInAnyPolygon(start, reds)) {
      log('Start inside forbidden');
      return (const [], RouteErrorCode.noStart);
    }
    if (transitions.isEmpty) {
      log('No transitions');
      return (const [], RouteErrorCode.noTransitions);
    }

    // 1) выбираем ближайшую синюю полилинию
    final pick = _pickNearestTransition(start, transitions);
    if (pick == null) return (const [], RouteErrorCode.noTransitions);

    final blue = transitions[pick.transitionIndex];

    // 2) синяя линия не должна залезать в красную
    if (_polylineHitsForbidden(blue, reds)) {
      log('Blue intersects forbidden -> impossible');
      return (const [], RouteErrorCode.blueIntersectsForbidden);
    }

    // 3) подъезд к синей
    final route = <Offset>[start];
    if ((start - pick.snapPoint).distance > 1e-6) {
      if (_segmentHitsForbidden(start, pick.snapPoint, reds, samples: 80)) {
        log('Start->Blue crosses forbidden');
        return (const [], RouteErrorCode.startToBlueBlocked);
      }
      route.add(pick.snapPoint);
    }

    // 4) строим traversal по синей в обе стороны, выбираем направление:
    final forward = _buildTraversalFromSnap(
      blue: blue,
      snapPoint: pick.snapPoint,
      snapSegIndex: pick.segIndex,
      dirForward: true,
    );
    final backward = _buildTraversalFromSnap(
      blue: blue,
      snapPoint: pick.snapPoint,
      snapSegIndex: pick.segIndex,
      dirForward: false,
    );

    final fHit = _firstGreenHitIndexOnTraversal(forward.pts, greens);
    final bHit = _firstGreenHitIndexOnTraversal(backward.pts, greens);

    _Traversal traversal;
    if (greens.isEmpty) {
      traversal = forward.total >= backward.total ? forward : backward;
    } else if (fHit != -1 && bHit != -1) {
      traversal = (fHit <= bHit) ? forward : backward;
    } else if (fHit != -1) {
      traversal = forward;
    } else if (bHit != -1) {
      traversal = backward;
    } else {
      traversal = forward.total >= backward.total ? forward : backward;
    }

    log('Traversal points: ${traversal.pts.length}, total=${traversal.total}');

    // 5) Едем по синей 1-в-1, встречаем зелёные зоны -> делаем змейку -> возвращаемся на синюю -> продолжаем
    final visitedGreen = <int>{};

    Offset cur = route.last;

    // Мы будем идти по traversal сегментами.
    int i = 0;
    while (i < traversal.pts.length - 1) {
      final nextBluePoint = traversal.pts[i + 1];

      // сегмент по синей безопасен (уже проверено), но оставим защиту:
      if (_segmentHitsForbidden(cur, nextBluePoint, reds, samples: 60)) {
        return (
          _simplify(route, minDist: cellSize * 0.05),
          RouteErrorCode.blueIntersectsForbidden
        );
      }

      // Проверяем: входим ли в зелёную на этом синем сегменте
      final hit = _firstGreenHitOnSegment(cur, nextBluePoint, greens);
      if (hit == null) {
        // просто добавляем следующую точку синей
        if ((route.last - nextBluePoint).distance > 1e-6)
          route.add(nextBluePoint);
        cur = nextBluePoint;
        i++;
        continue;
      }

      final zoneIndex = hit.$1;
      final enterPoint = hit.$2;

      // если зона уже убрана — просто проезжаем сегмент синей дальше
      if (visitedGreen.contains(zoneIndex)) {
        if ((route.last - nextBluePoint).distance > 1e-6)
          route.add(nextBluePoint);
        cur = nextBluePoint;
        i++;
        continue;
      }

      // добавляем точку входа в зелёную (она лежит на синем сегменте)
      if ((route.last - enterPoint).distance > 1e-6) route.add(enterPoint);
      cur = enterPoint;

      // делаем змейку
      final mowing = _buildMowingSnake(
        zone: greens[zoneIndex].points,
        forbiddens: reds,
        start: enterPoint,
        step: lineStepCells * cellSize,
        turnRadius: turnRadiusCells * cellSize,
        debugPrint: debugPrint,
      );

      if (mowing.isEmpty) {
        return (
          _simplify(route, minDist: cellSize * 0.05),
          RouteErrorCode.mowingFailed
        );
      }

      // добавляем змейку (без дубля первой точки)
      for (final p in mowing) {
        if (route.isNotEmpty && (route.last - p).distance < 1e-6) continue;
        route.add(p);
      }
      cur = route.last;
      visitedGreen.add(zoneIndex);

      // возвращаемся на синюю:
      // ищем ближайшую точку на текущем/следующих сегментах traversal (начиная с текущего i)
      final rejoin =
          _projectToTraversalFromIndex(cur, traversal, startSegIndex: i);
      if (rejoin == null) {
        // fallback: вернуться в enterPoint (он точно на синей) и продолжить
        if ((route.last - enterPoint).distance > 1e-6) route.add(enterPoint);
        cur = enterPoint;
      } else {
        // соединение cur -> rejoin.point должно быть безопасным
        if (_segmentHitsForbidden(cur, rejoin.point, reds, samples: 90)) {
          if ((route.last - enterPoint).distance > 1e-6) route.add(enterPoint);
          cur = enterPoint;
        } else {
          if ((route.last - rejoin.point).distance > 1e-6)
            route.add(rejoin.point);
          cur = rejoin.point;
          // выставляем i так, чтобы продолжить дальше по синей (на сегменте rejoin)
          i = rejoin.segIndex;
        }
      }

      // после возврата на синюю НЕ увеличиваем i принудительно — цикл сам продолжит
    }

    // 6) Финал: гарантированно добавляем последнюю точку синей (если её нет)
    if (traversal.pts.isNotEmpty) {
      final lastBlue = traversal.pts.last;
      if ((route.last - lastBlue).distance > 1e-6) {
        // это тоже часть синей — безопасно
        route.add(lastBlue);
      }
    }

    return (_simplify(route, minDist: cellSize * 0.05), null);
  }
}

/// ==========================
/// СИНЯЯ ЛИНИЯ / TRAVERSAL
/// ==========================

_Traversal _buildTraversalFromSnap({
  required List<Offset> blue,
  required Offset snapPoint,
  required int snapSegIndex,
  required bool dirForward,
}) {
  final pts = <Offset>[snapPoint];

  if (blue.length < 2) {
    return _Traversal(pts, const [0.0]);
  }

  if (dirForward) {
    // идём к blue[snapSeg+1], потом дальше до конца
    for (int i = snapSegIndex + 1; i < blue.length; i++) {
      pts.add(blue[i]);
    }
  } else {
    // назад: идём к blue[snapSeg], потом к 0
    for (int i = snapSegIndex; i >= 0; i--) {
      pts.add(blue[i]);
    }
  }

  final cum = List<double>.filled(pts.length, 0.0);
  for (int i = 1; i < pts.length; i++) {
    cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).distance;
  }
  return _Traversal(pts, cum);
}

int _firstGreenHitIndexOnTraversal(List<Offset> pts, List<_Poly> greens) {
  if (greens.isEmpty) return -1;
  for (int i = 0; i < pts.length; i++) {
    for (int g = 0; g < greens.length; g++) {
      if (_pointInPolygon(pts[i], greens[g].points)) return i;
    }
  }
  return -1;
}

/// проецируем точку на traversal, но только начиная с segIndex >= startSegIndex
_Proj? _projectToTraversalFromIndex(Offset p, _Traversal t,
    {required int startSegIndex}) {
  if (t.pts.length < 2) return null;

  _Proj? best;

  for (int i = math.max(0, startSegIndex); i < t.pts.length - 1; i++) {
    final a = t.pts[i];
    final b = t.pts[i + 1];
    final proj = _projectPointToSegmentWithT(p, a, b);
    final dist = (p - proj.$1).distance;
    final segLen = (b - a).distance;
    final progress = t.cum[i] + segLen * proj.$2;

    final cand = _Proj(
      segIndex: i,
      t: proj.$2,
      point: proj.$1,
      progress: progress,
      dist: dist,
    );

    if (best == null || cand.dist < best!.dist) best = cand;
  }

  return best;
}

/// ==========================
/// ВХОД В ЗЕЛЁНУЮ НА СЕГМЕНТЕ
/// ==========================

(int, Offset)? _firstGreenHitOnSegment(Offset a, Offset b, List<_Poly> greens) {
  if (greens.isEmpty) return null;

  final len = (b - a).distance;
  final samples = math.max(16, math.min(140, (len / 1.5).ceil()));

  for (int i = 1; i <= samples; i++) {
    final t = i / samples;
    final p = Offset(
      a.dx + (b.dx - a.dx) * t,
      a.dy + (b.dy - a.dy) * t,
    );
    for (int g = 0; g < greens.length; g++) {
      if (_pointInPolygon(p, greens[g].points)) {
        return (g, p);
      }
    }
  }

  return null;
}

/// ==========================
/// ЗМЕЙКА ВНУТРИ ЗОНЫ:
/// - полосы строго параллельны (горизонтальные или вертикальные)
/// - переход между полосами НЕ диагональный (верт/гор + скругление)
/// ==========================

List<Offset> _buildMowingSnake({
  required List<Offset> zone,
  required List<_Poly> forbiddens,
  required Offset start,
  required double step,
  required double turnRadius,
  required bool debugPrint,
}) {
  void log(String s) {
    if (debugPrint) {
      // ignore: avoid_print
      print('[MOW] $s');
    }
  }

  if (zone.length < 3) return const [];
  if (_pointInAnyPolygon(start, forbiddens)) return const [];

  // bbox зелёной зоны
  double minX = double.infinity, maxX = -double.infinity;
  double minY = double.infinity, maxY = -double.infinity;
  for (final p in zone) {
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }

  final width = maxX - minX;
  final height = maxY - minY;

  // выбираем ориентацию с меньшим числом полос
  final horizontalCount = (height / step).ceil() + 1; // линии вдоль X
  final verticalCount = (width / step).ceil() + 1; // линии вдоль Y
  final useHorizontal = horizontalCount <= verticalCount;

  log('useHorizontal=$useHorizontal step=$step');

  final out = <Offset>[start];
  Offset cur = start;
  bool forward = true;

  // Радиус скругления на повороте. Если step маленький, берем r <= step/2,
  // иначе поворот вылезает дальше чем расстояние между полосами.
  final r = math.min(turnRadius, step * 0.5);

  if (useHorizontal) {
    final n = math.max(1, ((maxY - minY) / step).ceil() + 1);

    // Чтобы “не прыгать” на первую полосу, начинаем с ближайшей к старту y
    final k0 = ((start.dy - minY) / step).round().clamp(0, n - 1);

    // порядок полос: от k0 вверх/вниз змейкой
    final order = <int>[];
    for (int d = 0; d < n; d++) {
      final up = k0 - d;
      final down = k0 + d;
      if (d == 0) {
        order.add(k0);
      } else {
        if (up >= 0) order.add(up);
        if (down < n) order.add(down);
      }
      if (order.length >= n) break;
    }

    for (int idx = 0; idx < order.length; idx++) {
      final k = order[idx];
      final y = minY + k * step;

      final segs = _clipHorizontalLineToPolygon(
        y: y,
        zone: zone,
        forbiddens: forbiddens,
      );
      if (segs.isEmpty) continue;

      // Берём все сегменты (если красный вырезал полосу на части),
      // но проходы по ним будут всё равно ГОРИЗОНТАЛЬНЫМИ (параллельными).
      // Сортируем по X.
      segs.sort((a, b) => a.$1.compareTo(b.$1));

      // Выбираем, с какого конца заходить, чтобы меньше “подъезд” от текущей позиции
      // (без диагонали — подъезд делаем ортогонально).
      // Для простоты: если forward, идём слева направо по сегментам; иначе справа налево.
      final segOrder = forward ? segs : segs.reversed.toList();

      for (final s in segOrder) {
        final x1 = forward ? s.$1 : s.$2;
        final x2 = forward ? s.$2 : s.$1;

        final a = Offset(x1, y);
        final b = Offset(x2, y);

        // 1) подъезд к началу сегмента без диагонали: сначала по X или по Y
        _appendOrthMove(out, forbiddens, from: cur, to: a, cornerRadius: r);
        cur = out.last;

        // 2) основной проход — строго горизонтальная прямая
        if (!_appendSafeStraight(out, b, forbiddens)) {
          // если упёрлись в красную (внутри сегмента не должно, но на границах бывает) — продолжаем дальше
          cur = out.last;
          continue;
        }
        cur = out.last;
      }

      // 3) переход на следующую полосу (если есть) — строго вертикально + скругление
      // forward меняем после каждой полосы (классическая змейка)
      forward = !forward;
    }
  } else {
    final n = math.max(1, ((maxX - minX) / step).ceil() + 1);
    final k0 = ((start.dx - minX) / step).round().clamp(0, n - 1);

    final order = <int>[];
    for (int d = 0; d < n; d++) {
      final left = k0 - d;
      final right = k0 + d;
      if (d == 0) {
        order.add(k0);
      } else {
        if (left >= 0) order.add(left);
        if (right < n) order.add(right);
      }
      if (order.length >= n) break;
    }

    for (int idx = 0; idx < order.length; idx++) {
      final k = order[idx];
      final x = minX + k * step;

      final segs = _clipVerticalLineToPolygon(
        x: x,
        zone: zone,
        forbiddens: forbiddens,
      );
      if (segs.isEmpty) continue;

      segs.sort((a, b) => a.$1.compareTo(b.$1));
      final segOrder = forward ? segs : segs.reversed.toList();

      for (final s in segOrder) {
        final y1 = forward ? s.$1 : s.$2;
        final y2 = forward ? s.$2 : s.$1;

        final a = Offset(x, y1);
        final b = Offset(x, y2);

        _appendOrthMove(out, forbiddens, from: cur, to: a, cornerRadius: r);
        cur = out.last;

        if (!_appendSafeStraight(out, b, forbiddens)) {
          cur = out.last;
          continue;
        }
        cur = out.last;
      }

      forward = !forward;
    }
  }

  final cleaned = _simplify(out, minDist: math.max(0.05, step * 0.12));
  if (cleaned.length <= 1) return const [];
  return cleaned;
}

/// Ортогональный ход без диагонали:
/// идём либо (X потом Y), либо (Y потом X) — выбираем безопасный вариант.
/// На углу делаем скругление радиусом cornerRadius (если > 0).
void _appendOrthMove(
  List<Offset> out,
  List<_Poly> forbiddens, {
  required Offset from,
  required Offset to,
  required double cornerRadius,
}) {
  if ((from - to).distance < 1e-6) return;

  final p1 = Offset(to.dx, from.dy); // X потом Y
  final p2 = Offset(from.dx, to.dy); // Y потом X

  bool okPath(List<Offset> pts) {
    for (int i = 0; i < pts.length - 1; i++) {
      if (_segmentHitsForbidden(pts[i], pts[i + 1], forbiddens, samples: 80))
        return false;
    }
    return true;
  }

  List<Offset> pathA = [from, p1, to];
  List<Offset> pathB = [from, p2, to];

  final useA = okPath(pathA);
  final useB = okPath(pathB);

  List<Offset> chosen;
  if (useA && !useB) {
    chosen = pathA;
  } else if (!useA && useB) {
    chosen = pathB;
  } else if (useA && useB) {
    // оба можно — выбираем с меньшей длиной
    final lenA = (from - p1).distance + (p1 - to).distance;
    final lenB = (from - p2).distance + (p2 - to).distance;
    chosen = lenA <= lenB ? pathA : pathB;
  } else {
    // оба режутся красным — ничего не делаем (лучше чем заехать в красную)
    return;
  }

  // Добавляем с возможным скруглением угла:
  // from -> corner -> to
  final corner = chosen[1];

  // Если скруглять нельзя/не нужно:
  if (cornerRadius <= 1e-6 ||
      (from - corner).distance < cornerRadius * 1.2 ||
      (corner - to).distance < cornerRadius * 1.2) {
    _appendSafeStraight(out, corner, forbiddens);
    _appendSafeStraight(out, to, forbiddens);
    return;
  }

  // Скругление: заменяем вершину двумя точками + дуга четверти окружности
  final v1 = (corner - from);
  final v2 = (to - corner);

  // нормализуем направления
  final d1 = Offset(v1.dx / v1.distance, v1.dy / v1.distance);
  final d2 = Offset(v2.dx / v2.distance, v2.dy / v2.distance);

  final a = corner - d1 * cornerRadius;
  final b = corner + d2 * cornerRadius;

  // Проверим, что a->b скругление не залезет в красную: добавим дугу 10 точек
  // Определим центр дуги для осевого поворота на 90°
  // Для осевых ходов центр = пересечение смещённых на r линий.
  // Проще: используем квадратичную аппроксимацию (без идеальной окружности), но без диагонали.
  // Сгенерируем 10 точек Bezier от a до b с контрольной точкой corner.
  final arcPts = <Offset>[];
  const n = 10;
  for (int i = 1; i < n; i++) {
    final t = i / n;
    // Quadratic Bezier: (1-t)^2*A + 2(1-t)t*C + t^2*B
    final u = 1 - t;
    final p = Offset(
      u * u * a.dx + 2 * u * t * corner.dx + t * t * b.dx,
      u * u * a.dy + 2 * u * t * corner.dy + t * t * b.dy,
    );
    arcPts.add(p);
  }

  // Добавляем: from -> a
  _appendSafeStraight(out, a, forbiddens);
  // дуга
  for (final p in arcPts) {
    _appendSafeStraight(out, p, forbiddens);
  }
  // b -> to
  _appendSafeStraight(out, b, forbiddens);
  _appendSafeStraight(out, to, forbiddens);
}

/// добавляет target прямым отрезком, но не заезжает в красное.
/// если пересекает — обрезает до последней безопасной точки.
bool _appendSafeStraight(
    List<Offset> out, Offset target, List<_Poly> forbiddens) {
  if (out.isEmpty) {
    if (!_pointInAnyPolygon(target, forbiddens)) out.add(target);
    return true;
  }

  final from = out.last;
  if ((from - target).distance < 1e-6) return true;

  // target в красном — бинарный поиск последней безопасной точки
  if (_pointInAnyPolygon(target, forbiddens)) {
    final safe = _binarySearchLastSafeOnSegment(from, target, forbiddens);
    if (safe != null && (from - safe).distance > 1e-3) out.add(safe);
    return false;
  }

  // сегмент пересекает красный — тоже обрезаем
  if (_segmentHitsForbidden(from, target, forbiddens, samples: 90)) {
    final safe = _binarySearchLastSafeOnSegment(from, target, forbiddens);
    if (safe != null && (from - safe).distance > 1e-3) out.add(safe);
    return false;
  }

  out.add(target);
  return true;
}

Offset? _binarySearchLastSafeOnSegment(
    Offset a, Offset b, List<_Poly> forbiddens) {
  double lo = 0.0, hi = 1.0;
  Offset best = a;

  for (int it = 0; it < 28; it++) {
    final mid = (lo + hi) * 0.5;
    final p = Offset(
      a.dx + (b.dx - a.dx) * mid,
      a.dy + (b.dy - a.dy) * mid,
    );

    final bad = _pointInAnyPolygon(p, forbiddens);
    if (bad) {
      hi = mid;
    } else {
      best = p;
      lo = mid;
    }
  }

  if ((best - a).distance < 1e-3) return null;
  return best;
}

/// ==========================
/// КЛИППИНГ ЛИНИЙ В ПОЛИГОН
/// ==========================

List<(double, double)> _clipHorizontalLineToPolygon({
  required double y,
  required List<Offset> zone,
  required List<_Poly> forbiddens,
}) {
  final inside = _horizontalIntervalsInsidePolygon(y, zone);
  if (inside.isEmpty) return const [];

  var res = inside;
  for (final f in forbiddens) {
    final cut = _horizontalIntervalsInsidePolygon(y, f.points);
    if (cut.isEmpty) continue;
    res = _subtractIntervals(res, cut);
    if (res.isEmpty) break;
  }

  // небольшая усадка, чтобы не “лизать” границу красного
  const eps = 1e-3;
  final cleaned = <(double, double)>[];
  for (final s in res) {
    final a = s.$1 + eps;
    final b = s.$2 - eps;
    if (b > a) cleaned.add((a, b));
  }
  return cleaned;
}

List<(double, double)> _clipVerticalLineToPolygon({
  required double x,
  required List<Offset> zone,
  required List<_Poly> forbiddens,
}) {
  final inside = _verticalIntervalsInsidePolygon(x, zone);
  if (inside.isEmpty) return const [];

  var res = inside;
  for (final f in forbiddens) {
    final cut = _verticalIntervalsInsidePolygon(x, f.points);
    if (cut.isEmpty) continue;
    res = _subtractIntervals(res, cut);
    if (res.isEmpty) break;
  }

  const eps = 1e-3;
  final cleaned = <(double, double)>[];
  for (final s in res) {
    final a = s.$1 + eps;
    final b = s.$2 - eps;
    if (b > a) cleaned.add((a, b));
  }
  return cleaned;
}

List<(double, double)> _horizontalIntervalsInsidePolygon(
    double y, List<Offset> poly) {
  if (poly.length < 3) return const [];
  final xs = <double>[];

  for (int i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    final y1 = a.dy, y2 = b.dy;

    if ((y1 <= y && y < y2) || (y2 <= y && y < y1)) {
      final t = (y - y1) / (y2 - y1);
      final x = a.dx + (b.dx - a.dx) * t;
      xs.add(x);
    }
  }

  xs.sort();
  if (xs.length < 2) return const [];
  final res = <(double, double)>[];
  for (int i = 0; i + 1 < xs.length; i += 2) {
    final x1 = xs[i];
    final x2 = xs[i + 1];
    if (x2 > x1) res.add((x1, x2));
  }
  return res;
}

List<(double, double)> _verticalIntervalsInsidePolygon(
    double x, List<Offset> poly) {
  if (poly.length < 3) return const [];
  final ys = <double>[];

  for (int i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    final x1 = a.dx, x2 = b.dx;

    if ((x1 <= x && x < x2) || (x2 <= x && x < x1)) {
      final t = (x - x1) / (x2 - x1);
      final y = a.dy + (b.dy - a.dy) * t;
      ys.add(y);
    }
  }

  ys.sort();
  if (ys.length < 2) return const [];
  final res = <(double, double)>[];
  for (int i = 0; i + 1 < ys.length; i += 2) {
    final y1 = ys[i];
    final y2 = ys[i + 1];
    if (y2 > y1) res.add((y1, y2));
  }
  return res;
}

List<(double, double)> _subtractIntervals(
    List<(double, double)> base, List<(double, double)> cut) {
  if (base.isEmpty) return const [];
  if (cut.isEmpty) return base;

  final b = base.toList()..sort((a, c) => a.$1.compareTo(c.$1));
  final c = cut.toList()..sort((a, d) => a.$1.compareTo(d.$1));

  final res = <(double, double)>[];
  int j = 0;

  for (final seg in b) {
    double a = seg.$1;
    double e = seg.$2;

    while (j < c.length && c[j].$2 <= a) {
      j++;
    }

    double cur = a;
    int jj = j;

    while (jj < c.length && c[jj].$1 < e) {
      final ca = c[jj].$1;
      final ce = c[jj].$2;

      if (ce <= cur) {
        jj++;
        continue;
      }
      if (ca > cur) {
        res.add((cur, math.min(ca, e)));
      }
      cur = math.max(cur, ce);
      if (cur >= e) break;
      jj++;
    }

    if (cur < e) res.add((cur, e));
  }

  final out = <(double, double)>[];
  for (final s in res) {
    if (s.$2 - s.$1 > 1e-6) out.add(s);
  }
  return out;
}

/// ==========================
/// ГЕОМЕТРИЯ / ПРОВЕРКИ
/// ==========================

bool _pointInPolygon(Offset point, List<Offset> polygon) {
  if (polygon.length < 3) return false;
  bool inside = false;
  int j = polygon.length - 1;

  for (int i = 0; i < polygon.length; i++) {
    final xi = polygon[i].dx;
    final yi = polygon[i].dy;
    final xj = polygon[j].dx;
    final yj = polygon[j].dy;

    final intersect = ((yi > point.dy) != (yj > point.dy)) &&
        (point.dx < (xj - xi) * (point.dy - yi) / ((yj - yi) + 1e-12) + xi);
    if (intersect) inside = !inside;
    j = i;
  }
  return inside;
}

bool _pointInAnyPolygon(Offset p, List<_Poly> polys) {
  for (final poly in polys) {
    if (_pointInPolygon(p, poly.points)) return true;
  }
  return false;
}

bool _segmentHitsForbidden(Offset a, Offset b, List<_Poly> forbiddens,
    {int samples = 60}) {
  if (forbiddens.isEmpty) return false;
  if (_pointInAnyPolygon(a, forbiddens)) return true;
  if (_pointInAnyPolygon(b, forbiddens)) return true;

  for (int i = 1; i < samples; i++) {
    final t = i / samples;
    final p = Offset(
      a.dx + (b.dx - a.dx) * t,
      a.dy + (b.dy - a.dy) * t,
    );
    if (_pointInAnyPolygon(p, forbiddens)) return true;
  }
  return false;
}

bool _polylineHitsForbidden(List<Offset> line, List<_Poly> forbiddens) {
  if (line.length < 2) return false;
  for (int i = 0; i < line.length - 1; i++) {
    if (_segmentHitsForbidden(line[i], line[i + 1], forbiddens, samples: 80))
      return true;
  }
  return false;
}

(Offset, double) _projectPointToSegmentWithT(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final ap = p - a;
  final abSq = ab.distanceSquared;
  if (abSq < 1e-12) return (a, 0.0);

  final t = (ap.dx * ab.dx + ap.dy * ab.dy) / abSq;
  final tt = t.clamp(0.0, 1.0);
  final c = a + Offset(ab.dx * tt, ab.dy * tt);
  return (c, tt);
}

_PickTransitionResult? _pickNearestTransition(
    Offset start, List<List<Offset>> transitions) {
  int bestIdx = -1;
  int bestSeg = -1;
  Offset bestSnap = Offset.zero;
  double bestD = double.infinity;

  for (int ti = 0; ti < transitions.length; ti++) {
    final t = transitions[ti];
    if (t.length < 2) continue;
    for (int i = 0; i < t.length - 1; i++) {
      final a = t[i];
      final b = t[i + 1];
      final proj = _projectPointToSegmentWithT(start, a, b);
      final d = (start - proj.$1).distance;
      if (d < bestD) {
        bestD = d;
        bestIdx = ti;
        bestSeg = i;
        bestSnap = proj.$1;
      }
    }
  }

  if (bestIdx == -1) return null;
  return _PickTransitionResult(bestIdx, bestSeg, bestSnap);
}

/// ==========================
/// УПРОЩЕНИЕ
/// ==========================

List<Offset> _simplify(List<Offset> pts, {required double minDist}) {
  if (pts.isEmpty) return const [];
  final out = <Offset>[pts.first];
  final min2 = minDist * minDist;

  for (int i = 1; i < pts.length; i++) {
    final a = out.last;
    final b = pts[i];
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    if (dx * dx + dy * dy >= min2) out.add(b);
  }

  // убираем подряд одинаковые
  final out2 = <Offset>[];
  for (final p in out) {
    if (out2.isEmpty || (out2.last - p).distance > 1e-6) out2.add(p);
  }
  return out2;
}
