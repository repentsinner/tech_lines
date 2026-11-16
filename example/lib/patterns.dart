import 'dart:math' as math;
import 'dart:typed_data';

import 'package:tech_lines/tech_lines.dart';
import 'package:vector_math/vector_math_64.dart';

/// One batch of a pattern: its segments and how they draw.
class PatternBatch {
  PatternBatch(this.segments, this.style);

  final LineSegments segments;
  final LineStyle style;
}

/// Shapes a pattern can draw its lines against.
enum SolidShape { box, sphere, cylinder }

/// An opaque solid a pattern draws its lines against, [size] being its
/// full extent on each axis before [rotation].
class PatternBox {
  const PatternBox(
    this.center,
    this.size,
    this.rotation, {
    this.shape = SolidShape.box,
    this.shade = 0.22,
  });

  final Vector3 center;
  final Vector3 size;
  final Quaternion rotation;
  final SolidShape shape;

  /// Grey level of its unlit surface.
  final double shade;
}

/// A scene of lines chosen to expose one class of line-rendering defect.
class LinePattern {
  const LinePattern({
    required this.name,
    required this.description,
    required this.build,
    this.boxes = const [],
  });

  final String name;

  /// What to look for, shown under the viewport.
  final String description;

  final List<PatternBatch> Function() build;
  final List<PatternBox> boxes;
}

const _white = LinearRgba(0.9, 0.9, 0.9);
const _cyan = LinearRgba(0.1, 0.7, 0.9);
const _amber = LinearRgba(1.0, 0.55, 0.05);

/// Builds [LineSegments] from a list of endpoint pairs.
LineSegments _segments(
  Iterable<(Vector3, Vector3)> pairs, {
  List<double>? widths,
}) {
  final list = pairs.toList();
  final endpoints = Float32List(list.length * 6);
  for (var i = 0; i < list.length; i++) {
    final (a, b) = list[i];
    endpoints.setAll(i * 6, [a.x, a.y, a.z, b.x, b.y, b.z]);
  }

  return LineSegments(
    endpoints: endpoints,
    widthsPixels: widths == null ? null : Float32List.fromList(widths),
  );
}

/// Every pattern, in the order the picker shows them.
final patterns = <LinePattern>[
  LinePattern(
    name: 'Width ladder',
    description:
        'Horizontal and slightly tilted lines from 0.25 to 4 px. Each rung '
        'should look as wide as its label says, and the rungs below 1 px '
        'should fade rather than break up.',
    build: () {
      const widths = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0];
      final pairs = <(Vector3, Vector3)>[];
      final perSegment = <double>[];
      for (var i = 0; i < widths.length; i++) {
        final y = 35.0 - i * 10;
        pairs
          ..add((Vector3(-60, y, 0), Vector3(-5, y, 0)))
          ..add((Vector3(5, y - 1.5, 0), Vector3(60, y + 1.5, 0)));
        perSegment
          ..add(widths[i])
          ..add(widths[i]);
      }

      return [
        PatternBatch(
          _segments(pairs, widths: perSegment),
          const LineStyle(widthPixels: 1, color: _white),
        ),
      ];
    },
  ),
  LinePattern(
    name: 'Angle fan',
    description:
        'Lines every 3° around a centre at 1 px. Every spoke should have '
        'the same weight; near-horizontal and near-diagonal spokes show '
        'aliasing first.',
    build: () => [
      PatternBatch(
        _segments([
          for (var a = 0; a < 360; a += 3)
            (
              Vector3(
                8 * math.cos(a * math.pi / 180),
                8 * math.sin(a * math.pi / 180),
                0,
              ),
              Vector3(
                60 * math.cos(a * math.pi / 180),
                60 * math.sin(a * math.pi / 180),
                0,
              ),
            ),
        ]),
        const LineStyle(widthPixels: 1, color: _white),
      ),
    ],
  ),
  LinePattern(
    name: 'Dense parallels',
    description:
        'Close parallel lines at 0.5 px. Zoom out until they approach one '
        'per pixel: they should merge into an even grey, not a moiré.',
    build: () => [
      PatternBatch(
        _segments([
          for (var i = -100; i <= 100; i++)
            (Vector3(i * 0.6, -50, 0), Vector3(i * 0.6 + 10, 50, 0)),
        ]),
        const LineStyle(widthPixels: 0.5, color: _white),
      ),
    ],
  ),
  LinePattern(
    name: 'Ground grid',
    description:
        'A large grid on the ground, seen at a grazing angle. Orbit '
        'slowly: distant lines should thin and fade smoothly without '
        'crawling or breaking into dashes.',
    build: () => [
      PatternBatch(
        _segments([
          for (var i = -50; i <= 50; i++) ...[
            (Vector3(i * 10.0, -40, -500), Vector3(i * 10.0, -40, 500)),
            (Vector3(-500, -40, i * 10.0), Vector3(500, -40, i * 10.0)),
          ],
        ]),
        const LineStyle(widthPixels: 1, color: LinearRgba(0.4, 0.4, 0.45)),
      ),
    ],
  ),
  LinePattern(
    name: 'Lines on faces',
    description:
        'Edges and a cross-hatch drawn on the faces of a tilted box. Orbit '
        'to steep angles: the lines should stay whole, without stipple '
        'where they meet the face.',
    boxes: [
      PatternBox(
        Vector3.zero(),
        Vector3(60, 40, 30),
        Quaternion.axisAngle(Vector3(1, 1, 0).normalized(), 0.5),
      ),
    ],
    build: () {
      final box = Matrix4.compose(
        Vector3.zero(),
        Quaternion.axisAngle(Vector3(1, 1, 0).normalized(), 0.5),
        Vector3(30, 20, 15),
      );
      Vector3 at(double x, double y, double z) =>
          box.transformed3(Vector3(x, y, z));
      final edges = <(Vector3, Vector3)>[];
      for (final a in [-1.0, 1.0]) {
        for (final b in [-1.0, 1.0]) {
          edges
            ..add((at(-1, a, b), at(1, a, b)))
            ..add((at(a, -1, b), at(a, 1, b)))
            ..add((at(a, b, -1), at(a, b, 1)));
        }
      }
      final hatch = <(Vector3, Vector3)>[
        for (var t = -0.9; t < 0.95; t += 0.15) ...[
          (at(t, -1, 1), at(t, 1, 1)),
          (at(-1, t, 1), at(1, t, 1)),
          (at(1, t, -1), at(1, t, 1)),
          (at(t, -1, -1), at(t, -1, 1)),
        ],
      ];

      return [
        PatternBatch(
          _segments(edges),
          const LineStyle(widthPixels: 1.5, color: _amber),
        ),
        PatternBatch(
          _segments(hatch),
          const LineStyle(widthPixels: 1, color: _cyan),
        ),
      ];
    },
  ),
  LinePattern(
    name: 'Lines through solids',
    description:
        'Lines piercing a box, a sphere and a cylinder from several '
        'directions. Each should vanish where it enters the solid and '
        'reappear where it leaves; the depth bias lets it run slightly '
        'past the surface, more where it crosses at a shallow angle.',
    boxes: [
      PatternBox(
        Vector3(-45, 0, 0),
        Vector3(30, 30, 30),
        Quaternion.axisAngle(Vector3(0.3, 1, 0.2).normalized(), 0.6),
      ),
      PatternBox(
        Vector3.zero(),
        Vector3(32, 32, 32),
        Quaternion.identity(),
        shape: SolidShape.sphere,
        shade: 0.3,
      ),
      PatternBox(
        Vector3(45, 0, 0),
        Vector3(24, 40, 24),
        Quaternion.axisAngle(Vector3(0, 0, 1), 0.4),
        shape: SolidShape.cylinder,
        shade: 0.26,
      ),
    ],
    build: () {
      final through = <(Vector3, Vector3)>[];
      for (final cx in [-45.0, 0.0, 45.0]) {
        final c = Vector3(cx, 0, 0);
        through
          // Along the view axis at the default camera.
          ..add((c + Vector3(3, 4, -60), c + Vector3(3, 4, 60)))
          // Diagonals through the centre.
          ..add((c + Vector3(-25, -25, -25), c + Vector3(25, 25, 25)))
          ..add((c + Vector3(-25, 25, -20), c + Vector3(25, -25, 20)))
          // Shallow: nearly parallel to the front, dipping inside.
          ..add((c + Vector3(-28, -8, 30), c + Vector3(28, -8, -2)));
      }
      final tangent = <(Vector3, Vector3)>[
        // Grazing the sphere's silhouette and its front.
        (Vector3(-20, 16.5, 0), Vector3(20, 16.5, 0)),
        (Vector3(-20, -5, 16), Vector3(20, -5, 16)),
      ];

      return [
        PatternBatch(
          _segments(through),
          const LineStyle(widthPixels: 2, color: _amber),
        ),
        PatternBatch(
          _segments(tangent),
          const LineStyle(widthPixels: 1, color: _cyan),
        ),
      ];
    },
  ),
  LinePattern(
    name: 'Near-plane crossers',
    description:
        'Long lines that pass behind the camera. Orbit and zoom in: no '
        'line should spike across the screen or vanish while part of it '
        'is in front of the camera.',
    build: () => [
      PatternBatch(
        _segments([
          for (var i = -5; i <= 5; i++)
            (Vector3(i * 8.0, -10, -2000), Vector3(i * 8.0, -10, 2000)),
          for (var i = -5; i <= 5; i++)
            (Vector3(-20, i * 8.0, -2000), Vector3(-20, i * 8.0, 2000)),
        ]),
        const LineStyle(widthPixels: 1.5, color: _white),
      ),
    ],
  ),
  LinePattern(
    name: 'Translucent overlaps',
    description:
        'Crossing lines at half opacity. Each line should be uniformly '
        'translucent, including its core, and crossings should blend '
        'evenly.',
    build: () => [
      PatternBatch(
        _segments([
          for (var i = -6; i <= 6; i++)
            (Vector3(-50, i * 6.0, 0), Vector3(50, i * 6.0, 0)),
        ]),
        const LineStyle(widthPixels: 4, color: _cyan, opacity: 0.5),
      ),
      PatternBatch(
        _segments([
          for (var i = -6; i <= 6; i++)
            (Vector3(i * 6.0, -50, 0.1), Vector3(i * 6.0, 50, 0.1)),
        ]),
        const LineStyle(widthPixels: 4, color: _amber, opacity: 0.5),
      ),
    ],
  ),
  LinePattern(
    name: 'Polylines',
    description:
        'A zigzag with sharp turns and a spiral of 2,000 short segments, '
        'like a tessellated arc. Corners should have no notch and the '
        'spiral should read as one smooth line.',
    build: () {
      final zigzag = <(Vector3, Vector3)>[];
      for (var i = 0; i < 12; i++) {
        final a = Vector3(-60 + i * 5.0, i.isEven ? 10 : 30, 0);
        final b = Vector3(-55 + i * 5.0, i.isEven ? 30 : 10, 0);
        zigzag.add((a, b));
      }
      final spiral = <(Vector3, Vector3)>[];
      const steps = 2000;
      Vector3 point(int i) {
        final t = i / steps * 12 * math.pi;
        final r = 2 + t * 1.2;

        return Vector3(20 + r * math.cos(t), -10 + r * math.sin(t), 0);
      }

      for (var i = 0; i < steps; i++) {
        spiral.add((point(i), point(i + 1)));
      }

      return [
        PatternBatch(
          _segments(zigzag),
          const LineStyle(widthPixels: 4, color: _amber),
        ),
        PatternBatch(
          _segments(spiral),
          const LineStyle(widthPixels: 1, color: _white),
        ),
      ];
    },
  ),
];
