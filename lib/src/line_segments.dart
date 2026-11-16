import 'dart:typed_data';

/// Floats per segment in [LineSegments.endpoints]: two xyz endpoints.
const floatsPerEndpointPair = 6;

/// Floats per segment in [LineSegments.colors].
const floatsPerColor = 4;

/// Floats per segment in [LineSegments.progress]: start and end.
const floatsPerProgress = 2;

/// A colour in linear RGB with straight (not premultiplied) alpha.
final class LinearRgba {
  const LinearRgba(this.r, this.g, this.b, [this.a = 1]);

  final double r;
  final double g;
  final double b;
  final double a;

  @override
  bool operator ==(Object other) =>
      other is LinearRgba &&
      other.r == r &&
      other.g == g &&
      other.b == b &&
      other.a == a;

  @override
  int get hashCode => Object.hash(r, g, b, a);

  @override
  String toString() => 'LinearRgba($r, $g, $b, $a)';
}

/// Segments in struct-of-arrays form, in the caller's world coordinates.
final class LineSegments {
  /// Creates segment data, checking every buffer holds [segmentCount]
  /// entries.
  ///
  /// Throws [ArgumentError] when a buffer's length does not match.
  LineSegments({
    required this.endpoints,
    this.colors,
    this.progress,
    this.widthsPixels,
  }) {
    if (endpoints.length % floatsPerEndpointPair != 0) {
      throw ArgumentError.value(
        endpoints.length,
        'endpoints',
        'must hold $floatsPerEndpointPair floats per segment',
      );
    }
    _checkLength(colors, floatsPerColor, 'colors');
    _checkLength(progress, floatsPerProgress, 'progress');
    _checkLength(widthsPixels, 1, 'widthsPixels');
  }

  /// Six floats per segment: x0 y0 z0 x1 y1 z1.
  final Float32List endpoints;

  /// Four linear floats per segment (r g b a), or null for the style
  /// colour.
  final Float32List? colors;

  /// Two floats per segment: progress at the start and at the end. A
  /// batch's progress cursor dims what lies behind it.
  final Float32List? progress;

  /// One width in logical pixels per segment, or null for the style width.
  final Float32List? widthsPixels;

  int get segmentCount => endpoints.length ~/ floatsPerEndpointPair;

  void _checkLength(Float32List? list, int perSegment, String name) {
    if (list != null && list.length != segmentCount * perSegment) {
      throw ArgumentError.value(
        list.length,
        name,
        'must hold $perSegment floats for each of $segmentCount segments',
      );
    }
  }
}
