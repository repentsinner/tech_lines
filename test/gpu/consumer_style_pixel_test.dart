// Pixel test for consumer styles (§spec:consumer-styles). Builds the test
// styles with tools/compile_style.sh, so it needs matc as well as a GPU.
@Tags(['gpu'])
library;

import 'dart:io';

import 'package:tech_lines/tech_lines.dart';
import 'package:test/test.dart';
import 'package:thermion_dart/thermion_dart.dart';

import 'gpu_harness.dart';

const _white = LinearRgba(1, 1, 1, 1);

/// A style no renderer loaded, as a consumer's tests might make.
class _StyleDouble implements ConsumerStyle {
  @override
  String get name => 'double';
}

/// The horizontal test line: x 28 to 228 on row 128.5, 4 px wide, so a
/// column's sum is its alpha times 4.
const _lineY = 128.5;
const _lineStart = 28.0;
const _lineEnd = 228.0;
const _lineWidth = 4.0;

/// Tolerance on a column's summed coverage, in target pixels.
const _columnTolerance = 0.05;

/// The fade test/styles/fade.fs applies: full at [center], zero from
/// [radius] out.
double _fade(double x, double center, double radius) {
  final t = ((x - center).abs() / radius).clamp(0.0, 1.0);

  return 1 - t * t * (3 - 2 * t);
}

void main() {
  late GpuScene scene;
  late Directory styles;
  late ConsumerStyle fade;
  late ConsumerStyle identity;

  Future<void> compileStyle(String name, {String? params}) async {
    final result = await Process.run('tools/compile_style.sh', [
      if (params != null) ...['--params', params],
      name,
      'test/styles/$name.fs',
      styles.path,
    ]);
    if (result.exitCode != 0) {
      fail('compile_style.sh $name failed:\n${result.stdout}${result.stderr}');
    }
  }

  Future<ConsumerStyle> load(String name) => scene.lines.loadStyle(
    bodyAsset: '${styles.path}/${name}_body.filamat',
    edgeAsset: '${styles.path}/${name}_edge.filamat',
  );

  setUpAll(() async {
    styles = Directory.systemTemp.createTempSync('consumer_styles_');
    await compileStyle('fade', params: 'test/styles/fade.params');
    await compileStyle('identity');
    scene = await GpuScene.create();
    fade = await load('fade');
    identity = await load('identity');
  });

  tearDownAll(() async {
    await scene.dispose();
    styles.deleteSync(recursive: true);
  });

  LineSegments line({List<double>? progress}) => LineSegments(
    endpoints: Float32List.fromList(
      segment(Vector3(_lineStart, _lineY, 0), Vector3(_lineEnd, _lineY, 0)),
    ),
    progress: progress == null ? null : Float32List.fromList(progress),
  );

  const butt = LineStyle(
    widthPixels: _lineWidth,
    color: _white,
    cap: LineCap.butt,
  );

  Future<LineBatch> fadedLine({
    required double center,
    required double radius,
    LineStyle style = butt,
    List<double>? progress,
  }) async {
    final batch = await scene.lines.createBatch(
      line(progress: progress),
      style,
      consumerStyle: fade,
    );
    await batch.setStyleParameter('fadeCenter', [center, _lineY, 0]);
    await batch.setStyleParameter('fadeRadius', [radius]);

    return batch;
  }

  double column(Coverage frame, int x) => frame.sum(x, 100, x + 1, 156);

  test('the identity style matches the built-in materials exactly', () async {
    // Lines that reach every part of the fragment stage: a fringe at an
    // angle, a translucent line, a dash, and a pulse with a glow.
    final batches = <(LineSegments, LineStyle, LinePulse?)>[
      (
        LineSegments(
          endpoints: Float32List.fromList(
            segment(Vector3(20, 30, 0), Vector3(230, 90, 0)),
          ),
        ),
        const LineStyle(widthPixels: 1.5, color: _white),
        null,
      ),
      (
        line(),
        const LineStyle(widthPixels: 3, color: _white, opacity: 0.4),
        null,
      ),
      (
        LineSegments(
          endpoints: Float32List.fromList(
            segment(Vector3(20, 200, 0), Vector3(230, 200, 0)),
          ),
          progress: Float32List.fromList([0, 1]),
        ),
        const LineStyle(
          widthPixels: 2,
          color: LinearRgba(0.2, 0.2, 0.2),
          dash: LineDash(6, 3),
        ),
        const LinePulse(center: 0.5, halfLength: 0.2, glowPixels: 3),
      ),
    ];

    Future<Coverage> draw(ConsumerStyle? consumerStyle) async {
      final drawn = <LineBatch>[];
      for (final (segments, style, pulse) in batches) {
        final batch = await scene.lines.createBatch(
          segments,
          style,
          consumerStyle: consumerStyle,
        );
        await batch.setPulse(pulse);
        drawn.add(batch);
      }
      final frame = await scene.capture();
      for (final batch in drawn) {
        await batch.destroy();
      }

      return frame;
    }

    final builtIn = await draw(null);
    final styled = await draw(identity);
    expect(styled.values, builtIn.values);
  });

  test('a style fades the line by world position', () async {
    final batch = await fadedLine(center: 128, radius: 80);
    final frame = await scene.capture();
    await batch.destroy();

    expect(column(frame, 128), closeTo(_lineWidth, _columnTolerance));
    expect(column(frame, 167), closeTo(_lineWidth * 0.5, 0.1));
    expect(column(frame, 215), 0);
  });

  test(
    'a fading style leaves no gap or double draw where the passes meet',
    () async {
      final batch = await fadedLine(center: 128, radius: 80);
      final frame = await scene.capture();
      await batch.destroy();

      // The body pass keeps the fully opaque middle and the edge pass
      // the rest, so a gap or an overlap where they meet would show as a
      // column off its expected sum.
      for (var x = _lineStart.toInt() + 1; x < _lineEnd.toInt() - 1; x++) {
        expect(
          column(frame, x),
          closeTo(_lineWidth * _fade(x + 0.5, 128, 80), _columnTolerance),
          reason: 'column $x',
        );
      }
    },
  );

  test('setStyleParameter moves the fade', () async {
    final batch = await fadedLine(center: 60, radius: 40);
    final frame = await scene.capture();
    await batch.destroy();

    expect(column(frame, 60), closeTo(_lineWidth, _columnTolerance));
    expect(column(frame, 128), 0);
  });

  test('the glow scale fades the pulse glow', () async {
    const pulse = LinePulse(
      center: 0.5,
      halfLength: 0.1,
      colorMix: 0,
      glowPixels: 4,
    );
    // Three pixels past the edge of the line at its middle, x = 128.
    double glowAt(Coverage frame) => frame.max(128, 133, 129, 134);

    final wide = await fadedLine(center: 128, radius: 1000, progress: [0, 1]);
    await wide.setPulse(pulse);
    final lit = await scene.capture();
    await wide.destroy();

    final away = await fadedLine(center: 28, radius: 40, progress: [0, 1]);
    await away.setPulse(pulse);
    final faded = await scene.capture();
    await away.destroy();

    expect(glowAt(lit), greaterThan(0.05));
    expect(glowAt(faded), 0);
  });

  test('the hidden-line pass runs the style', () async {
    // The box spans x 32–96, in front of the line.
    final box = await scene.addBox(
      Vector3(64, 128, occluderDepth),
      Vector3(64, 64, 1),
    );
    final batch = await fadedLine(
      center: 60,
      radius: 30,
      style: const LineStyle(
        widthPixels: _lineWidth,
        color: _white,
        cap: LineCap.butt,
        depthMode: LineDepthMode.hiddenStyled,
        hiddenOpacity: 0.5,
        // Solid, so one column measures the hidden pass's opacity.
        hiddenDash: null,
      ),
    );
    final frame = await scene.capture();
    await batch.destroy();
    await scene.viewer.destroyAsset(box);

    // Behind the box, at the fade's centre, the hidden pass draws at its
    // opacity; in the open, past the fade's radius, nothing draws.
    expect(column(frame, 60), closeTo(_lineWidth * 0.5, 0.1));
    expect(column(frame, 128), 0);
  });

  group('loadStyle', () {
    test('rejects a material compile_style.sh did not build', () {
      expect(
        scene.lines.loadStyle(
          bodyAsset: 'assets/materials/screen_line_body.filamat',
          edgeAsset: 'assets/materials/screen_line_edge.filamat',
        ),
        throwsA(isA<StyleTemplateException>()),
      );
    });

    test('rejects a body and edge passed the wrong way round', () {
      expect(
        scene.lines.loadStyle(
          bodyAsset: '${styles.path}/fade_edge.filamat',
          edgeAsset: '${styles.path}/fade_body.filamat',
        ),
        throwsA(isA<StyleTemplateException>()),
      );
    });

    test('rejects a body and edge from different styles', () {
      expect(
        scene.lines.loadStyle(
          bodyAsset: '${styles.path}/fade_body.filamat',
          edgeAsset: '${styles.path}/identity_edge.filamat',
        ),
        throwsA(isA<StyleTemplateException>()),
      );
    });
  });

  test('createBatch rejects a style the renderer did not load', () {
    expect(
      scene.lines.createBatch(line(), butt, consumerStyle: _StyleDouble()),
      throwsArgumentError,
    );
  });

  group('setStyleParameter', () {
    test('rejects a name the package sets itself', () async {
      final batch = await fadedLine(center: 128, radius: 80);
      await expectLater(
        batch.setStyleParameter('opacity', [0.5]),
        throwsArgumentError,
      );
      await batch.destroy();
    });

    test('rejects a batch drawn without a consumer style', () async {
      final batch = await scene.lines.createBatch(line(), butt);
      await expectLater(
        batch.setStyleParameter('fadeRadius', [1]),
        throwsStateError,
      );
      await batch.destroy();
    });
  });
}
