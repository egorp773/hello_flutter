// lib/core/route_builder.dart
import 'dart:math' as math;
import 'dart:ui';

import '../features/manual/manual_control_screen.dart';

enum RouteErrorCode {
  noStart,
  noTransitions,
  noZones,
  blueNotConnected,
  cannotSliceBlue,
  zoneNoIntersectionWithBlue,
  mowFailed,
}

class RouteBuilder {
  /// Главная функция.
  ///
  /// lineStepCells: шаг между параллельными полосами в "клетках" (у тебя 0.8).
  /// worldCellSize: размер одной "клетки" в world-координатах твоей карты (пиксели/юниты).
  ///   Если сетка на экране имеет шаг 25 — ставь 25.
  static (List<Offset>, RouteErrorCode?) buildRoute(
    ManualMapState mapState, {
    double lineStepCells = 0.8,
    double worldCellSize = 25.0,
    bool debugPrint = false,
  }) {
    void log(String s) {
      if (!debugPrint) return;
      // ignore: avoid_print
      print('[RouteBuilder] $s');
    }

    final start = mapState.startPoint ?? mapState.robot;
    if (start == Offset.zero) return (const [], RouteErrorCode.noStart);

    final transitions = mapState.transitions.where((t) => t.length >= 2).toList();
    if (transitions.isEmpty) return (const [], RouteErrorCode.noTransitions);

    final zones = mapState.zones.map((z) => z.points).where((p) => p.length >= 3).toList();
    if (zones.isEmpty) return (const [], RouteErrorCode.noZones);

    // 1) Собираем ЕДИНЫЙ "синий маршрут" как одну полилинию, соединяя куски по концам.
    final blue = _chainTransitionsIntoSinglePolyline(transitions, start);
    if (blue.length < 2) return (const [], RouteErrorCode.blueNotConnected);

    // 2) Проецируем старт на синюю полилинию и начинаем маршрут с этой точки
    final projStart = _projectPointToPolyline(blue, start);
    if (projStart == null) return (const [], RouteErrorCode.blueNotConnected);

    final blueWithStart = _insertPointIntoPolylineAt(blue, projStart.segIndex, projStart.t, projStart.point);

    // 3) Предрасчёт длины синей полилинии (параметр s вдоль пути)
    final cum = _cumulativeLengths(blueWithStart);

    // 4) Для каждой зелёной зоны найдём первый интервал [sEnter, sExit] где синяя линия внутри зоны
    final zoneHits = <_ZoneHit>[];
    for (int zi = 0; zi < zones.length; zi++) {
      final hit = _findFirstInsideIntervalAlongPolyline(blueWithStart, cum, zones[zi]);
      if (hit != null) {
        zoneHits.add(_ZoneHit(zoneIndex: zi, sEnter: hit.sEnter, sExit: hit.sExit));
      } else {
        // если синяя линия вообще не пересекает зону — по твоим правилам туда не попасть
        log('Zone $zi has no intersection with BLUE.');
        // не фейлим сразу — просто пропустим
      }
    }

    if (zoneHits.isEmpty) {
      // значит есть зоны, но синяя линия их не касается — по заданию робот должен ехать по синей,
      // значит он просто проедет по синей до конца
      final route = <Offset>[];
      route.add(projStart.point);
      route.addAll(_appendWithoutDuplicate(route.last, blueWithStart));
      final cleaned = _simplify(route, minDist: worldCellSize * 0.05);
      return (cleaned, null);
    }

    // 5) Обрабатываем зоны в порядке их появления вдоль синей линии
    zoneHits.sort((a, b) => a.sEnter.compareTo(b.sEnter));

    final route = <Offset>[];

    // Начинаем ровно на синей линии
    route.add(projStart.point);

    double curS = projStart.sAlong(cum, blueWithStart);

    for (final zh in zoneHits) {
      // 5.1) Доезжаем по синей линии от curS до входа в зону (строго по синей полилинии)
      final sliceToEnter = _slicePolylineByS(blueWithStart, cum, curS, zh.sEnter);
      if (sliceToEnter == null) return (const [], RouteErrorCode.cannotSliceBlue);
      route.addAll(_appendWithoutDuplicate(route.last, sliceToEnter));

      final enterPoint = route.last;

      // 5.2) Уборка зоны: только параллельные прямые проходы
      final zonePoly = zones[zh.zoneIndex];
      final mow = _buildParallelMowLines(
        zonePoly,
        startPrefer: enterPoint,
        lineStepWorld: lineStepCells * worldCellSize,
      );
      if (mow.isEmpty) return (const [], RouteErrorCode.mowFailed);

      // Подъезд к первому проходу (коротко)
      route.addAll(_appendWithoutDuplicate(route.last, [mow.first]));
      route.addAll(_appendWithoutDuplicate(route.last, mow));

      // 5.3) После уборки возвращаемся на синюю линию в точку выхода и продолжаем дальше
      final sliceToExitPoint = _pointOnPolylineByS(blueWithStart, cum, zh.sExit);
      if (sliceToExitPoint == null) return (const [], RouteErrorCode.cannotSliceBlue);

      // Подъезд к точке выхода (прямая), затем снова строго по синей
      route.addAll(_appendWithoutDuplicate(route.last, [sliceToExitPoint]));

      curS = zh.sExit;
    }

    // 6) После последней зоны — продолжаем по синей линии до конца
    final sliceToEnd = _slicePolylineByS(blueWithStart, cum, curS, cum.last);
    if (sliceToEnd == null) return (const [], RouteErrorCode.cannotSliceBlue);
    route.addAll(_appendWithoutDuplicate(route.last, sliceToEnd));

    final cleaned = _simplify(route, minDist: worldCellSize * 0.05);
    return (cleaned, null);
  }
}

/// ============================================================================
/// BLUE: склейка transitions в один маршрут (одна полилиния)
/// ============================================================================

List<Offset> _chainTransitionsIntoSinglePolyline(List<List<Offset>> polys, Offset start) {
  // Идея: берём полилинию, которая ближе всего к старту.
  // Потом ищем следующую полилинию, чей конец совпадает с текущим концом (с eps),
  // если надо — разворачиваем её.

  const eps = 6.0; // допуск по world-координатам для "соединения" концов

  double distPointToPolyline(Offset p, List<Offset> poly) {
    double best = double.infinity;
    for (int i = 0; i < poly.length - 1; i++) {
      final q = _closestPointOnSegment(p, poly[i], poly[i + 1]);
      final d = (p - q).distance;
      if (d < best) best = d;
    }
    return best;
  }

  // 1) стартовая полилиния
  int startIdx = 0;
  double best = double.infinity;
  for (int i = 0; i < polys.length; i++) {
    final d = distPointToPolyline(start, polys[i]);
    if (d < best) {
      best = d;
      startIdx = i;
    }
  }

  final remaining = <List<Offset>>[];
  for (int i = 0; i < polys.length; i++) {
    if (i == startIdx) continue;
    remaining.add(polys[i]);
  }

  List<Offset> out = List<Offset>.from(polys[startIdx]);

  bool close(Offset a, Offset b) => (a - b).distance <= eps;

  // 2) жадно цепляем дальше
  while (remaining.isNotEmpty) {
    final tail = out.last;

    int bestJ = -1;
    bool reverse = false;
    double bestD = double.infinity;

    for (int j = 0; j < remaining.length; j++) {
      final p = remaining[j];
      final head = p.first;
      final end = p.last;

      // идеальный случай — совпадение
      if (close(tail, head)) {
        bestJ = j;
        reverse = false;
        bestD = 0;
        break;
      }
      if (close(tail, end)) {
        bestJ = j;
        reverse = true;
        bestD = 0;
        break;
      }

      // если нет точного, возьмём ближайшее (но без "прыжка" — просто прекратим цепочку)
      final d1 = (tail - head).distance;
      final d2 = (tail - end).distance;
      final d = math.min(d1, d2);
      if (d < bestD) {
        bestD = d;
        bestJ = j;
        reverse = d2 < d1;
      }
    }

    // если следующий кусок далеко — прекращаем (иначе получится "прыжок" не по синей)
    if (bestJ == -1 || bestD > eps) break;

    final nxt = remaining.removeAt(bestJ);
    final toAdd = reverse ? nxt.reversed.toList() : nxt;

    // добавляем без дублирования стыка
    if ((out.last - toAdd.first).distance < 1e-6) {
      out.addAll(toAdd.skip(1));
    } else {
      out.addAll(toAdd);
    }
  }

  return out;
}

/// ============================================================================
/// BLUE: работа с параметром s вдоль полилинии
/// ============================================================================

List<double> _cumulativeLengths(List<Offset> poly) {
  final cum = <double>[0.0];
  double s = 0;
  for (int i = 0; i < poly.length - 1; i++) {
    s += (poly[i + 1] - poly[i]).distance;
    cum.add(s);
  }
  return cum;
}

Offset? _pointOnPolylineByS(List<Offset> poly, List<double> cum, double s) {
  if (s <= 0) return poly.first;
  if (s >= cum.last) return poly.last;

  int i = _lowerBound(cum, s) - 1;
  if (i < 0) i = 0;
  if (i >= poly.length - 1) i = poly.length - 2;

  final s0 = cum[i];
  final s1 = cum[i + 1];
  final segLen = (s1 - s0);
  final t = segLen <= 1e-9 ? 0.0 : (s - s0) / segLen;

  return Offset(
    poly[i].dx + (poly[i + 1].dx - poly[i].dx) * t,
    poly[i].dy + (poly[i + 1].dy - poly[i].dy) * t,
  );
}

List<Offset>? _slicePolylineByS(List<Offset> poly, List<double> cum, double sFrom, double sTo) {
  if (sTo < sFrom) {
    final tmp = sFrom;
    sFrom = sTo;
    sTo = tmp;
  }

  final a = _pointOnPolylineByS(poly, cum, sFrom);
  final b = _pointOnPolylineByS(poly, cum, sTo);
  if (a == null || b == null) return null;

  final out = <Offset>[a];

  // добавим все вершины между
  for (int i = 0; i < poly.length; i++) {
    final si = i == 0 ? 0.0 : cum[i];
    if (si > sFrom + 1e-6 && si < sTo - 1e-6) {
      out.add(poly[i]);
    }
  }

  out.add(b);
  return out;
}

int _lowerBound(List<double> a, double x) {
  int l = 0, r = a.length;
  while (l < r) {
    final m = (l + r) >> 1;
    if (a[m] < x) {
      l = m + 1;
    } else {
      r = m;
    }
  }
  return l;
}

/// ============================================================================
/// GREEN: найти первый интервал, где синяя линия внутри зоны
/// ============================================================================

_InsideInterval? _findFirstInsideIntervalAlongPolyline(
  List<Offset> poly,
  List<double> cum,
  List<Offset> zone,
) {
  const epsS = 1e-6;

  final insideRanges = <_InsideInterval>[];

  for (int i = 0; i < poly.length - 1; i++) {
    final a = poly[i];
    final b = poly[i + 1];
    final len = (b - a).distance;
    if (len < 1e-9) continue;

    final insideA = _pointInPolygon(a, zone);
    final insideB = _pointInPolygon(b, zone);

    // Найдём точки пересечения сегмента с границей полигона (t в [0..1])
    final ts = _segmentPolygonIntersectionTs(a, b, zone);
    ts.sort();

    bool inside = insideA;
    double prevT = 0.0;

    void addRange(double t0, double t1) {
      if (t1 <= t0) return;
      final s0 = cum[i] + t0 * len;
      final s1 = cum[i] + t1 * len;
      insideRanges.add(_InsideInterval(sEnter: s0, sExit: s1));
    }

    if (ts.isEmpty) {
      if (insideA && insideB) {
        addRange(0.0, 1.0);
      }
    } else {
      for (final tInt in ts) {
        if (inside) addRange(prevT, tInt);
        inside = !inside;
        prevT = tInt;
      }
      if (inside) addRange(prevT, 1.0);
    }
  }

  if (insideRanges.isEmpty) return null;

  // Мержим соседние
  insideRanges.sort((x, y) => x.sEnter.compareTo(y.sEnter));
  final merged = <_InsideInterval>[];
  _InsideInterval cur = insideRanges.first;
  for (int i = 1; i < insideRanges.length; i++) {
    final nxt = insideRanges[i];
    if ((nxt.sEnter - cur.sExit).abs() <= epsS) {
      cur = _InsideInterval(sEnter: cur.sEnter, sExit: math.max(cur.sExit, nxt.sExit));
    } else {
      merged.add(cur);
      cur = nxt;
    }
  }
  merged.add(cur);

  // Берём первый интервал (самый ранний вход)
  return merged.first;
}

class _InsideInterval {
  final double sEnter;
  final double sExit;
  const _InsideInterval({required this.sEnter, required this.sExit});
}

class _ZoneHit {
  final int zoneIndex;
  final double sEnter;
  final double sExit;
  const _ZoneHit({required this.zoneIndex, required this.sEnter, required this.sExit});
}

/// ============================================================================
/// GREEN: параллельные прямые линии (сканлайны)
/// ============================================================================

List<Offset> _buildParallelMowLines(
  List<Offset> zone, {
  required Offset startPrefer,
  required double lineStepWorld,
}) {
  final bb = _bbox(zone);

  // Выбираем ориентацию: если шире — горизонтальные линии, иначе вертикальные
  final horizontal = bb.width >= bb.height;

  final passes = <_Pass>[]; // каждый проход — один отрезок

  if (horizontal) {
    final yMin = bb.top;
    final yMax = bb.bottom;

    final y0 = _clamp(startPrefer.dy, yMin, yMax);
    final ys = _scanPositions(y0, yMin, yMax, lineStepWorld);

    for (final y in ys) {
      final segs = _intersectPolygonWithHorizontal(zone, y);
      for (final s in segs) {
        final a = Offset(s.x1, y);
        final b = Offset(s.x2, y);
        if ((b - a).distance > lineStepWorld * 0.2) {
          passes.add(_Pass(a, b, key: y));
        }
      }
    }
  } else {
    final xMin = bb.left;
    final xMax = bb.right;

    final x0 = _clamp(startPrefer.dx, xMin, xMax);
    final xs = _scanPositions(x0, xMin, xMax, lineStepWorld);

    for (final x in xs) {
      final segs = _intersectPolygonWithVertical(zone, x);
      for (final s in segs) {
        final a = Offset(x, s.y1);
        final b = Offset(x, s.y2);
        if ((b - a).distance > lineStepWorld * 0.2) {
          passes.add(_Pass(a, b, key: x));
        }
      }
    }
  }

  if (passes.isEmpty) return const [];

  // Сортируем проходы по "полосам"
  passes.sort((a, b) => a.key.compareTo(b.key));

  // Делаем змейку: чередуем направление каждого прохода
  final out = <Offset>[];

  // Стартуем с прохода, который ближе к startPrefer
  int firstIdx = 0;
  double best = double.infinity;
  for (int i = 0; i < passes.length; i++) {
    final mid = Offset((passes[i].a.dx + passes[i].b.dx) * 0.5, (passes[i].a.dy + passes[i].b.dy) * 0.5);
    final d = (mid - startPrefer).distance;
    if (d < best) {
      best = d;
      firstIdx = i;
    }
  }

  final ordered = <_Pass>[];
  ordered.addAll(passes.sublist(firstIdx));
  ordered.addAll(passes.sublist(0, firstIdx));

  bool forward = true;

  // Первый проход
  out.add(ordered.first.a);
  out.add(ordered.first.b);

  for (int i = 1; i < ordered.length; i++) {
    forward = !forward;

    final p = ordered[i];
    final s = forward ? p.a : p.b;
    final e = forward ? p.b : p.a;

    // перемычка к началу следующего прохода (да, она не параллельна проходам,
    // но без неё маршрут не будет непрерывным)
    out.add(s);
    out.add(e);
  }

  return _simplify(out, minDist: lineStepWorld * 0.08);
}

class _Pass {
  final Offset a;
  final Offset b;
  final double key; // y (для горизонтальных) или x (для вертикальных)
  _Pass(this.a, this.b, {required this.key});
}

/// ============================================================================
/// Геометрия: пересечения, bbox, point-in-polygon
/// ============================================================================

class _BBox {
  final double left, top, right, bottom;
  const _BBox(this.left, this.top, this.right, this.bottom);
  double get width => right - left;
  double get height => bottom - top;
}

_BBox _bbox(List<Offset> poly) {
  double minX = double.infinity, minY = double.infinity;
  double maxX = -double.infinity, maxY = -double.infinity;
  for (final p in poly) {
    minX = math.min(minX, p.dx);
    minY = math.min(minY, p.dy);
    maxX = math.max(maxX, p.dx);
    maxY = math.max(maxY, p.dy);
  }
  return _BBox(minX, minY, maxX, maxY);
}

double _clamp(double v, double a, double b) => math.max(a, math.min(b, v));

List<double> _scanPositions(double start, double min, double max, double step) {
  final out = <double>[start];
  double p = start - step;
  while (p >= min) {
    out.add(p);
    p -= step;
  }
  p = start + step;
  while (p <= max) {
    out.add(p);
    p += step;
  }
  out.sort();
  return out;
}

/// Пересечение полигона с горизонталью y=const → интервалы по x
List<_Seg1D> _intersectPolygonWithHorizontal(List<Offset> poly, double y) {
  final xs = <double>[];
  for (int i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    final y1 = a.dy, y2 = b.dy;
    if ((y1 <= y && y2 > y) || (y2 <= y && y1 > y)) {
      final t = (y - y1) / (y2 - y1);
      final x = a.dx + (b.dx - a.dx) * t;
      xs.add(x);
    }
  }
  xs.sort();
  final out = <_Seg1D>[];
  for (int i = 0; i + 1 < xs.length; i += 2) {
    out.add(_Seg1D(xs[i], xs[i + 1]));
  }
  return out;
}

/// Пересечение полигона с вертикалью x=const → интервалы по y
List<_Seg1D> _intersectPolygonWithVertical(List<Offset> poly, double x) {
  final ys = <double>[];
  for (int i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    final x1 = a.dx, x2 = b.dx;
    if ((x1 <= x && x2 > x) || (x2 <= x && x1 > x)) {
      final t = (x - x1) / (x2 - x1);
      final y = a.dy + (b.dy - a.dy) * t;
      ys.add(y);
    }
  }
  ys.sort();
  final out = <_Seg1D>[];
  for (int i = 0; i + 1 < ys.length; i += 2) {
    out.add(_Seg1D(ys[i], ys[i + 1], vertical: true));
  }
  return out;
}

class _Seg1D {
  final double a;
  final double b;
  final bool vertical;
  _Seg1D(this.a, this.b, {this.vertical = false});
  double get x1 => math.min(a, b);
  double get x2 => math.max(a, b);
  double get y1 => math.min(a, b);
  double get y2 => math.max(a, b);
}

bool _pointInPolygon(Offset p, List<Offset> poly) {
  bool inside = false;
  int j = poly.length - 1;
  for (int i = 0; i < poly.length; i++) {
    final xi = poly[i].dx, yi = poly[i].dy;
    final xj = poly[j].dx, yj = poly[j].dy;
    final intersect = ((yi > p.dy) != (yj > p.dy)) &&
        (p.dx < (xj - xi) * (p.dy - yi) / ((yj - yi) + 1e-12) + xi);
    if (intersect) inside = !inside;
    j = i;
  }
  return inside;
}

/// Возвращает список t (0..1), где сегмент AB пересекает границу полигона.
List<double> _segmentPolygonIntersectionTs(Offset a, Offset b, List<Offset> poly) {
  final ts = <double>[];

  for (int i = 0; i < poly.length; i++) {
    final c = poly[i];
    final d = poly[(i + 1) % poly.length];
    final inter = _segmentSegmentIntersection(a, b, c, d);
    if (inter != null) {
      final t = inter.$1;
      if (t > 1e-9 && t < 1.0 - 1e-9) {
        ts.add(t);
      }
    }
  }

  // убрать почти-дубликаты
  ts.sort();
  final out = <double>[];
  for (final t in ts) {
    if (out.isEmpty || (t - out.last).abs() > 1e-6) out.add(t);
  }
  return out;
}

/// Пересечение отрезков AB и CD.
/// Возвращает (t, u), где:
///   A + t*(B-A) = C + u*(D-C)
/// t и u в [0..1] при пересечении в пределах отрезков.
(double, double)? _segmentSegmentIntersection(Offset a, Offset b, Offset c, Offset d) {
  final r = b - a;
  final s = d - c;

  final rxs = r.dx * s.dy - r.dy * s.dx;
  if (rxs.abs() < 1e-12) return null; // параллельны/коллинеарны

  final qp = c - a;
  final t = (qp.dx * s.dy - qp.dy * s.dx) / rxs;
  final u = (qp.dx * r.dy - qp.dy * r.dx) / rxs;

  if (t >= 0 && t <= 1 && u >= 0 && u <= 1) {
    return (t, u);
  }
  return null;
}

Offset _closestPointOnSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final ap = p - a;
  final abSq = ab.distanceSquared;
  if (abSq < 1e-12) return a;
  final t = (ap.dx * ab.dx + ap.dy * ab.dy) / abSq;
  final tc = t.clamp(0.0, 1.0);
  return a + ab * tc;
}

class _ProjectionOnPolyline {
  final int segIndex;
  final double t;
  final Offset point;
  _ProjectionOnPolyline(this.segIndex, this.t, this.point);

  double sAlong(List<double> cum, List<Offset> poly) {
    final a = poly[segIndex];
    final b = poly[segIndex + 1];
    final len = (b - a).distance;
    return cum[segIndex] + t * len;
  }
}

_ProjectionOnPolyline? _projectPointToPolyline(List<Offset> poly, Offset p) {
  double best = double.infinity;
  int bestI = -1;
  double bestT = 0;
  Offset bestPt = Offset.zero;

  for (int i = 0; i < poly.length - 1; i++) {
    final a = poly[i];
    final b = poly[i + 1];
    final q = _closestPointOnSegment(p, a, b);
    final d = (p - q).distance;
    if (d < best) {
      best = d;
      bestI = i;
      // восстановим t
      final ab = b - a;
      final abSq = ab.distanceSquared;
      final t = abSq < 1e-12 ? 0.0 : ((q - a).dx * ab.dx + (q - a).dy * ab.dy) / abSq;
      bestT = t.clamp(0.0, 1.0);
      bestPt = q;
    }
  }

  if (bestI == -1) return null;
  return _ProjectionOnPolyline(bestI, bestT, bestPt);
}

/// Вставляет точку P в полилинию на сегменте segIndex (с параметром t).
/// Возвращает новую полилинию.
List<Offset> _insertPointIntoPolylineAt(List<Offset> poly, int segIndex, double t, Offset p) {
  // если p почти совпадает с концами — просто вернём как есть
  if ((p - poly[segIndex]).distance < 1e-6) return poly;
  if ((p - poly[segIndex + 1]).distance < 1e-6) return poly;

  final out = <Offset>[];
  for (int i = 0; i <= segIndex; i++) out.add(poly[i]);
  out.add(p);
  for (int i = segIndex + 1; i < poly.length; i++) out.add(poly[i]);
  return out;
}

/// Удаляет дубликаты при добавлении
List<Offset> _appendWithoutDuplicate(Offset last, List<Offset> pts) {
  final out = <Offset>[];
  for (final p in pts) {
    if ((p - last).distance < 1e-6) continue;
    out.add(p);
    last = p;
  }
  return out;
}

List<Offset> _simplify(List<Offset> pts, {required double minDist}) {
  if (pts.isEmpty) return const [];
  final out = <Offset>[pts.first];
  for (int i = 1; i < pts.length; i++) {
    if ((pts[i] - out.last).distance >= minDist) out.add(pts[i]);
  }
  return out;
}
