import 'dart:typed_data';

import 'line_segments.dart';

/// Vertices per segment: one per quad corner.
const lineVerticesPerSegment = 4;

/// Indices per segment: two triangles.
const lineIndicesPerSegment = 6;

/// `UV0.x` of a corner on each side of the line.
const _sideLeft = -1.0;
const _sideRight = 1.0;

/// `UV0.y` of a corner at the segment's start and at its end.
const _atStart = 0.0;
const _atEnd = 1.0;

/// Segment data in the per-vertex layout the line materials read.
///
/// Per vertex:
///   position    = this endpoint
///   CUSTOM0.xyz = the other endpoint, CUSTOM0.w = width in logical pixels
///   UV0         = (side, isEnd)
///   UV1         = (progress, 0)
///   COLOR       = linear RGBA
final class PackedLines {
  const PackedLines({
    required this.positions,
    required this.attribute0,
    required this.uvs,
    required this.uvs1,
    required this.colors,
    required this.indices,
    required this.hasVertexColors,
  });

  final Float32List positions;
  final Float32List attribute0;
  final Float32List uvs;
  final Float32List uvs1;
  final Float32List colors;
  final Uint32List indices;

  /// Whether [colors] came from the segments rather than defaulting to
  /// white.
  final bool hasVertexColors;

  int get vertexCount => positions.length ~/ 3;

  int get segmentCount => vertexCount ~/ lineVerticesPerSegment;
}

/// Packs [segments] into four vertices each, at [widthPixels] wherever the
/// segments carry no width of their own.
PackedLines packLineSegments(
  LineSegments segments, {
  required double widthPixels,
}) {
  final count = segments.segmentCount;
  final vertexCount = count * lineVerticesPerSegment;
  final positions = Float32List(vertexCount * 3);
  final attribute0 = Float32List(vertexCount * 4);
  final uvs = Float32List(vertexCount * 2);
  final uvs1 = Float32List(vertexCount * 2);
  final colors = Float32List(vertexCount * 4);
  final indices = Uint32List(count * lineIndicesPerSegment);

  final ends = segments.endpoints;
  final widths = segments.widthsPixels;
  final progress = segments.progress;
  final segmentColors = segments.colors;

  var v = 0;
  for (var s = 0; s < count; s++) {
    final e = s * floatsPerEndpointPair;
    final width = widths?[s] ?? widthPixels;
    final startProgress = progress?[s * floatsPerProgress] ?? 0.0;
    final endProgress = progress?[s * floatsPerProgress + 1] ?? 0.0;

    void corner(double side, double isEnd) {
      final here = isEnd == _atEnd ? e + 3 : e;
      final there = isEnd == _atEnd ? e : e + 3;
      positions
        ..[v * 3] = ends[here]
        ..[v * 3 + 1] = ends[here + 1]
        ..[v * 3 + 2] = ends[here + 2];
      attribute0
        ..[v * 4] = ends[there]
        ..[v * 4 + 1] = ends[there + 1]
        ..[v * 4 + 2] = ends[there + 2]
        ..[v * 4 + 3] = width;
      uvs
        ..[v * 2] = side
        ..[v * 2 + 1] = isEnd;
      uvs1[v * 2] = isEnd == _atEnd ? endProgress : startProgress;
      if (segmentColors == null) {
        colors.fillRange(v * 4, v * 4 + 4, 1);
      } else {
        colors.setRange(v * 4, v * 4 + 4, segmentColors, s * floatsPerColor);
      }
      v++;
    }

    final base = v;
    corner(_sideLeft, _atStart);
    corner(_sideRight, _atStart);
    corner(_sideRight, _atEnd);
    corner(_sideLeft, _atEnd);

    final i = s * lineIndicesPerSegment;
    indices
      ..[i] = base
      ..[i + 1] = base + 1
      ..[i + 2] = base + 2
      ..[i + 3] = base
      ..[i + 4] = base + 2
      ..[i + 5] = base + 3;
  }

  return PackedLines(
    positions: positions,
    attribute0: attribute0,
    uvs: uvs,
    uvs1: uvs1,
    colors: colors,
    indices: indices,
    hasVertexColors: segmentColors != null,
  );
}
