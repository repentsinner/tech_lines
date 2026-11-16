import 'dart:typed_data';

import 'package:tech_lines/tech_lines.dart';
import 'package:test/test.dart';

void main() {
  group('packLineSegments', () {
    final twoSegments = LineSegments(
      endpoints: Float32List.fromList([
        0, 0, 0, 1, 0, 0, //
        1, 0, 0, 1, 2, 0,
      ]),
    );

    test('expands every segment to four vertices and two triangles', () {
      final packed = packLineSegments(twoSegments, widthPixels: 2);

      expect(packed.segmentCount, 2);
      expect(packed.vertexCount, 8);
      expect(packed.positions.length, 8 * 3);
      expect(packed.indices, [0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7]);
    });

    test('puts this endpoint in position and the other in custom0', () {
      final packed = packLineSegments(twoSegments, widthPixels: 2);

      // Corners 0 and 1 sit at the start, 2 and 3 at the end.
      expect(packed.positions.sublist(0, 12), [
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
      ]);
      expect(packed.attribute0.sublist(0, 16), [
        1, 0, 0, 2, //
        1, 0, 0, 2,
        0, 0, 0, 2,
        0, 0, 0, 2,
      ]);
    });

    test('encodes side and end in uv0', () {
      final packed = packLineSegments(twoSegments, widthPixels: 2);

      expect(packed.uvs.sublist(0, 8), [-1, 0, 1, 0, 1, 1, -1, 1]);
    });

    test('takes per-segment widths over the style width', () {
      final packed = packLineSegments(
        LineSegments(
          endpoints: twoSegments.endpoints,
          widthsPixels: Float32List.fromList([3, 0.5]),
        ),
        widthPixels: 2,
      );

      expect(packed.attribute0[3], 3);
      expect(packed.attribute0[4 * 4 + 3], 0.5);
    });

    test('repeats each segment colour on its four vertices', () {
      final packed = packLineSegments(
        LineSegments(
          endpoints: twoSegments.endpoints,
          colors: Float32List.fromList([1, 0, 0, 1, 0, 0, 1, 0.5]),
        ),
        widthPixels: 1,
      );

      expect(packed.hasVertexColors, isTrue);
      expect(packed.colors.sublist(12, 20), [1, 0, 0, 1, 0, 0, 1, 0.5]);
    });

    test('writes white when no colours are given', () {
      final packed = packLineSegments(twoSegments, widthPixels: 1);

      expect(packed.hasVertexColors, isFalse);
      expect(packed.colors.every((c) => c == 1), isTrue);
    });

    test('carries start progress at the start and end progress at the end', () {
      final packed = packLineSegments(
        LineSegments(
          endpoints: twoSegments.endpoints,
          progress: Float32List.fromList([0, 0.25, 0.25, 1]),
        ),
        widthPixels: 1,
      );

      expect(
        [for (var v = 0; v < 8; v++) packed.uvs1[v * 2]],
        [0, 0, 0.25, 0.25, 0.25, 0.25, 1, 1],
      );
    });

    test('indexes past the 16-bit limit', () {
      const count = 20000;
      final packed = packLineSegments(
        LineSegments(endpoints: Float32List(count * 6)),
        widthPixels: 1,
      );

      expect(packed.indices, isA<Uint32List>());
      expect(packed.indices.last, count * 4 - 1);
    });

    test('rejects buffers of the wrong length', () {
      expect(
        () => LineSegments(endpoints: Float32List(5)),
        throwsArgumentError,
      );
      expect(
        () => LineSegments(endpoints: Float32List(6), colors: Float32List(3)),
        throwsArgumentError,
      );
    });
  });
}
