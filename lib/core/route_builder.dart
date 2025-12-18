import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../features/manual/manual_control_screen.dart';

/// ============================================================================
/// Алгоритм построения оптимального маршрута для уборки
/// ============================================================================
class RouteBuilder {
  static const double lineSpacing = 0.8; // Шаг между параллельными линиями (в клетках)
  static const double smoothTurnRadius = 0.5; // Радиус плавного поворота

  /// Построить маршрут для карты
  static List<Offset> buildRoute(ManualMapState mapState) {
    if (mapState.zones.isEmpty) {
      return [];
    }

    final route = <Offset>[];
    // Используем начальную точку, если она задана, иначе позицию робота
    final startPoint = mapState.startPoint ?? mapState.robot;

    // Если есть переходы, используем их для соединения зон
    // Иначе строим маршрут напрямую между зонами

    // Для каждой зоны строим параллельные линии
    for (int i = 0; i < mapState.zones.length; i++) {
      final zone = mapState.zones[i];
      
      // Строим маршрут внутри зоны (параллельные линии)
      final zoneRoute = _buildZoneRoute(zone, mapState.forbiddens);
      
      if (zoneRoute.isNotEmpty) {
        // Если это не первая зона, добавляем переход
        if (i > 0 && route.isNotEmpty) {
          final transition = _findTransitionToZone(
            route.last,
            zone,
            mapState.transitions,
            mapState.forbiddens,
          );
          if (transition.isNotEmpty) {
            route.addAll(transition);
          } else {
            // Если нет перехода, строим прямой путь
            final directPath = _buildDirectPath(
              route.last,
              zoneRoute.first,
              mapState.forbiddens,
            );
            route.addAll(directPath);
          }
        } else if (route.isEmpty) {
          // Первая зона - добавляем путь от стартовой точки
          final pathToFirst = _buildDirectPath(
            startPoint,
            zoneRoute.first,
            mapState.forbiddens,
          );
          route.addAll(pathToFirst);
        }
        
        route.addAll(zoneRoute);
      }
    }

    return route;
  }

  /// Построить маршрут внутри зоны (параллельные линии)
  static List<Offset> _buildZoneRoute(
    PolyShape zone,
    List<PolyShape> forbiddens,
  ) {
    if (zone.points.length < 3) return [];

    // Вычисляем bounding box зоны
    double minX = zone.points.first.dx;
    double maxX = zone.points.first.dx;
    double minY = zone.points.first.dy;
    double maxY = zone.points.first.dy;

    for (final pt in zone.points) {
      if (pt.dx < minX) minX = pt.dx;
      if (pt.dx > maxX) maxX = pt.dx;
      if (pt.dy < minY) minY = pt.dy;
      if (pt.dy > maxY) maxY = pt.dy;
    }

    final width = maxX - minX;
    final height = maxY - minY;

    // Определяем направление движения (по большей стороне)
    final isHorizontal = width >= height;
    final route = <Offset>[];

    if (isHorizontal) {
      // Движение горизонтально (слева направо)
      final startY = minY;
      final endY = maxY;
      double currentY = startY;
      bool goingRight = true;

      while (currentY <= endY) {
        // Находим точки пересечения линии Y=currentY с границами зоны
        final intersections = _findIntersectionsWithZone(
          zone,
          currentY,
          true,
        );

        if (intersections.length >= 2) {
          final left = intersections.first;
          final right = intersections.last;

          if (goingRight) {
            route.add(left);
            route.add(right);
          } else {
            route.add(right);
            route.add(left);
          }
        }

        currentY += lineSpacing;
        goingRight = !goingRight; // Зигзаг
      }
    } else {
      // Движение вертикально (снизу вверх)
      final startX = minX;
      final endX = maxX;
      double currentX = startX;
      bool goingUp = true;

      while (currentX <= endX) {
        // Находим точки пересечения линии X=currentX с границами зоны
        final intersections = _findIntersectionsWithZone(
          zone,
          currentX,
          false,
        );

        if (intersections.length >= 2) {
          final bottom = intersections.first;
          final top = intersections.last;

          if (goingUp) {
            route.add(bottom);
            route.add(top);
          } else {
            route.add(top);
            route.add(bottom);
          }
        }

        currentX += lineSpacing;
        goingUp = !goingUp; // Зигзаг
      }
    }

    // Добавляем плавные повороты между линиями
    return _smoothRoute(route, forbiddens);
  }

  /// Найти точки пересечения линии с границами зоны
  static List<Offset> _findIntersectionsWithZone(
    PolyShape zone,
    double lineValue,
    bool isHorizontal,
  ) {
    final intersections = <Offset>[];
    final points = zone.points;

    for (int i = 0; i < points.length; i++) {
      final p1 = points[i];
      final p2 = points[(i + 1) % points.length];

      Offset? intersection;
      if (isHorizontal) {
        // Пересечение с горизонтальной линией Y=lineValue
        if ((p1.dy <= lineValue && p2.dy >= lineValue) ||
            (p1.dy >= lineValue && p2.dy <= lineValue)) {
          if ((p2.dy - p1.dy).abs() > 0.001) {
            final t = (lineValue - p1.dy) / (p2.dy - p1.dy);
            final x = p1.dx + t * (p2.dx - p1.dx);
            intersection = Offset(x, lineValue);
          }
        }
      } else {
        // Пересечение с вертикальной линией X=lineValue
        if ((p1.dx <= lineValue && p2.dx >= lineValue) ||
            (p1.dx >= lineValue && p2.dx <= lineValue)) {
          if ((p2.dx - p1.dx).abs() > 0.001) {
            final t = (lineValue - p1.dx) / (p2.dx - p1.dx);
            final y = p1.dy + t * (p2.dy - p1.dy);
            intersection = Offset(lineValue, y);
          }
        }
      }

      if (intersection != null) {
        // Проверяем, что точка внутри зоны
        if (_isPointInsidePolygon(intersection, zone)) {
          intersections.add(intersection);
        }
      }
    }

    // Сортируем точки
    if (isHorizontal) {
      intersections.sort((a, b) => a.dx.compareTo(b.dx));
    } else {
      intersections.sort((a, b) => a.dy.compareTo(b.dy));
    }

    return intersections;
  }

  /// Добавить плавные повороты к маршруту
  static List<Offset> _smoothRoute(
    List<Offset> route,
    List<PolyShape> forbiddens,
  ) {
    if (route.length < 2) return route;

    final smoothed = <Offset>[route.first];

    for (int i = 1; i < route.length - 1; i++) {
      final prev = route[i - 1];
      final curr = route[i];
      final next = route[i + 1];

      // Вычисляем угол поворота
      final angle1 = math.atan2(curr.dy - prev.dy, curr.dx - prev.dx);
      final angle2 = math.atan2(next.dy - curr.dy, next.dx - curr.dx);
      final angleDiff = angle2 - angle1;

      // Нормализуем угол
      var normalizedAngle = angleDiff;
      while (normalizedAngle > math.pi) normalizedAngle -= 2 * math.pi;
      while (normalizedAngle < -math.pi) normalizedAngle += 2 * math.pi;

      if (normalizedAngle.abs() > 0.1) {
        // Добавляем плавный поворот
        final turnPoints = _createSmoothTurn(
          prev,
          curr,
          next,
          smoothTurnRadius,
          forbiddens,
        );
        smoothed.addAll(turnPoints);
      } else {
        smoothed.add(curr);
      }
    }

    smoothed.add(route.last);
    return smoothed;
  }

  /// Создать плавный поворот
  static List<Offset> _createSmoothTurn(
    Offset p1,
    Offset p2,
    Offset p3,
    double radius,
    List<PolyShape> forbiddens,
  ) {
    final turnPoints = <Offset>[];

    // Векторы направлений
    final dir1 = (p2 - p1).normalized();
    final dir2 = (p3 - p2).normalized();

    // Угол поворота
    final angle = math.acos(dir1.dot(dir2).clamp(-1.0, 1.0));

    if (angle < 0.1) {
      // Угол слишком мал, поворот не нужен
      return [p2];
    }

    // Количество точек для плавного поворота
    final numPoints = (angle / (math.pi / 8)).ceil().clamp(3, 8);

    for (int i = 0; i <= numPoints; i++) {
      final t = i / numPoints;
      final angleT = angle * t;
      
      // Вращаем вектор направления
      final cosA = math.cos(angleT);
      final sinA = math.sin(angleT);
      final rotated = Offset(
        dir1.dx * cosA - dir1.dy * sinA,
        dir1.dx * sinA + dir1.dy * cosA,
      );

      final point = p2 + rotated * radius * t;
      
      // Проверяем, что точка не в запретной зоне
      bool inForbidden = false;
      for (final forbidden in forbiddens) {
        if (_isPointInsidePolygon(point, forbidden)) {
          inForbidden = true;
          break;
        }
      }

      if (!inForbidden) {
        turnPoints.add(point);
      }
    }

    return turnPoints.isEmpty ? [p2] : turnPoints;
  }

  /// Найти переход к зоне
  static List<Offset> _findTransitionToZone(
    Offset fromPoint,
    PolyShape zone,
    List<List<Offset>> transitions,
    List<PolyShape> forbiddens,
  ) {
    // Ищем переход, который ведет к этой зоне
    for (final transition in transitions) {
      if (transition.isEmpty) continue;

      final transitionEnd = transition.last;
      
      // Проверяем, что конец перехода близок к зоне
      if (_isPointOnEdge(transitionEnd, zone, 2.0)) {
        // Проверяем, что начало перехода близко к fromPoint
        final transitionStart = transition.first;
        if ((transitionStart - fromPoint).distance < 5.0) {
          return transition;
        }
      }
    }

    return [];
  }

  /// Построить прямой путь между точками (избегая запретных зон)
  static List<Offset> _buildDirectPath(
    Offset from,
    Offset to,
    List<PolyShape> forbiddens,
  ) {
    // Простой алгоритм: прямая линия, если не пересекает запретные зоны
    final path = <Offset>[from];
    
    // Проверяем пересечение с запретными зонами
    bool intersectsForbidden = false;
    for (final forbidden in forbiddens) {
      if (_lineIntersectsPolygon(from, to, forbidden)) {
        intersectsForbidden = true;
        break;
      }
    }

    if (!intersectsForbidden) {
      // Прямой путь безопасен
      path.add(to);
    } else {
      // Нужно обойти запретную зону (упрощенный алгоритм)
      final detour = _buildDetourPath(from, to, forbiddens);
      path.addAll(detour);
    }

    return path;
  }

  /// Построить обходной путь
  static List<Offset> _buildDetourPath(
    Offset from,
    Offset to,
    List<PolyShape> forbiddens,
  ) {
    // Упрощенный алгоритм: обходим вокруг первой встреченной запретной зоны
    for (final forbidden in forbiddens) {
      if (_lineIntersectsPolygon(from, to, forbidden)) {
        // Находим ближайшую точку на краю запретной зоны
        final edgePoint = _findClosestEdgePoint(from, forbidden);
        final exitPoint = _findClosestEdgePoint(to, forbidden);
        
        return [edgePoint, exitPoint, to];
      }
    }

    return [to];
  }

  /// Проверка пересечения линии с полигоном
  static bool _lineIntersectsPolygon(
    Offset lineStart,
    Offset lineEnd,
    PolyShape polygon,
  ) {
    final points = polygon.points;
    for (int i = 0; i < points.length; i++) {
      final p1 = points[i];
      final p2 = points[(i + 1) % points.length];
      
      if (_linesIntersect(lineStart, lineEnd, p1, p2)) {
        return true;
      }
    }
    return false;
  }

  /// Проверка пересечения двух отрезков
  static bool _linesIntersect(
    Offset a1,
    Offset a2,
    Offset b1,
    Offset b2,
  ) {
    final d = (a2.dx - a1.dx) * (b2.dy - b1.dy) - (a2.dy - a1.dy) * (b2.dx - b1.dx);
    if (d.abs() < 0.001) return false; // Параллельные линии

    final t = ((b1.dx - a1.dx) * (b2.dy - b1.dy) - (b1.dy - a1.dy) * (b2.dx - b1.dx)) / d;
    final u = ((b1.dx - a1.dx) * (a2.dy - a1.dy) - (b1.dy - a1.dy) * (a2.dx - a1.dx)) / d;

    return t >= 0 && t <= 1 && u >= 0 && u <= 1;
  }

  /// Найти ближайшую точку на краю полигона
  static Offset _findClosestEdgePoint(Offset point, PolyShape polygon) {
    double minDist = double.infinity;
    Offset closest = polygon.points.first;

    final points = polygon.points;
    for (int i = 0; i < points.length; i++) {
      final p1 = points[i];
      final p2 = points[(i + 1) % points.length];

      final closestOnSegment = _closestPointOnSegment(point, p1, p2);
      final dist = (point - closestOnSegment).distance;

      if (dist < minDist) {
        minDist = dist;
        closest = closestOnSegment;
      }
    }

    return closest;
  }

  /// Найти ближайшую точку на отрезке
  static Offset _closestPointOnSegment(
    Offset point,
    Offset segStart,
    Offset segEnd,
  ) {
    final A = point.dx - segStart.dx;
    final B = point.dy - segStart.dy;
    final C = segEnd.dx - segStart.dx;
    final D = segEnd.dy - segStart.dy;

    final dot = A * C + B * D;
    final lenSq = C * C + D * D;
    if (lenSq == 0) return segStart;

    final param = (dot / lenSq).clamp(0.0, 1.0);
    return Offset(
      segStart.dx + param * C,
      segStart.dy + param * D,
    );
  }

  /// Проверка точки на краю полигона
  static bool _isPointOnEdge(
    Offset point,
    PolyShape polygon, [
    double tolerance = 1.0,
  ]) {
    final points = polygon.points;
    for (int i = 0; i < points.length; i++) {
      final p1 = points[i];
      final p2 = points[(i + 1) % points.length];

      final dist = _pointToSegmentDistance(point, p1, p2);
      if (dist <= tolerance) {
        return true;
      }
    }
    return false;
  }

  /// Расстояние от точки до отрезка
  static double _pointToSegmentDistance(
    Offset point,
    Offset segStart,
    Offset segEnd,
  ) {
    final A = point.dx - segStart.dx;
    final B = point.dy - segStart.dy;
    final C = segEnd.dx - segStart.dx;
    final D = segEnd.dy - segStart.dy;

    final dot = A * C + B * D;
    final lenSq = C * C + D * D;
    if (lenSq == 0) {
      return (point - segStart).distance;
    }

    final param = (dot / lenSq).clamp(0.0, 1.0);
    final closest = Offset(
      segStart.dx + param * C,
      segStart.dy + param * D,
    );

    return (point - closest).distance;
  }

  /// Проверка точки внутри полигона (ray casting)
  static bool _isPointInsidePolygon(Offset point, PolyShape polygon) {
    final points = polygon.points;
    if (points.length < 3) return false;

    bool inside = false;
    for (int i = 0, j = points.length - 1; i < points.length; j = i++) {
      final xi = points[i].dx, yi = points[i].dy;
      final xj = points[j].dx, yj = points[j].dy;

      final intersect = ((yi > point.dy) != (yj > point.dy)) &&
          (point.dx < (xj - xi) * (point.dy - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }
}

/// Расширение для Offset
extension OffsetExtension on Offset {
  Offset normalized() {
    final len = distance;
    if (len < 0.001) return Offset.zero;
    return Offset(dx / len, dy / len);
  }

  double dot(Offset other) => dx * other.dx + dy * other.dy;
}

