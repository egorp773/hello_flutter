// lib/core/route_builder.dart
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import '../features/manual/manual_control_screen.dart';

// ==== ОПРЕДЕЛЕНИЯ ТИПОВ ====
enum CellType { empty, red, green, blue }

class Pt {
  final double x;
  final double y;
  const Pt(this.x, this.y);
}

class I2 {
  final int x;
  final int y;
  const I2(this.x, this.y);
}

class GridMap {
  final int w;
  final int h;
  final double cellSize;
  final double minX;
  final double minY;
  final CellType Function(int x, int y) at;

  GridMap({
    required this.w,
    required this.h,
    required this.cellSize,
    required this.minX,
    required this.minY,
    required this.at,
  });
}

// ==== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ====
bool isBlue(CellType t) => t == CellType.blue;
bool isGreen(CellType t) => t == CellType.green;
bool isForbidden(CellType t) => t == CellType.red;

Pt cellCenter(GridMap g, int cx, int cy) {
  return Pt(
    g.minX + cx * g.cellSize + g.cellSize * 0.5,
    g.minY + cy * g.cellSize + g.cellSize * 0.5,
  );
}

I2 worldToCell(GridMap g, Pt p) {
  return I2(
    ((p.x - g.minX) / g.cellSize).floor(),
    ((p.y - g.minY) / g.cellSize).floor(),
  );
}

bool _inBounds(GridMap g, int x, int y) => x >= 0 && y >= 0 && x < g.w && y < g.h;

/// allowBlue=true => green+blue разрешены, red запрещён
bool isPointSafe(GridMap g, Pt p, {required bool allowBlue}) {
  final c = worldToCell(g, p);
  if (!_inBounds(g, c.x, c.y)) return false;
  final t = g.at(c.x, c.y);
  if (isForbidden(t)) return false;
  if (isGreen(t)) return true;
  if (allowBlue && isBlue(t)) return true;
  return false;
}

// ==== КОДЫ ОШИБОК ====
enum RouteErrorCode {
  noStart,
  greenEmpty,
  noBlue,
  startNotBlueOrGreen,
  buildFailed,
}

class RouteBuilder {
  static ManualMapState? _currentMapState;

  /// Главный вход: возвращает (маршрут, ошибка)
  static (List<Offset>, RouteErrorCode?) buildRoute(
    ManualMapState mapState, {
    double lineStepCells = 0.8,
    double turnRadiusCells = 1.0,
    bool allowBlue = true,
    bool debugPrint = false,
  }) {
    _currentMapState = mapState;

    void log(String s) {
      if (debugPrint) {
        // ignore: avoid_print
        print('[RouteBuilder] $s');
      }
    }

    final g = _convertToGridMap(mapState);
    if (g == null) return (const [], RouteErrorCode.noStart);

    final startWorld = mapState.startPoint != null
        ? Pt(mapState.startPoint!.dx, mapState.startPoint!.dy)
        : Pt(mapState.robot.dx, mapState.robot.dy);

    // СНАП старта на ближайшую blue/green клетку (если вдруг попал в empty)
    final snapped = _snapToNearestAllowed(g, startWorld);
    final start = snapped ?? startWorld;

    // Если синей нет — работаем только по зелёным (тогда детуры не нужны)
    final hasBlue = mapState.transitions.isNotEmpty &&
        mapState.transitions.any((p) => p.length >= 2);

    // Параметр плотности точек на синей: чем меньше — тем “ровнее 1в1”
    final blueStepWorld = g.cellSize * 0.35;

    // 1) если есть синяя — строим “синяя магистраль + детуры в зелёное + продолжение”
    if (hasBlue) {
      final pts = _buildRouteBlueWithMowDetours(
        g,
        mapState,
        start,
        blueStepWorld: blueStepWorld,
        lineStepCells: lineStepCells,
        turnRadiusCells: turnRadiusCells,
        allowBlue: allowBlue,
        log: log,
      );

      if (pts.isNotEmpty) {
        final res = pts.map((p) => Offset(p.x, p.y)).toList();
        return (res, null);
      }

      return (const [], RouteErrorCode.buildFailed);
    }

    // 2) если синей нет — просто змейка по всем зелёным компонентам
    final greenComponents = _findGreenComponents(g);
    if (greenComponents.isEmpty) return (const [], RouteErrorCode.greenEmpty);

    final out = <Pt>[start];
    Pt cur = start;

    for (final comp in greenComponents) {
      final mow = _buildMowPathForComponent(
        g,
        comp,
        start: cur,
        lineStepCells: lineStepCells,
        turnRadiusCells: turnRadiusCells,
        allowBlue: allowBlue,
        log: log,
        mapState: mapState,
      );
      if (mow.isNotEmpty) {
        if (_samePt(out.last, mow.first)) {
          out.addAll(mow.skip(1));
        } else {
          out.addAll(mow);
        }
        cur = out.last;
      }
    }

    final cleaned = _simplify(out, minDist: g.cellSize * 0.10);
    return (cleaned.map((p) => Offset(p.x, p.y)).toList(), null);
  }

  // =============================================================
  // MAP -> GRID
  // =============================================================

  static GridMap? _convertToGridMap(ManualMapState mapState) {
    // границы
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;

    void addPoint(Offset p) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    for (final z in mapState.zones) {
      for (final p in z.points) addPoint(p);
    }
    for (final f in mapState.forbiddens) {
      for (final p in f.points) addPoint(p);
    }
    for (final tr in mapState.transitions) {
      for (final p in tr) addPoint(p);
    }
    addPoint(mapState.robot);
    if (mapState.startPoint != null) addPoint(mapState.startPoint!);

    if (minX == double.infinity) return null;

    // отступ
    const padding = 10.0;
    minX -= padding;
    maxX += padding;
    minY -= padding;
    maxY += padding;

    // !!! ВАЖНО !!!
    // Я оставил cellSize=1.0 как у тебя.
    // Если в твоём мире 1 клетка = 10 пикселей/см/метров — скажи, и мы выставим правильно.
    const cellSize = 1.0;

    final w = ((maxX - minX) / cellSize).ceil();
    final h = ((maxY - minY) / cellSize).ceil();
    if (w <= 0 || h <= 0) return null;

    CellType at(int x, int y) {
      final worldX = minX + x * cellSize + cellSize * 0.5;
      final worldY = minY + y * cellSize + cellSize * 0.5;
      final pt = Offset(worldX, worldY);

      // RED
      for (final forbidden in mapState.forbiddens) {
        if (_pointInPolygon(pt, forbidden.points)) return CellType.red;
      }

      // GREEN
      for (final zone in mapState.zones) {
        if (_pointInPolygon(pt, zone.points)) return CellType.green;
      }

      // BLUE (линия может быть не по центрам клеток)
      for (final tr in mapState.transitions) {
        if (_pointNearPolyline(pt, tr, threshold: cellSize * 0.85)) {
          return CellType.blue;
        }
      }

      return CellType.empty;
    }

    return GridMap(
      w: w,
      h: h,
      cellSize: cellSize,
      minX: minX,
      minY: minY,
      at: at,
    );
  }

  // =============================================================
  // GEOMETRY
  // =============================================================

  static bool _pointInPolygon(Offset point, List<Offset> polygon) {
    if (polygon.length < 3) return false;

    bool inside = false;
    int j = polygon.length - 1;

    for (int i = 0; i < polygon.length; i++) {
      final xi = polygon[i].dx;
      final yi = polygon[i].dy;
      final xj = polygon[j].dx;
      final yj = polygon[j].dy;

      final intersect = ((yi > point.dy) != (yj > point.dy)) &&
          (point.dx < (xj - xi) * (point.dy - yi) / (yj - yi + 1e-12) + xi);
      if (intersect) inside = !inside;
      j = i;
    }

    return inside;
  }

  static bool _pointNearPolyline(Offset point, List<Offset> polyline,
      {required double threshold}) {
    if (polyline.length < 2) return false;

    for (int i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i];
      final b = polyline[i + 1];
      final dist = _pointToLineSegmentDistance(point, a, b);
      if (dist <= threshold) return true;
    }
    return false;
  }

  static double _pointToLineSegmentDistance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final abSq = ab.distanceSquared;
    if (abSq < 1e-12) return (p - a).distance;

    final t = (ap.dx * ab.dx + ap.dy * ab.dy) / abSq;
    final tt = t.clamp(0.0, 1.0);
    final c = a + Offset(ab.dx * tt, ab.dy * tt);
    return (p - c).distance;
  }
}

// =============================================================
// CORE ROUTING: BLUE SPINE + DETOURS INTO GREEN + CONTINUE BLUE
// =============================================================

class _GreenComp {
  final Set<I2> cells;
  final List<_Entrance> entrances;
  _GreenComp({required this.cells, required this.entrances});
}

class _Entrance {
  final I2 greenCell;
  final I2 blueCell;
  _Entrance({required this.greenCell, required this.blueCell});
}

List<Pt> _buildRouteBlueWithMowDetours(
  GridMap g,
  ManualMapState mapState,
  Pt startWorld, {
  required double blueStepWorld,
  required double lineStepCells,
  required double turnRadiusCells,
  required bool allowBlue,
  required void Function(String) log,
}) {
  // 1) строим “спину” по синей строго
  final spine = _buildBlueSpineFromStart(
    mapState,
    startWorld,
    stepWorld: blueStepWorld,
  );
  if (spine.isEmpty) {
    log('BLUE SPINE EMPTY');
    return const [];
  }

  // 2) компоненты зелёного + входы
  final greenComponents = _findGreenComponents(g);
  final comps = <_GreenComp>[];
  for (final cells in greenComponents) {
    final entrances = _findEntrancesToGreen(g, cells);
    comps.add(_GreenComp(cells: cells, entrances: entrances));
  }

  // Если зелёных нет — просто едем по синей до конца
  if (comps.isEmpty) return spine;

  final done = List<bool>.filled(comps.length, false);

  // 3) идём по синей; если рядом вход в зелёное — детур; потом возвращаемся на синюю и продолжаем
  final out = <Pt>[];
  out.add(spine.first);

  for (int i = 0; i < spine.length; i++) {
    final curBlue = spine[i];
    if (!_samePt(out.last, curBlue)) out.add(curBlue);

    // ищем ближайший вход среди ещё не убранных
    int bestComp = -1;
    _Entrance? bestEnt;
    double bestD2 = double.infinity;

    for (int ci = 0; ci < comps.length; ci++) {
      if (done[ci]) continue;
      final comp = comps[ci];
      if (comp.entrances.isEmpty) continue;

      for (final e in comp.entrances) {
        final bp = cellCenter(g, e.blueCell.x, e.blueCell.y);
        final d2 = _dist2(curBlue, bp);
        if (d2 < bestD2) {
          bestD2 = d2;
          bestComp = ci;
          bestEnt = e;
        }
      }
    }

    // порог близости входа к синей точке
    final nearThreshold = g.cellSize * 2.2; // если входы пропускаются — увеличь до 3.0
    if (bestComp == -1 ||
        bestEnt == null ||
        bestD2 > nearThreshold * nearThreshold) {
      continue; // просто едем дальше по синей
    }

    // ДЕТУР
    done[bestComp] = true;

    final entryGreen =
        cellCenter(g, bestEnt.greenCell.x, bestEnt.greenCell.y);

    // 3.1) съезд с синей в зелёное
    _appendSafeLine(
      out,
      g,
      out.last,
      entryGreen,
      allowBlue: true,
      samples: 24,
      mapState: mapState,
      enforceForbidden: true,
    );

    // 3.2) змейка по зелёной компоненте (строго параллельными прямыми)
    final mow = _buildMowPathForComponent(
      g,
      comps[bestComp].cells,
      start: out.last,
      lineStepCells: lineStepCells,
      turnRadiusCells: turnRadiusCells,
      allowBlue: allowBlue,
      log: log,
      mapState: mapState,
    );

    if (mow.isNotEmpty) {
      if (_samePt(out.last, mow.first)) {
        out.addAll(mow.skip(1));
      } else {
        out.addAll(mow);
      }
    }

    // 3.3) вернуться на синюю ВПЕРЁД (не назад)
    int bestJ = i;
    double bestJoinD2 = double.infinity;

    final maxLook = math.min(spine.length - 1, i + 400);
    for (int j = i; j <= maxLook; j++) {
      final p = spine[j];
      final d2 = _dist2(out.last, p);
      if (d2 < bestJoinD2) {
        bestJoinD2 = d2;
        bestJ = j;
      }
    }

    // Проверка границ перед доступом к массиву
    if (bestJ < 0 || bestJ >= spine.length) {
      log('ERROR: bestJ out of bounds: $bestJ, spine.length: ${spine.length}');
      break;
    }

    final rejoin = spine[bestJ];

    _appendSafeLine(
      out,
      g,
      out.last,
      rejoin,
      allowBlue: true,
      samples: 28,
      mapState: mapState,
      enforceForbidden: true,
    );

    // двигаем индекс вперёд, чтобы продолжить синюю "после возврата"
    // Используем bestJ - 1, так как цикл for увеличит i на следующей итерации
    // Но не меньше текущего i, чтобы не зациклиться
    i = math.max(i, bestJ - 1);
  }

  return _simplify(out, minDist: g.cellSize * 0.10);
}

// =============================================================
// BLUE SPINE (STRICT)
// =============================================================

List<Pt> _buildBlueSpineFromStart(
  ManualMapState mapState,
  Pt startWorld, {
  required double stepWorld,
}) {
  if (mapState.transitions.isEmpty) return const [];

  int bestPoly = -1;
  int bestSeg = -1;
  Offset bestProj = const Offset(0, 0);
  double bestDist = double.infinity;

  for (int pi = 0; pi < mapState.transitions.length; pi++) {
    final poly = mapState.transitions[pi];
    if (poly.length < 2) continue;

    for (int i = 0; i < poly.length - 1; i++) {
      final a = poly[i];
      final b = poly[i + 1];
      final proj = _closestPointOnSegment(
        Offset(startWorld.x, startWorld.y),
        a,
        b,
      );
      final d = (Offset(startWorld.x, startWorld.y) - proj).distance;
      if (d < bestDist) {
        bestDist = d;
        bestPoly = pi;
        bestSeg = i;
        bestProj = proj;
      }
    }
  }

  if (bestPoly == -1) return const [];

  final poly = mapState.transitions[bestPoly];

  // направление: куда "вперёд"
  final dToFirst = (bestProj - poly.first).distance;
  final dToLast = (bestProj - poly.last).distance;
  final forwardToLast = dToLast >= dToFirst;

  final stitched = <Offset>[];
  stitched.add(bestProj);

  if (forwardToLast) {
    for (int i = bestSeg + 1; i < poly.length; i++) {
      stitched.add(poly[i]);
    }
  } else {
    for (int i = bestSeg; i >= 0; i--) {
      stitched.add(poly[i]);
    }
  }

  // СЕМПЛИНГ строго по отрезкам (не "срезает углы")
  return _samplePolylineStrict(stitched, step: stepWorld);
}

List<Pt> _samplePolylineStrict(List<Offset> poly, {required double step}) {
  if (poly.length < 2) return const [];

  final out = <Pt>[];
  out.add(Pt(poly.first.dx, poly.first.dy));

  double carry = 0.0;

  for (int i = 0; i < poly.length - 1; i++) {
    final a = poly[i];
    final b = poly[i + 1];
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final segLen = math.sqrt(dx * dx + dy * dy);
    if (segLen < 1e-9) continue;

    double dist = 0.0;
    double firstT = 0.0;

    if (carry > 0) {
      if (carry >= segLen) {
        carry -= segLen;
        continue;
      } else {
        firstT = carry / segLen;
        dist = carry;
        carry = 0.0;
      }
    }

    while (dist + step <= segLen + 1e-9) {
      dist += step;
      final t = dist / segLen;
      out.add(Pt(a.dx + dx * t, a.dy + dy * t));
    }

    final remain = segLen - dist;
    carry = (remain < 1e-6) ? 0.0 : step - remain;
  }

  final last = poly.last;
  out.add(Pt(last.dx, last.dy));
  return out;
}

Offset _closestPointOnSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final ap = p - a;
  final abSq = ab.distanceSquared;
  if (abSq < 1e-12) return a;

  final t = (ap.dx * ab.dx + ap.dy * ab.dy) / abSq;
  final tt = t.clamp(0.0, 1.0);
  return a + Offset(ab.dx * tt, ab.dy * tt);
}

// =============================================================
// GREEN COMPONENTS + ENTRANCES
// =============================================================

List<Set<I2>> _findGreenComponents(GridMap g) {
  final visited = List<bool>.filled(g.w * g.h, false);
  int idx(int x, int y) => y * g.w + x;

  final comps = <Set<I2>>[];

  for (int y = 0; y < g.h; y++) {
    for (int x = 0; x < g.w; x++) {
      if (visited[idx(x, y)]) continue;
      if (!isGreen(g.at(x, y))) continue;

      final comp = <I2>{};
      final q = Queue<I2>();
      q.add(I2(x, y));
      visited[idx(x, y)] = true;

      while (q.isNotEmpty) {
        final c = q.removeFirst();
        comp.add(c);

        for (final n in _n4(c)) {
          if (!_inBounds(g, n.x, n.y)) continue;
          if (visited[idx(n.x, n.y)]) continue;
          if (!isGreen(g.at(n.x, n.y))) continue;
          visited[idx(n.x, n.y)] = true;
          q.add(n);
        }
      }

      comps.add(comp);
    }
  }

  return comps;
}

List<_Entrance> _findEntrancesToGreen(GridMap g, Set<I2> greenCells) {
  final res = <_Entrance>[];
  for (final c in greenCells) {
    for (final n in _n8(c)) {
      if (!_inBounds(g, n.x, n.y)) continue;
      if (isBlue(g.at(n.x, n.y))) {
        res.add(_Entrance(greenCell: c, blueCell: n));
      }
    }
  }
  return res;
}

Pt? _snapToNearestAllowed(GridMap g, Pt startWorld) {
  final c0 = worldToCell(g, startWorld);

  bool ok(CellType t) => isBlue(t) || isGreen(t);

  if (_inBounds(g, c0.x, c0.y) && ok(g.at(c0.x, c0.y))) {
    return startWorld;
  }

  final visited = List<bool>.filled(g.w * g.h, false);
  int idx(int x, int y) => y * g.w + x;

  final q = Queue<I2>();
  if (_inBounds(g, c0.x, c0.y)) {
    q.add(c0);
    visited[idx(c0.x, c0.y)] = true;
  } else {
    // если старт вне сетки — попробуем соседей
    for (int dx = -2; dx <= 2; dx++) {
      for (int dy = -2; dy <= 2; dy++) {
        final x = c0.x + dx;
        final y = c0.y + dy;
        if (_inBounds(g, x, y) && !visited[idx(x, y)]) {
          visited[idx(x, y)] = true;
          q.add(I2(x, y));
        }
      }
    }
  }

  while (q.isNotEmpty) {
    final c = q.removeFirst();
    final t = g.at(c.x, c.y);
    if (ok(t)) return cellCenter(g, c.x, c.y);

    for (final n in _n4(c)) {
      if (!_inBounds(g, n.x, n.y)) continue;
      if (visited[idx(n.x, n.y)]) continue;
      visited[idx(n.x, n.y)] = true;
      q.add(n);
    }
  }

  return null;
}

// =============================================================
// MOW PATH: PARALLEL STRIPES ONLY + END TURNS (NO DIAGONAL CROSS)
// =============================================================

class _Dir {
  final double x;
  final double y;
  const _Dir(this.x, this.y);

  _Dir normalized() {
    final len = math.sqrt(x * x + y * y);
    if (len < 1e-9) return this;
    return _Dir(x / len, y / len);
  }
}

class _Stripe {
  final double v; // уровень по нормали
  final double uMin;
  final double uMax;
  _Stripe({required this.v, required this.uMin, required this.uMax});
}

List<Pt> _buildMowPathForComponent(
  GridMap g,
  Set<I2> greenCells, {
  required Pt start,
  required double lineStepCells,
  required double turnRadiusCells,
  required bool allowBlue,
  required void Function(String) log,
  required ManualMapState mapState,
}) {
  if (greenCells.isEmpty) return const [];

  final stepWorld = lineStepCells * g.cellSize;

  // Кандидаты направлений. Чтобы всё было строго параллельно — выбираем ОДНО направление на компоненту.
  // Можно добавить 45°, но на практике чаще надо 0/90.
  final dirs = <_Dir>[
    const _Dir(1, 0),
    const _Dir(0, 1),
  ];

  _Dir bestDir = dirs.first;
  List<_Stripe> bestStripes = const [];
  double bestScore = -1e18;

  for (final d0 in dirs) {
    final d = d0.normalized();
    final stripes = _buildStripesFromGreen(g, greenCells, dir: d, stepWorld: stepWorld);
    if (stripes.isEmpty) continue;

    // Скоринг: покрытие - штраф за количество полос
    final coverage = stripes.length.toDouble();
    final score = coverage - stripes.length * 0.05;

    if (score > bestScore) {
      bestScore = score;
      bestDir = d;
      bestStripes = stripes;
    }
  }

  if (bestStripes.isEmpty) {
    log('MOW: stripes empty');
    return const [];
  }

  // Упорядочим полосы по v (строго последовательно -> параллельность)
  bestStripes.sort((a, b) => a.v.compareTo(b.v));

  // Преобразование (u,v) -> world
  final n = _Dir(-bestDir.y, bestDir.x); // нормаль

  Pt uvToWorld(double u, double v) => Pt(bestDir.x * u + n.x * v, bestDir.y * u + n.y * v);

  // Нужно привязать систему координат к миру:
  // Берём опорную точку origin = (0,0) в world.
  // Тогда u = dot(world, dir), v = dot(world, normal).
  double dot(Pt p, _Dir a) => p.x * a.x + p.y * a.y;

  // Начальная позиция в uv
  final u0 = dot(start, bestDir);
  final v0 = dot(start, n);

  // Найдём ближайшую полосу к старту (по |v-v0|)
  int startStripeIdx = 0;
  double bestDv = double.infinity;
  for (int i = 0; i < bestStripes.length; i++) {
    final dv = (bestStripes[i].v - v0).abs();
    if (dv < bestDv) {
      bestDv = dv;
      startStripeIdx = i;
    }
  }

  // Строим порядок обхода: от ближайшей полосы вверх, затем вниз (или наоборот) — без прыжков через середину
  final order = <int>[];
  // вверх
  for (int i = startStripeIdx; i < bestStripes.length; i++) order.add(i);
  // вниз
  for (int i = startStripeIdx - 1; i >= 0; i--) order.add(i);

  final out = <Pt>[];
  Pt cur = start;
  out.add(cur);

  bool forward = true; // направление по u

  for (int k = 0; k < order.length; k++) {
    final stripe = bestStripes[order[k]];

    // Концы полосы в world (строго параллельные линии)
    final a = uvToWorld(stripe.uMin, stripe.v);
    final b = uvToWorld(stripe.uMax, stripe.v);

    // Выбираем, с какого конца заходить — чтобы было меньше "диагонального подъезда"
    final distA = _dist2(cur, a);
    final distB = _dist2(cur, b);
    final startEnd = (distA <= distB) ? a : b;
    final finishEnd = (startEnd == a) ? b : a;

    // Подъезд к началу полосы (короткий)
    _appendSafeLine(out, g, cur, startEnd,
        allowBlue: true, samples: 18, mapState: mapState, enforceForbidden: true);
    cur = out.last;

    // Основной прямой проход по полосе (СТРОГО ПРЯМОЙ)
    _appendSafeLine(out, g, cur, finishEnd,
        allowBlue: true, samples: 30, mapState: mapState, enforceForbidden: true);
    cur = out.last;

    // Плавный разворот к следующей полосе (без диагональной линии через всю зону)
    if (k != order.length - 1) {
      final nextStripe = bestStripes[order[k + 1]];
      final nextA = uvToWorld(nextStripe.uMin, nextStripe.v);
      final nextB = uvToWorld(nextStripe.uMax, nextStripe.v);

      // Куда входить в следующую — противоположный конец, чтобы змейка шла "туда-сюда"
      final nextStart = forward ? nextB : nextA;

      // ПОВОРОТ: делаем плавную S-кривую (Bezier) вблизи конца текущей полосы,
      // чтобы не появлялись диагональные линии через всю зону.
      final r = math.max(0.1, turnRadiusCells * g.cellSize);
      _appendSmoothTurnBezier(out, g,
          from: cur,
          to: nextStart,
          dir: bestDir,
          radius: r,
          allowBlue: true,
          mapState: mapState,
          enforceForbidden: true);

      cur = out.last;
      forward = !forward;
    }
  }

  return _simplify(out, minDist: g.cellSize * 0.08);
}

List<_Stripe> _buildStripesFromGreen(
  GridMap g,
  Set<I2> greenCells, {
  required _Dir dir,
  required double stepWorld,
}) {
  final n = _Dir(-dir.y, dir.x);

  // точки центров клеток
  final pts = <Pt>[];
  for (final c in greenCells) {
    pts.add(cellCenter(g, c.x, c.y));
  }

  double dot(Pt p, _Dir a) => p.x * a.x + p.y * a.y;

  // диапазон v
  double minV = double.infinity;
  double maxV = -double.infinity;
  for (final p in pts) {
    final v = dot(p, n);
    if (v < minV) minV = v;
    if (v > maxV) maxV = v;
  }

  // уровни полос: v = minV + i*stepWorld
  final stripes = <_Stripe>[];
  if (minV == double.infinity) return stripes;
  if (stepWorld <= 1e-9) return stripes; // Защита от деления на ноль

  final count = ((maxV - minV) / stepWorld).ceil() + 1;
  final half = stepWorld * 0.55; // ширина захвата полосы (чтобы не было дыр)

  for (int i = 0; i < count; i++) {
    final vLevel = minV + i * stepWorld;
    double uMin = double.infinity;
    double uMax = -double.infinity;

    for (final p in pts) {
      final v = dot(p, n);
      if ((v - vLevel).abs() <= half) {
        final u = dot(p, dir);
        if (u < uMin) uMin = u;
        if (u > uMax) uMax = u;
      }
    }

    if (uMin.isFinite && uMax.isFinite && (uMax - uMin) > 1e-6) {
      stripes.add(_Stripe(v: vLevel, uMin: uMin, uMax: uMax));
    }
  }

  return stripes;
}

// =============================================================
// DRAW / TURN HELPERS
// =============================================================

bool _samePt(Pt a, Pt b) => (a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9;

double _dist2(Pt a, Pt b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return dx * dx + dy * dy;
}

/// Прямая с safety-проверкой
void _appendSafeLine(
  List<Pt> out,
  GridMap g,
  Pt from,
  Pt to, {
  required bool allowBlue,
  required int samples,
  required ManualMapState mapState,
  required bool enforceForbidden,
}) {
  if (_samePt(from, to)) return;

  Pt last = out.isEmpty ? from : out.last;
  if (!_samePt(last, from)) out.add(from);

  for (int i = 1; i <= samples; i++) {
    final t = i / samples;
    final p = Pt(
      from.x + (to.x - from.x) * t,
      from.y + (to.y - from.y) * t,
    );

    if (enforceForbidden && _isInForbidden(mapState, Offset(p.x, p.y))) {
      // упёрлись в запрет — прекращаем (в будущем тут будет обход)
      return;
    }

    if (!isPointSafe(g, p, allowBlue: allowBlue)) {
      return;
    }

    out.add(p);
  }
}

/// Плавный поворот через Bezier-кривую.
/// Это убирает диагональные "перемычки" через зону и делает змейку визуально ровной.
void _appendSmoothTurnBezier(
  List<Pt> out,
  GridMap g, {
  required Pt from,
  required Pt to,
  required _Dir dir,
  required double radius,
  required bool allowBlue,
  required ManualMapState mapState,
  required bool enforceForbidden,
}) {
  // Контрольные точки: немного вперёд по направлению + к целевой
  final d = dir.normalized();
  final c1 = Pt(from.x + d.x * radius, from.y + d.y * radius);
  final c2 = Pt(to.x - d.x * radius, to.y - d.y * radius);

  // Семплим кубическую Bezier
  const int steps = 24;
  for (int i = 1; i <= steps; i++) {
    final t = i / steps;
    final p = _cubicBezier(from, c1, c2, to, t);

    if (enforceForbidden && _isInForbidden(mapState, Offset(p.x, p.y))) {
      // если в запрете — fallback на прямую (короткую) до to
      _appendSafeLine(out, g, out.last, to,
          allowBlue: allowBlue, samples: 18, mapState: mapState, enforceForbidden: enforceForbidden);
      return;
    }

    if (!isPointSafe(g, p, allowBlue: allowBlue)) {
      // fallback
      _appendSafeLine(out, g, out.last, to,
          allowBlue: allowBlue, samples: 18, mapState: mapState, enforceForbidden: enforceForbidden);
      return;
    }

    out.add(p);
  }
}

Pt _cubicBezier(Pt p0, Pt p1, Pt p2, Pt p3, double t) {
  final u = 1.0 - t;
  final tt = t * t;
  final uu = u * u;
  final uuu = uu * u;
  final ttt = tt * t;

  final x = p0.x * uuu +
      3.0 * p1.x * uu * t +
      3.0 * p2.x * u * tt +
      p3.x * ttt;

  final y = p0.y * uuu +
      3.0 * p1.y * uu * t +
      3.0 * p2.y * u * tt +
      p3.y * ttt;

  return Pt(x, y);
}

bool _isInForbidden(ManualMapState mapState, Offset p) {
  for (final f in mapState.forbiddens) {
    if (RouteBuilder._pointInPolygon(p, f.points)) return true;
  }
  return false;
}

/// Упрощение пути
List<Pt> _simplify(List<Pt> pts, {required double minDist}) {
  if (pts.isEmpty) return const [];
  final out = <Pt>[pts.first];

  final minD2 = minDist * minDist;

  for (int i = 1; i < pts.length; i++) {
    final a = out.last;
    final b = pts[i];
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    if ((dx * dx + dy * dy) >= minD2) {
      out.add(b);
    }
  }
  return out;
}

List<I2> _n4(I2 c) => [
      I2(c.x + 1, c.y),
      I2(c.x - 1, c.y),
      I2(c.x, c.y + 1),
      I2(c.x, c.y - 1),
    ];

List<I2> _n8(I2 c) => [
      I2(c.x + 1, c.y),
      I2(c.x - 1, c.y),
      I2(c.x, c.y + 1),
      I2(c.x, c.y - 1),
      I2(c.x + 1, c.y + 1),
      I2(c.x - 1, c.y - 1),
      I2(c.x + 1, c.y - 1),
      I2(c.x - 1, c.y + 1),
    ];
