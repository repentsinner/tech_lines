// Pixel test for the line renderer. Renders headless, where
// nothing resamples the target, so every figure here is the shader's own.
@Tags(['gpu'])
library;

import 'dart:math' as math;

import 'package:tech_lines/tech_lines.dart';
import 'package:test/test.dart';
import 'package:thermion_dart/thermion_dart.dart';

import 'gpu_harness.dart';

/// Pass criteria from the specification.
const _widthTolerancePx = 0.1;
const _thinCoverageTolerance = 0.10;
const _subPixelSpreadTolerance = 0.05;

/// Sub-pixel offsets per case, and the grid of cells that holds them.
const _offsets = 16;
const _cellsPerRow = 4;
const _cellPx = 64;

/// Length of each test segment in target pixels.
const _lengthPx = 40.0;

const _white = LinearRgba(1, 1, 1, 1);

void main() {
  late GpuScene scene;

  setUpAll(() async {
    scene = await GpuScene.create();
  });

  tearDownAll(() async {
    await scene.dispose();
  });

  /// Draws one segment per sub-pixel offset at [angleDegrees], one per
  /// cell, and returns each cell's coverage integral, plus the FWHM at
  /// each cell's centre column when the segments are horizontal.
  Future<({List<double> integrals, List<double> columns, List<double> fwhm})>
  sweep(double widthPx, double angleDegrees) async {
    final angle = angleDegrees * math.pi / 180;
    final dir = Vector3(math.cos(angle), math.sin(angle), 0);
    final normal = Vector3(-dir.y, dir.x, 0);
    final endpoints = <double>[];
    for (var k = 0; k < _offsets; k++) {
      final cx = (k % _cellsPerRow) * _cellPx + _cellPx / 2;
      final cy = (k ~/ _cellsPerRow) * _cellPx + _cellPx / 2;
      final center = Vector3(cx, cy, 0) + normal * (k / _offsets);
      endpoints.addAll(
        segment(center - dir * (_lengthPx / 2), center + dir * (_lengthPx / 2)),
      );
    }
    final batch = await scene.lines.createBatch(
      LineSegments(endpoints: Float32List.fromList(endpoints)),
      LineStyle(widthPixels: widthPx, color: _white, cap: LineCap.butt),
    );
    final frame = await scene.capture();
    await batch.destroy();

    final integrals = <double>[];
    final columns = <double>[];
    final fwhm = <double>[];
    for (var k = 0; k < _offsets; k++) {
      final x0 = (k % _cellsPerRow) * _cellPx;
      final y0 = (k ~/ _cellsPerRow) * _cellPx;
      integrals.add(frame.sum(x0, y0, x0 + _cellPx, y0 + _cellPx));
      if (angleDegrees == 0) {
        final x = x0 + _cellPx ~/ 2;
        columns.add(frame.sum(x, y0, x + 1, y0 + _cellPx));
        fwhm.add(frame.fullWidthAtHalfMaximum(x, y0, y0 + _cellPx));
      }
    }

    return (integrals: integrals, columns: columns, fwhm: fwhm);
  }

  double mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;
  double spread(List<double> v) {
    final m = mean(v);
    final variance =
        v.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / v.length;

    return math.sqrt(variance) / m;
  }

  group('width and coverage', () {
    for (final angle in [0.0, 22.5, 45.0, 90.0]) {
      for (final width in [1.0, 1.5, 2.0, 3.0]) {
        test('$width px at $angle° holds its width at every offset', () async {
          final r = await sweep(width, angle);

          expect(mean(r.integrals) / (width * _lengthPx), closeTo(1, 0.03));
          expect(spread(r.integrals), lessThan(_subPixelSpreadTolerance));
          // A column's sum is the drawn width at any sub-pixel offset.
          for (final c in r.columns) {
            expect(c, closeTo(width, _widthTolerancePx));
          }
          // Half-maximum width read from pixel samples is only defined
          // once a line spans two pixels: a 1 px line half a pixel off
          // centre samples as two pixels at half intensity.
          if (width >= 2) {
            for (final f in r.fwhm) {
              expect(f, closeTo(width, _widthTolerancePx));
            }
          }
        });
      }
      for (final width in [0.25, 0.5, 0.75]) {
        test('$width px at $angle° fades in proportion to width', () async {
          final r = await sweep(width, angle);

          expect(
            mean(r.integrals) / (width * _lengthPx),
            closeTo(1, _thinCoverageTolerance),
          );
          expect(spread(r.integrals), lessThan(_subPixelSpreadTolerance));
        });
      }
    }
  });

  test('opacity applies to every fragment', () async {
    final batch = await scene.lines.createBatch(
      LineSegments(
        endpoints: Float32List.fromList(
          segment(Vector3(40, 128.5, 0), Vector3(216, 128.5, 0)),
        ),
      ),
      const LineStyle(widthPixels: 4, color: _white, opacity: 0.4),
    );
    final frame = await scene.capture();
    await batch.destroy();

    expect(frame.max(0, 0, 256, 256), closeTo(0.4, 0.01));
  });

  test(
    'a segment colour owns its alpha in place of the style colour',
    () async {
      final batch = await scene.lines.createBatch(
        LineSegments(
          endpoints: Float32List.fromList(
            segment(Vector3(40, 128.5, 0), Vector3(216, 128.5, 0)),
          ),
          colors: Float32List.fromList([1, 1, 1, 0.5]),
        ),
        const LineStyle(widthPixels: 4, color: LinearRgba(1, 1, 1, 0.5)),
      );
      final frame = await scene.capture();
      await batch.destroy();

      expect(frame.max(0, 0, 256, 256), closeTo(0.5, 0.01));
    },
  );

  test('rewritten vertex colours replace the uploaded ones', () async {
    final endpoints = Float32List.fromList(
      segment(Vector3(40, 128.5, 0), Vector3(216, 128.5, 0)),
    );
    final packed = packLineSegments(
      LineSegments(
        endpoints: endpoints,
        colors: Float32List.fromList([1, 1, 1, 1]),
      ),
      widthPixels: 4,
    );
    final batch = await scene.lines.createPackedBatch(
      packed,
      const LineStyle(widthPixels: 4, color: _white),
    );
    final before = await scene.capture();
    final dark = packLineSegments(
      LineSegments(
        endpoints: endpoints,
        colors: Float32List.fromList([0.25, 0, 0, 1]),
      ),
      widthPixels: 4,
    );
    expect(batch.colorsWritable, isTrue);
    final written = await batch.writeColors(dark.colors);
    final after = await scene.capture();
    await batch.destroy();

    expect(written, isTrue);
    expect(batch.colorsWritable, isFalse);
    await batch.setColor(_white);
    expect(before.max(0, 0, 256, 256), closeTo(1, 0.01));
    expect(after.max(0, 0, 256, 256), closeTo(0.25, 0.01));
  });

  test('pixel scale multiplies the logical width', () async {
    await scene.lines.setPixelScale(2);
    final batch = await scene.lines.createBatch(
      LineSegments(
        endpoints: Float32List.fromList(
          segment(Vector3(40, 128.5, 0), Vector3(216, 128.5, 0)),
        ),
      ),
      const LineStyle(widthPixels: 1.5, color: _white),
    );
    final frame = await scene.capture();
    await batch.destroy();
    await scene.lines.setPixelScale(1);

    expect(frame.fullWidthAtHalfMaximum(128, 100, 156), closeTo(3, 0.1));
  });

  test('round caps reach half a width past each endpoint', () async {
    const width = 6.0;
    final batch = await scene.lines.createBatch(
      LineSegments(
        endpoints: Float32List.fromList(
          segment(Vector3(100, 128.5, 0), Vector3(150, 128.5, 0)),
        ),
      ),
      const LineStyle(widthPixels: width, color: _white),
    );
    final frame = await scene.capture();
    await batch.destroy();

    // A capsule: a 50 × 6 box plus a disc of diameter 6.
    const area = 50 * width + math.pi * (width / 2) * (width / 2);
    expect(frame.sum(0, 0, 256, 256), closeTo(area, area * 0.02));
  });

  group('depth', () {
    test('a mesh in front hides the line behind it', () async {
      final box = await scene.addBox(
        Vector3(64, 128, occluderDepth),
        Vector3(64, 64, 1),
      );
      final batch = await scene.lines.createBatch(
        LineSegments(
          endpoints: Float32List.fromList(
            segment(Vector3(16, 128.5, 0), Vector3(240, 128.5, 0)),
          ),
        ),
        const LineStyle(widthPixels: 3, color: _white),
      );
      final frame = await scene.capture();
      await batch.destroy();
      await scene.viewer.destroyAsset(box);

      // The box spans x 32–96; its own red channel is zero.
      expect(frame.max(40, 110, 88, 146), 0);
      expect(frame.max(120, 110, 230, 146), greaterThan(0.99));
    });

    // A line piercing a face, in the orthographic scene: the box fills
    // the frame behind z = 0, and the line climbs from z = -h to z = +h
    // across x 28–228, so it enters the face at x = 128. Left of that it
    // is behind the face.
    for (final rise in [100.0, 25.0]) {
      test(
        'a line piercing a face at rise $rise stops near the surface',
        () async {
          final box = await scene.addBox(
            Vector3(128, 128, -200),
            Vector3(512, 512, 400),
          );
          final batch = await scene.lines.createBatch(
            LineSegments(
              endpoints: Float32List.fromList(
                segment(Vector3(28, 128.5, -rise), Vector3(228, 128.5, rise)),
              ),
            ),
            const LineStyle(widthPixels: 2, color: _white, cap: LineCap.butt),
          );
          final frame = await scene.capture();
          await batch.destroy();
          await scene.viewer.destroyAsset(box);

          // The first column, from the left, where the line shows.
          var cut = -1;
          for (var x = 0; x < 256; x++) {
            if (frame.max(x, 120, x + 1, 137) > 0.5) {
              cut = x;
              break;
            }
          }
          // The bias draws the line in front of the face by its reach
          // times the slope factor in pixel sizes, so the cut moves along
          // the line by that depth over the line's rise per pixel.
          const reach = 1 + 0.5 * 1;
          const shift = reach * defaultLineDepthSlopeBias;
          final risePerPixel = 2 * rise / 200;
          final expected = 128 - shift / risePerPixel;
          print(
            'rise $rise: cut at x = $cut, surface at 128, '
            'predicted ${expected.toStringAsFixed(1)}',
          );
          expect(cut, inInclusiveRange(expected.floor() - 1, 128));
        },
      );
    }

    test('an on-top line draws over a mesh in front', () async {
      final box = await scene.addBox(
        Vector3(64, 128, occluderDepth),
        Vector3(64, 64, 1),
      );
      final batch = await scene.lines.createBatch(
        LineSegments(
          endpoints: Float32List.fromList(
            segment(Vector3(16, 128.5, 0), Vector3(240, 128.5, 0)),
          ),
        ),
        const LineStyle(
          widthPixels: 3,
          color: _white,
          depthMode: LineDepthMode.onTop,
        ),
      );
      final frame = await scene.capture();
      await batch.destroy();
      await scene.viewer.destroyAsset(box);

      expect(frame.max(40, 110, 88, 146), greaterThan(0.99));
    });

    test('a hidden-line style draws the occluded part dimmed', () async {
      final box = await scene.addBox(
        Vector3(64, 128, occluderDepth),
        Vector3(64, 64, 1),
      );
      final batch = await scene.lines.createBatch(
        LineSegments(
          endpoints: Float32List.fromList(
            segment(Vector3(16, 128.5, 0), Vector3(240, 128.5, 0)),
          ),
        ),
        const LineStyle(
          widthPixels: 3,
          color: _white,
          depthMode: LineDepthMode.hiddenStyled,
          hiddenOpacity: 0.3,
        ),
      );
      final frame = await scene.capture();
      await batch.destroy();
      await scene.viewer.destroyAsset(box);

      expect(frame.max(40, 110, 88, 146), closeTo(0.3, 0.02));
      expect(frame.max(120, 110, 230, 146), greaterThan(0.99));
    });
  });

  group('present scale', () {
    tearDown(() => scene.lines.setPresentScale(1));

    Future<Coverage> horizontal(double width, double y) async {
      final batch = await scene.lines.createBatch(
        LineSegments(
          endpoints: Float32List.fromList(
            segment(Vector3(28, y, 0), Vector3(228, y, 0)),
          ),
        ),
        LineStyle(widthPixels: width, color: _white, cap: LineCap.butt),
      );
      final frame = await scene.capture();
      await batch.destroy();

      return frame;
    }

    test('below 1 widens the ramp and keeps the summed width', () async {
      await scene.lines.setPresentScale(0.5);
      final frame = await horizontal(3, 128.5);

      // The ramp spans 1/s = 2 target pixels: the column sum still equals
      // the width, and the half-maximum width holds too.
      expect(frame.sum(128, 100, 129, 156), closeTo(3, 0.1));
      expect(frame.fullWidthAtHalfMaximum(128, 100, 156), closeTo(3, 0.1));
      // But the ramp reaches a pixel past the edge that s = 1 leaves dark.
      await scene.lines.setPresentScale(1);
      final sharp = await horizontal(3, 128.5);
      expect(sharp.max(128, 125, 129, 126), 0);
      expect(frame.max(128, 125, 129, 126), greaterThan(0.2));
    });

    test('below 1 draws a thin line at least 1/s pixels wide', () async {
      await scene.lines.setPresentScale(0.5);
      final frame = await horizontal(0.5, 128.5);

      expect(frame.sum(128, 100, 129, 156), closeTo(0.5, 0.05));
      // Two target pixels wide, so no row holds more than half of it.
      expect(frame.max(128, 100, 129, 156), lessThan(0.3));
    });

    test('above 1 changes nothing', () async {
      await scene.lines.setPresentScale(1.5);
      final frame = await horizontal(1, 128.5);
      await scene.lines.setPresentScale(1);
      final reference = await horizontal(1, 128.5);

      expect(frame.values, reference.values);
    });
  });

  group('pulse', () {
    // A horizontal line from x 28 to 228 whose progress runs 0 to 1 by
    // arc length: two segments, the first a quarter of the length.
    Future<LineBatch> pulsedLine() => scene.lines.createBatch(
      LineSegments(
        endpoints: Float32List.fromList([
          ...segment(Vector3(28, 128.5, 0), Vector3(78, 128.5, 0)),
          ...segment(Vector3(78, 128.5, 0), Vector3(228, 128.5, 0)),
        ]),
        progress: Float32List.fromList([0, 0.25, 0.25, 1]),
      ),
      const LineStyle(
        widthPixels: 3,
        color: LinearRgba(0, 0, 0),
        cap: LineCap.butt,
      ),
    );

    test('colors the band around its center by arc length', () async {
      final batch = await pulsedLine();
      await batch.setPulse(const LinePulse(center: 0.5, halfLength: 0.05));
      final frame = await scene.capture();
      await batch.destroy();

      // Progress 0.5 is x = 128, the line's geometric middle, though it
      // lies in the second of two segments.
      expect(frame.max(126, 120, 131, 137), greaterThan(0.95));
      // Outside the band the line keeps its black.
      expect(frame.max(40, 120, 100, 137), 0);
      expect(frame.max(150, 120, 220, 137), 0);
    });

    test('widens the line in the band', () async {
      final batch = await pulsedLine();
      await batch.setColor(const LinearRgba(1, 1, 1));
      await batch.setPulse(
        const LinePulse(center: 0.5, halfLength: 0.1, widthScale: 3),
      );
      final frame = await scene.capture();
      await batch.destroy();

      expect(frame.sum(128, 100, 129, 156), closeTo(9, 0.3));
      expect(frame.sum(60, 100, 61, 156), closeTo(3, 0.1));
    });

    test('adds a glow outside the line in the band', () async {
      final batch = await pulsedLine();
      await batch.setPulse(
        const LinePulse(
          center: 0.5,
          halfLength: 0.1,
          colorMix: 0,
          glowPixels: 4,
        ),
      );
      final frame = await scene.capture();
      await batch.destroy();

      // Three pixels past the line's edge, in the band and out of it.
      expect(frame.max(128, 133, 129, 134), greaterThan(0.05));
      expect(frame.max(60, 133, 61, 134), 0);
    });

    test('fades the band to an opacity', () async {
      final batch = await pulsedLine();
      await batch.setColor(const LinearRgba(1, 1, 1));
      await batch.setPulse(
        const LinePulse(center: 0.5, halfLength: 0.1, opacity: 0.25),
      );
      final frame = await scene.capture();
      await batch.destroy();

      expect(frame.max(127, 120, 130, 137), closeTo(0.25, 0.02));
      expect(frame.max(60, 120, 61, 137), closeTo(1, 0.01));
    });

    test('a null pulse draws the line unchanged', () async {
      final batch = await pulsedLine();
      await batch.setColor(const LinearRgba(1, 1, 1));
      await batch.setPulse(
        const LinePulse(center: 0.5, halfLength: 0.1, widthScale: 3),
      );
      await batch.setPulse(null);
      final frame = await scene.capture();
      await batch.destroy();

      expect(frame.sum(128, 100, 129, 156), closeTo(3, 0.1));
    });
  });

  group('progress and visibility', () {
    Future<LineBatch> progressLine() => scene.lines.createBatch(
      LineSegments(
        endpoints: Float32List.fromList(
          segment(Vector3(28, 128.5, 0), Vector3(228, 128.5, 0)),
        ),
        progress: Float32List.fromList([0, 1]),
      ),
      const LineStyle(widthPixels: 3, color: _white, cap: LineCap.butt),
    );

    test('dims what lies behind the cursor', () async {
      final batch = await progressLine();
      await batch.setProgress(0.5);
      final frame = await scene.capture();
      await batch.destroy();

      expect(frame.max(40, 120, 110, 136), closeTo(0.3, 0.01));
      expect(frame.max(140, 120, 220, 136), closeTo(1, 0.01));
    });

    test('a hidden batch draws nothing until shown again', () async {
      final batch = await progressLine();
      await batch.setVisible(false);
      final hidden = await scene.capture();
      await batch.setVisible(true);
      final shown = await scene.capture();
      await batch.destroy();

      expect(hidden.max(0, 0, 256, 256), 0);
      expect(shown.max(0, 0, 256, 256), greaterThan(0.99));
    });
  });

  group('perspective', () {
    late GpuScene view;

    setUpAll(() async {
      view = await GpuScene.create(perspective: true);
    });

    tearDownAll(() async {
      await view.dispose();
    });

    for (final depth in [0.0, -20.0]) {
      test('width holds in pixels at depth $depth', () async {
        await view.lookAt(Vector3(0, 0, cameraDistance));
        final batch = await view.lines.createBatch(
          LineSegments(
            endpoints: Float32List.fromList(
              segment(Vector3(-1, 0.01, depth), Vector3(1, 0.01, depth)),
            ),
          ),
          const LineStyle(widthPixels: 3, color: _white),
        );
        final frame = await view.capture();
        await batch.destroy();

        expect(frame.fullWidthAtHalfMaximum(128, 100, 156), closeTo(3, 0.1));
      });
    }

    group('perspective width', () {
      tearDown(() => view.lines.setPerspectiveWidth(null));

      for (final (depth, expected) in [(0.0, 3.0), (-10.0, 1.5)]) {
        test('at depth $depth draws $expected px', () async {
          await view.lookAt(Vector3(0, 0, cameraDistance));
          await view.lines.setPerspectiveWidth(cameraDistance);
          final batch = await view.lines.createBatch(
            LineSegments(
              endpoints: Float32List.fromList(
                segment(Vector3(-1, 0.01, depth), Vector3(1, 0.01, depth)),
              ),
            ),
            const LineStyle(widthPixels: 3, color: _white),
          );
          final frame = await view.capture();
          await batch.destroy();

          // Summed coverage is the drawn width at any sub-pixel offset.
          expect(frame.sum(128, 0, 129, 256), closeTo(expected, 0.1));
        });
      }

      test('keeps a segment through the camera plane visible', () async {
        await view.lookAt(Vector3(0, 0, cameraDistance));
        await view.lines.setPerspectiveWidth(cameraDistance);
        final batch = await view.lines.createBatch(
          LineSegments(
            endpoints: Float32List.fromList(
              segment(Vector3(0.5, -0.5, 30), Vector3(0.5, -0.5, -30)),
            ),
          ),
          const LineStyle(widthPixels: 2, color: _white),
        );
        final frame = await view.capture();
        await batch.destroy();

        final total = frame.sum(0, 0, 256, 256);
        expect(total.isFinite, isTrue);
        expect(total, greaterThan(50));
      });

      test('tapers a segment receding from the camera', () async {
        await view.lookAt(Vector3(0, 0, cameraDistance));
        await view.lines.setPerspectiveWidth(cameraDistance);
        // From x = -1 at depth 0 to x = +1 at depth -10: the near end
        // draws 3 px wide and the far end 1.5.
        final batch = await view.lines.createBatch(
          LineSegments(
            endpoints: Float32List.fromList(
              segment(Vector3(-1, 0.01, 0), Vector3(1, 0.01, -10)),
            ),
          ),
          const LineStyle(widthPixels: 3, color: _white, cap: LineCap.butt),
        );
        final frame = await view.capture();
        await batch.destroy();

        // Columns near each end, inside the segment.
        var first = -1, last = -1;
        for (var x = 0; x < 256; x++) {
          if (frame.max(x, 0, x + 1, 256) > 0.5) {
            if (first < 0) first = x;
            last = x;
          }
        }
        final near = frame.sum(first + 2, 0, first + 3, 256);
        final far = frame.sum(last - 2, 0, last - 1, 256);
        expect(near, greaterThan(far * 1.6));
      });
    });

    test('a segment through the camera plane stays a bounded line', () async {
      await view.lookAt(Vector3(0, 0, cameraDistance));
      final batch = await view.lines.createBatch(
        LineSegments(
          endpoints: Float32List.fromList(
            segment(Vector3(0.5, -0.5, 30), Vector3(0.5, -0.5, -30)),
          ),
        ),
        const LineStyle(widthPixels: 2, color: _white),
      );
      final frame = await view.capture();
      await batch.destroy();

      final total = frame.sum(0, 0, 256, 256);
      expect(total.isFinite, isTrue);
      // The visible part runs from the edge of the frame towards the
      // vanishing point: at most a frame diagonal of 2 px line.
      expect(total, greaterThan(50));
      expect(total, lessThan(2 * 256 * math.sqrt2));
    });

    for (final incidence in [30.0, 60.0, 75.0]) {
      test('a line on a face at $incidence° shows no stipple', () async {
        final a = incidence * math.pi / 180;
        await view.lookAt(
          Vector3(0, -math.sin(a), math.cos(a)) * cameraDistance,
        );
        final line = LineSegments(
          endpoints: Float32List.fromList(
            segment(Vector3(-1.5, 0, 0), Vector3(1.5, 0, 0)),
          ),
        );
        const style = LineStyle(widthPixels: 2, color: _white);

        final alone = await view.lines.createBatch(line, style);
        final reference = (await view.capture()).sum(0, 0, 256, 256);
        await alone.destroy();

        // The box's front face lies in the z = 0 plane, under the line.
        final box = await view.addBox(Vector3(0, 0, -0.5), Vector3(20, 20, 1));
        final onFace = await view.lines.createBatch(line, style);
        final drawn = (await view.capture()).sum(0, 0, 256, 256);
        await onFace.destroy();
        await view.viewer.destroyAsset(box);

        expect(drawn / reference, closeTo(1, 0.02));
      });
    }

    test('without the slope bias the face hides part of the line', () async {
      const a = 60 * math.pi / 180;
      await view.lookAt(Vector3(0, -math.sin(a), math.cos(a)) * cameraDistance);
      final unbiased = await ScreenLineRenderer.create(
        viewer: view.viewer,
        loadAsset: loadPackageAsset,
        depthSlopeBias: 0,
      );
      final box = await view.addBox(Vector3(0, 0, -0.5), Vector3(20, 20, 1));
      final batch = await unbiased.createBatch(
        LineSegments(
          endpoints: Float32List.fromList(
            segment(Vector3(-1.5, 0, 0), Vector3(1.5, 0, 0)),
          ),
        ),
        const LineStyle(widthPixels: 2, color: _white),
      );
      final drawn = (await view.capture()).sum(0, 0, 256, 256);
      await batch.destroy();
      await unbiased.dispose();
      await view.viewer.destroyAsset(box);

      // The 2 px line spans two rows; the face covers the nearer one.
      expect(drawn, lessThan(0.75 * 2 * 91));
    });
  });
}
