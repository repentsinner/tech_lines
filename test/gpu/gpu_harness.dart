import 'dart:io';
import 'dart:math' as math;

import 'package:tech_lines/tech_lines.dart';
import 'package:thermion_dart/src/filament/src/implementation/ffi_filament_app.dart';
import 'package:thermion_dart/thermion_dart.dart';

/// Distance from the perspective camera to the plane z = 0.
const cameraDistance = 10.0;

/// Distance from the orthographic camera to the plane z = 0. Its world
/// unit is a pixel, and the depth bias moves lines a few pixel sizes
/// towards the camera, so it needs room in depth.
const orthographicDistance = 1000.0;

/// Depth at which the tests place an occluder in front of the plane z = 0.
const occluderDepth = 100.0;

const _near = 0.1;
const _far = 2000.0;

/// Package prefix Flutter puts on the material asset keys; the tests read
/// the files relative to the package root instead.
const _assetPrefix = 'packages/tech_lines/';

bool _appCreated = false;

/// Backend the harness renders with. On macOS, Filament creates an OpenGL
/// headless swap chain on the main thread, which `dart test` never runs a
/// run loop on, so the creation never returns. Metal creates it on the
/// driver thread.
final _backend = Platform.isMacOS ? Backend.METAL : Backend.OPENGL;

/// Reads a material asset from the package's own directory.
Future<Uint8List> loadPackageAsset(String key) async =>
    File(key.replaceFirst(_assetPrefix, '')).readAsBytesSync();

/// A headless viewer rendering into an offscreen swap chain.
///
/// Nothing resamples the render target, so a capture shows exactly what
/// the shaders produced.
class GpuScene {
  GpuScene._(this.viewer, this.swapChain, this.width, this.height, this.lines);

  final ThermionViewer viewer;
  final SwapChain<dynamic> swapChain;
  final int width;
  final int height;
  final ScreenLineRenderer lines;

  /// Creates a scene of [width] × [height] target pixels.
  ///
  /// With [perspective] false the camera is orthographic and one world
  /// unit on the z = 0 plane spans exactly one target pixel, with the
  /// origin at the bottom-left corner of the target.
  static Future<GpuScene> create({
    int width = 256,
    int height = 256,
    bool perspective = false,
  }) async {
    if (!_appCreated) {
      await FFIFilamentApp.create(
        config: FFIFilamentConfig(
          loadResource: (uri) async =>
              File(uri.replaceAll('file://', '')).readAsBytesSync(),
          backend: _backend,
        ),
      );
      _appCreated = true;
    }
    final app = FilamentApp.instance!;
    final swapChain = await app.createHeadlessSwapChain(width, height);
    final viewer = ThermionViewerFFI(app: app as FFIFilamentApp);
    await viewer.initialized;
    await app.renderManager.attach(viewer.view, swapChain);
    await viewer.view.setViewport(width, height);
    await viewer.view.setPostProcessing(false);
    await app.setClearOptions(0, 0, 0, 1);

    final camera = await viewer.getActiveCamera();
    if (perspective) {
      // Thermion's default lens: 28 mm with a 0.1 near plane, as the app.
      await camera.setLensProjection(far: _far, aspect: width / height);
      await camera.lookAt(
        Vector3(0, 0, cameraDistance),
        focus: Vector3.zero(),
        up: Vector3(0, 1, 0),
      );
    } else {
      await camera.setProjection(
        Projection.Orthographic,
        0,
        width.toDouble(),
        0,
        height.toDouble(),
        _near,
        _far,
      );
      await camera.lookAt(
        Vector3(0, 0, orthographicDistance),
        focus: Vector3(0, 0, 0),
        up: Vector3(0, 1, 0),
      );
    }

    final lines = await ScreenLineRenderer.create(
      viewer: viewer,
      loadAsset: loadPackageAsset,
    );

    return GpuScene._(viewer, swapChain, width, height, lines);
  }

  /// Points the camera at the origin from [eye], with +y up.
  Future<void> lookAt(Vector3 eye) async {
    final camera = await viewer.getActiveCamera();
    await camera.lookAt(eye, focus: Vector3.zero(), up: Vector3(0, 1, 0));
  }

  /// Renders one frame and returns its red channel, row 0 at the bottom.
  Future<Coverage> capture() async {
    final frames = await FilamentApp.instance!.capture(
      swapChain,
      view: viewer.view,
    );
    final rgba = frames.first.$2.buffer.asFloat32List();
    final red = Float64List(width * height);
    for (var i = 0; i < red.length; i++) {
      red[i] = rgba[i * 4];
    }

    return Coverage(red, width, height);
  }

  /// Adds an unlit box of [size] centred at [center].
  ///
  /// Thermion's cube spans -1 to 1 on each axis, so it scales by half of
  /// [size].
  Future<ThermionAsset<dynamic>> addBox(
    Vector3 center,
    Vector3 size, {
    double r = 0,
    double g = 0,
    double b = 1,
  }) async {
    final material = await FilamentApp.instance!
        .createUbershaderMaterialInstance(unlit: true);
    await material.setParameterFloat4('baseColorFactor', r, g, b, 1);
    final box = await viewer.createGeometry(
      GeometryUtils.cube(),
      materialInstances: [material],
    );
    await box.setTransform(
      Matrix4.translation(center)..scaleByVector3(size / 2),
    );

    return box;
  }

  Future<void> dispose() async {
    await lines.dispose();
    await viewer.dispose();
    await FilamentApp.instance!.destroySwapChain(swapChain);
  }
}

/// One captured channel of the render target.
class Coverage {
  Coverage(this.values, this.width, this.height);

  final Float64List values;
  final int width;
  final int height;

  double at(int x, int y) => values[y * width + x];

  /// Sum of the channel over the rectangle [x0, x1) × [y0, y1).
  double sum(int x0, int y0, int x1, int y1) {
    var total = 0.0;
    for (var y = math.max(y0, 0); y < math.min(y1, height); y++) {
      for (var x = math.max(x0, 0); x < math.min(x1, width); x++) {
        total += at(x, y);
      }
    }

    return total;
  }

  /// Largest value in the rectangle [x0, x1) × [y0, y1).
  double max(int x0, int y0, int x1, int y1) {
    var peak = 0.0;
    for (var y = math.max(y0, 0); y < math.min(y1, height); y++) {
      for (var x = math.max(x0, 0); x < math.min(x1, width); x++) {
        peak = math.max(peak, at(x, y));
      }
    }

    return peak;
  }

  /// Full width at half maximum of column [x] between rows [y0] and [y1],
  /// in pixels, with the half-maximum crossings interpolated linearly.
  double fullWidthAtHalfMaximum(int x, int y0, int y1) {
    final profile = [for (var y = y0; y < y1; y++) at(x, y)];
    final peak = profile.reduce(math.max);
    final half = peak / 2;
    final first = profile.indexWhere((v) => v >= half);
    final last = profile.lastIndexWhere((v) => v >= half);
    if (first <= 0 || last >= profile.length - 1) return double.nan;
    double crossing(int inside, int outside) {
      final a = profile[outside];
      final b = profile[inside];

      return outside + (half - a) / (b - a) * (inside - outside);
    }

    return crossing(last, last + 1) - crossing(first, first - 1);
  }
}

/// Endpoints of one segment as the six floats [LineSegments] takes.
List<double> segment(Vector3 a, Vector3 b) => [a.x, a.y, a.z, b.x, b.y, b.z];
