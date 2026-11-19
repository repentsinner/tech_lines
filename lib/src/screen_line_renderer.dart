import 'dart:math' as math;

import 'package:logging/logging.dart';
import 'package:thermion_dart/thermion_dart.dart';

import 'consumer_style.dart';
import 'filamat_header.dart';
import 'line_packer.dart';
import 'line_segments.dart';
import 'line_style.dart';

final _log = Logger('ScreenLineRenderer');

/// Loads the bytes of an asset by its key.
typedef AssetLoader = Future<Uint8List> Function(String key);

/// Material parameter names, as declared in the package's `.mat` files.
abstract final class ScreenLineParams {
  static const lineColor = 'lineColor';
  static const opacity = 'opacity';
  static const vertexColorMix = 'vertexColorMix';
  static const pixelScale = 'pixelScale';
  static const rampScale = 'rampScale';
  static const widthReferenceDepth = 'widthReferenceDepth';
  static const capStyle = 'capStyle';
  static const depthBias = 'depthBias';
  static const depthSlopeBias = 'depthSlopeBias';
  static const dash = 'dash';
  static const progressCursor = 'progressCursor';
  static const progressWindowEnd = 'progressWindowEnd';
  static const progressDim = 'progressDim';
  static const progressBoost = 'progressBoost';
  static const edgeDrawsAll = 'edgeDrawsAll';
  static const pulseCenter = 'pulseCenter';
  static const pulseHalfLength = 'pulseHalfLength';
  static const pulseColor = 'pulseColor';
  static const pulseOpacity = 'pulseOpacity';
  static const pulseWidthScale = 'pulseWidthScale';
  static const pulseGlowPixels = 'pulseGlowPixels';
  static const pulseFade = 'pulseFade';

  /// Every name above. A consumer style's own parameters shall not reuse
  /// one (§spec:consumer-styles).
  static const all = {
    lineColor,
    opacity,
    vertexColorMix,
    pixelScale,
    rampScale,
    widthReferenceDepth,
    capStyle,
    depthBias,
    depthSlopeBias,
    dash,
    progressCursor,
    progressWindowEnd,
    progressDim,
    progressBoost,
    edgeDrawsAll,
    pulseCenter,
    pulseHalfLength,
    pulseColor,
    pulseOpacity,
    pulseWidthScale,
    pulseGlowPixels,
    pulseFade,
  };
}

/// A consumer style's two materials, loaded by
/// [ScreenLineRenderer.loadStyle] (§spec:consumer-styles).
///
/// Pass it to [ScreenLineRenderer.createBatch] to draw a batch in the
/// style. The renderer that loaded it owns its materials and destroys them
/// in [ScreenLineRenderer.dispose].
///
/// A consumer's tests may implement it, to hand a style to a renderer
/// they mock. A renderer draws only in a style its own
/// [ScreenLineRenderer.loadStyle] returned.
class ConsumerStyle {
  ConsumerStyle._(this.name, this._body, this._edge);

  /// The style's name, as `tools/compile_style.sh` was given it.
  final String name;

  final Material<dynamic> _body;
  final Material<dynamic> _edge;
}

/// Fraction of its distance from the camera that a line moves towards it,
/// for depth precision.
const defaultLineDepthBias = 1e-4;

/// Pixel sizes a line moves towards the camera per pixel of its reach, so
/// a line drawn on a face wins the depth test against it.
///
/// A face at incidence a rises tan(a) pixel sizes per pixel, so 4 covers
/// faces up to about 76°. A larger factor covers steeper faces but lets a
/// line show through an occluder that close in depth.
const defaultLineDepthSlopeBias = 4.0;

/// Progress value that turns the progress cursor and window off.
const _progressOff = -1.0;

/// Draws lines at a constant width in screen pixels into a Thermion
/// scene.
///
/// Every batch is a body pass of opaque, fully covered fragments that
/// writes depth, and an edge pass that blends the rest: the anti-aliased
/// rim, and all of a translucent or sub-pixel line.
class ScreenLineRenderer {
  ScreenLineRenderer._(
    this._viewer,
    this._loadAsset,
    this._body,
    this._edge,
    this._pixelScale,
    this.depthBias,
    this.depthSlopeBias,
  );

  /// Asset key of the body material, as Flutter serves package assets.
  static const bodyMaterialAsset =
      'packages/tech_lines/assets/materials/screen_line_body.filamat';

  /// Asset key of the edge material, as Flutter serves package assets.
  static const edgeMaterialAsset =
      'packages/tech_lines/assets/materials/screen_line_edge.filamat';

  /// Loads both line materials through [loadAsset] and returns a renderer
  /// drawing into [viewer]'s scene.
  ///
  /// [pixelScale] is target pixels per logical pixel, the device pixel
  /// ratio in a Flutter view. Throws [FilamatVersionException] when the
  /// materials were compiled for a different Filament release.
  static Future<ScreenLineRenderer> create({
    required ThermionViewer viewer,
    required AssetLoader loadAsset,
    double pixelScale = 1,
    double depthBias = defaultLineDepthBias,
    double depthSlopeBias = defaultLineDepthSlopeBias,
  }) async {
    Future<Material<dynamic>> load(String key) async {
      final bytes = await loadAsset(key);
      // Filament aborts the render thread on a package it cannot parse,
      // so reject a stale one here, where the error is catchable.
      assertFilamatCompatible(bytes, key);

      return FilamentApp.instance!.createMaterial(bytes);
    }

    final body = await load(bodyMaterialAsset);
    final edge = await load(edgeMaterialAsset);

    return ScreenLineRenderer._(
      viewer,
      loadAsset,
      body,
      edge,
      pixelScale,
      depthBias,
      depthSlopeBias,
    );
  }

  /// Loads a consumer style's materials, which `tools/compile_style.sh`
  /// built, through the renderer's asset loader (§spec:consumer-styles).
  ///
  /// Throws [FilamatVersionException] when either material was compiled
  /// for a different Filament release, and [StyleTemplateException] when
  /// either was built from other line material templates, the two
  /// are each other's pass, or they belong to different styles.
  Future<ConsumerStyle> loadStyle({
    required String bodyAsset,
    required String edgeAsset,
  }) async {
    final bodyBytes = await _loadAsset(bodyAsset);
    final edgeBytes = await _loadAsset(edgeAsset);
    final name = checkConsumerStyle(
      bodyBytes,
      bodyAsset,
      ConsumerStylePass.body,
    );
    final edgeName = checkConsumerStyle(
      edgeBytes,
      edgeAsset,
      ConsumerStylePass.edge,
    );
    if (edgeName != name) {
      throw StyleTemplateException(
        assetPath: edgeAsset,
        found: styleTemplateRevision,
        expected: styleTemplateRevision,
        message:
            'is the edge material of style "$edgeName", loaded with the '
            'body material of style "$name".',
      );
    }
    final style = ConsumerStyle._(
      name,
      await FilamentApp.instance!.createMaterial(bodyBytes),
      await FilamentApp.instance!.createMaterial(edgeBytes),
    );
    _styles.add(style);

    return style;
  }

  final ThermionViewer _viewer;
  final AssetLoader _loadAsset;
  final Material<dynamic> _body;
  final Material<dynamic> _edge;
  final List<ConsumerStyle> _styles = [];
  double _pixelScale;

  /// Relative depth bias every new batch draws with.
  final double depthBias;

  /// Depth bias in pixel sizes per pixel of reach for every new batch.
  final double depthSlopeBias;

  final Set<LineBatch> _batches = {};

  double get pixelScale => _pixelScale;

  double _rampScale = 1;

  /// No reference depth: widths are in screen pixels at every depth.
  static const _screenWidths = 0.0;

  double _widthReferenceDepth = _screenWidths;

  /// Draws every line at its width at [referenceDepth] from the camera and
  /// scales it by reference over depth elsewhere, as geometry of fixed
  /// thickness would foreshorten in perspective; null draws widths in
  /// screen pixels at every depth. An orthographic view keeps screen
  /// widths either way.
  Future<void> setPerspectiveWidth(double? referenceDepth) async {
    final depth = referenceDepth ?? _screenWidths;
    if (depth == _widthReferenceDepth) return;
    _widthReferenceDepth = depth;
    for (final batch in _batches) {
      await batch._setAll(ScreenLineParams.widthReferenceDepth, depth);
    }
  }

  /// Sets the present scale: panel pixels per render-target pixel after
  /// any resample the platform applies to the finished frame.
  ///
  /// Below 1, the anti-aliasing ramp and the minimum line width grow to
  /// 1/[presentScale] target pixels, so the frame holds no detail finer
  /// than the resample keeps and thin lines stop shimmering as they move.
  /// At 1 or above, lines draw as they would with no resample.
  Future<void> setPresentScale(double presentScale) async {
    final rampScale = math.max(1.0, 1 / presentScale);
    if (rampScale == _rampScale) return;
    _rampScale = rampScale;
    for (final batch in _batches) {
      await batch._setAll(ScreenLineParams.rampScale, rampScale);
    }
  }

  /// Sets target pixels per logical pixel for every batch.
  Future<void> setPixelScale(double pixelScale) async {
    if (pixelScale == _pixelScale) return;
    _pixelScale = pixelScale;
    for (final batch in _batches) {
      await batch._setAll(ScreenLineParams.pixelScale, pixelScale);
    }
  }

  /// Uploads [segments] and adds them to the scene drawn in [style].
  ///
  /// With a [consumerStyle] from [loadStyle], every pass runs that style's
  /// `styleLine` on each fragment; without one, the built-in style.
  Future<LineBatch> createBatch(
    LineSegments segments,
    LineStyle style, {
    ConsumerStyle? consumerStyle,
  }) => createPackedBatch(
    packLineSegments(segments, widthPixels: style.widthPixels),
    style,
    consumerStyle: consumerStyle,
  );

  /// Uploads segments [packLineSegments] already packed, which lets a
  /// caller pack a large batch on another isolate, and adds them to the
  /// scene drawn in [style], and in [consumerStyle] when one is given.
  ///
  /// Throws an [ArgumentError] when [consumerStyle] is not one this
  /// renderer's [loadStyle] returned.
  Future<LineBatch> createPackedBatch(
    PackedLines packed,
    LineStyle style, {
    ConsumerStyle? consumerStyle,
  }) async {
    if (consumerStyle != null && !_styles.contains(consumerStyle)) {
      throw ArgumentError.value(
        consumerStyle.name,
        'consumerStyle',
        'was not loaded by this renderer',
      );
    }
    final body = consumerStyle?._body ?? _body;
    final edge = consumerStyle?._edge ?? _edge;
    final passes = <_Pass>[];

    // The first pass uploads the buffers. Every later pass is a Thermion
    // instance of it: its own renderable and material over the same
    // vertex and index buffers. Filament still picks each renderable's
    // pass from its material's blending.
    Future<void> addPass(Material<dynamic> material, _PassKind kind) async {
      final instance = await material.createInstance();
      await _configure(instance, kind, style, packed.hasVertexColors);
      final ThermionAsset<dynamic> asset;
      if (passes.isEmpty) {
        asset = await _viewer.createGeometry(
          Geometry(
            packed.positions,
            packed.indices,
            uvs: packed.uvs,
            uvs1: packed.uvs1,
            colors: packed.colors,
            attribute0: packed.attribute0,
          ),
          materialInstances: [instance],
        );
      } else {
        asset = await passes.first.asset.createInstance(
          materialInstances: [instance],
        );
        await _viewer.addToScene(asset);
      }
      await _viewer.setPriority(asset.entity, style.priority);
      passes.add(_Pass(kind, instance, asset));
    }

    if (style.depthMode != LineDepthMode.onTop) {
      await addPass(body, _PassKind.body);
    }
    await addPass(edge, _PassKind.edge);
    if (style.depthMode == LineDepthMode.hiddenStyled) {
      await addPass(edge, _PassKind.hidden);
    }

    final batch = LineBatch._(this, passes, style, packed, consumerStyle);
    _batches.add(batch);

    return batch;
  }

  Future<void> _configure(
    MaterialInstance<dynamic> instance,
    _PassKind kind,
    LineStyle style,
    bool hasVertexColors,
  ) async {
    final c = style.color;
    final dash = kind == _PassKind.hidden ? style.hiddenDash : style.dash;
    await instance.setParameterFloat4(
      ScreenLineParams.lineColor,
      c.r,
      c.g,
      c.b,
      c.a,
    );
    await instance.setParameterFloat(
      ScreenLineParams.opacity,
      _passOpacity(kind, style, style.opacity),
    );
    await instance.setParameterFloat(
      ScreenLineParams.vertexColorMix,
      hasVertexColors ? 1 : 0,
    );
    await instance.setParameterFloat(ScreenLineParams.pixelScale, _pixelScale);
    await instance.setParameterFloat(ScreenLineParams.rampScale, _rampScale);
    await instance.setParameterFloat(
      ScreenLineParams.widthReferenceDepth,
      _widthReferenceDepth,
    );
    await instance.setParameterInt(ScreenLineParams.capStyle, style.cap.index);
    await instance.setParameterFloat(ScreenLineParams.depthBias, depthBias);
    await instance.setParameterFloat(
      ScreenLineParams.depthSlopeBias,
      depthSlopeBias,
    );
    await instance.setParameterFloat2(
      ScreenLineParams.dash,
      dash?.onPixels ?? 0,
      dash?.offPixels ?? 0,
    );
    await instance.setParameterFloat(
      ScreenLineParams.progressCursor,
      _progressOff,
    );
    await instance.setParameterFloat(
      ScreenLineParams.progressWindowEnd,
      _progressOff,
    );
    await instance.setParameterFloat(
      ScreenLineParams.progressDim,
      style.progressDim,
    );
    await instance.setParameterFloat(
      ScreenLineParams.progressBoost,
      style.progressBoost,
    );

    await LineBatch._writePulse(instance, null);

    final onTop = style.depthMode == LineDepthMode.onTop;
    await instance.setParameterBool(ScreenLineParams.edgeDrawsAll, onTop);
    if (onTop) {
      await instance.setDepthCullingEnabled(false);
    }
    if (kind == _PassKind.hidden) {
      // Filament's depth is reversed, so a fragment behind what the depth
      // buffer holds compares less.
      await instance.setDepthFunc(SamplerCompareFunction.L);
      await instance.setParameterBool(ScreenLineParams.edgeDrawsAll, true);
    }
  }

  static double _passOpacity(_PassKind kind, LineStyle style, double opacity) =>
      kind == _PassKind.hidden ? opacity * style.hiddenOpacity : opacity;

  /// Destroys every batch, both materials, and every consumer style's
  /// materials.
  Future<void> dispose() async {
    for (final batch in _batches.toList()) {
      await batch.destroy();
    }
    await _body.destroy();
    await _edge.destroy();
    for (final style in _styles) {
      await style._body.destroy();
      await style._edge.destroy();
    }
    _styles.clear();
  }
}

enum _PassKind { body, edge, hidden }

final class _Pass {
  _Pass(this.kind, this.instance, this.asset);

  final _PassKind kind;
  final MaterialInstance<dynamic> instance;
  final ThermionAsset<dynamic> asset;
}

/// One uploaded set of segments and the passes that draw it.
class LineBatch {
  LineBatch._(
    this._renderer,
    this._passes,
    this._style,
    PackedLines packed,
    this.consumerStyle,
  ) : vertexCount = packed.vertexCount,
      hasVertexColors = packed.hasVertexColors;

  /// The consumer style the batch draws in, or null for the built-in
  /// style.
  final ConsumerStyle? consumerStyle;

  /// Vertex buffer slot of the per-vertex colour. Thermion lays a
  /// geometry's buffers out as position, tangents (only with normals),
  /// UV0, UV1, colour, then CUSTOM0, and line geometry has no normals.
  static const _colorBufferIndex = 3;

  /// Vertices the batch uploaded, four per segment.
  final int vertexCount;

  /// Whether the batch draws its per-vertex colours.
  final bool hasVertexColors;

  final ScreenLineRenderer _renderer;
  final List<_Pass> _passes;
  final LineStyle _style;
  bool _visible = true;
  bool _destroyed = false;

  /// Assets of the batch's passes. The first uploaded the buffers; the
  /// others are instances drawing from them.
  List<ThermionAsset<dynamic>> get assets => [for (final p in _passes) p.asset];

  ThermionViewer get _viewer => _renderer._viewer;

  /// Writes [colors], four floats per vertex as [PackedLines.colors]
  /// holds them, into the uploaded vertex buffer, and returns whether it
  /// could. Every pass draws the new colours from the next frame.
  ///
  /// Returns false, writing nothing, when [colors] does not match the
  /// batch's vertex count or the buffer is not writable.
  Future<bool> writeColors(Float32List colors) async {
    if (!colorsWritable || colors.length != vertexCount * 4) return false;
    await _passes.first.asset.getVertexBuffer()!.setBufferAt(
      _colorBufferIndex,
      colors,
    );

    return true;
  }

  /// Whether [writeColors] can write into the uploaded vertex buffer.
  bool get colorsWritable {
    if (_destroyed) return false;
    final buffer = _passes.first.asset.getVertexBuffer();

    return buffer != null && buffer.supportsSetBufferAt;
  }

  /// Sets the colour where segments carry none.
  Future<void> setColor(LinearRgba color) async {
    if (_destroyed) return;
    for (final p in _passes) {
      await p.instance.setParameterFloat4(
        ScreenLineParams.lineColor,
        color.r,
        color.g,
        color.b,
        color.a,
      );
    }
  }

  /// Sets the opacity of every fragment.
  Future<void> setOpacity(double opacity) async {
    if (_destroyed) return;
    for (final p in _passes) {
      await p.instance.setParameterFloat(
        ScreenLineParams.opacity,
        ScreenLineRenderer._passOpacity(p.kind, _style, opacity),
      );
    }
  }

  /// Adds the batch to the scene or removes it.
  Future<void> setVisible(bool visible) async {
    if (_destroyed || visible == _visible) return;
    _visible = visible;
    for (final p in _passes) {
      if (visible) {
        await _viewer.addToScene(p.asset);
      } else {
        await _viewer.removeFromScene(p.asset);
      }
    }
  }

  /// Sets the Filament render priority, 0 (first) to 7 (last).
  Future<void> setPriority(int priority) async {
    if (_destroyed) return;
    for (final p in _passes) {
      await _viewer.setPriority(p.asset.entity, priority);
    }
  }

  /// Dims what lies behind [cursor] and brightens what lies between it and
  /// [windowEnd]. A negative [cursor] turns both off.
  Future<void> setProgress(
    double cursor, {
    double windowEnd = _progressOff,
  }) async {
    await _setAll(ScreenLineParams.progressCursor, cursor);
    await _setAll(ScreenLineParams.progressWindowEnd, windowEnd);
  }

  /// Draws [pulse] along the batch's progress, or no pulse when null.
  ///
  /// Call it every frame with a moving [LinePulse.center] to animate the
  /// band along the lines.
  Future<void> setPulse(LinePulse? pulse) async {
    if (_destroyed) return;
    for (final p in _passes) {
      await _writePulse(p.instance, pulse);
    }
  }

  static Future<void> _writePulse(
    MaterialInstance<dynamic> instance,
    LinePulse? pulse,
  ) async {
    final c = pulse?.color ?? const LinearRgba(1, 1, 1);
    await instance.setParameterFloat(
      ScreenLineParams.pulseCenter,
      pulse?.center ?? 0,
    );
    await instance.setParameterFloat(
      ScreenLineParams.pulseHalfLength,
      pulse?.halfLength ?? 0,
    );
    await instance.setParameterFloat4(
      ScreenLineParams.pulseColor,
      c.r,
      c.g,
      c.b,
      pulse?.colorMix ?? 0,
    );
    await instance.setParameterFloat(
      ScreenLineParams.pulseOpacity,
      pulse?.opacity ?? 1,
    );
    await instance.setParameterFloat(
      ScreenLineParams.pulseWidthScale,
      pulse?.widthScale ?? 1,
    );
    await instance.setParameterFloat(
      ScreenLineParams.pulseGlowPixels,
      pulse?.glowPixels ?? 0,
    );
    await instance.setParameterFloat2(
      ScreenLineParams.pulseFade,
      pulse?.fadeBehind ?? 1,
      pulse?.fadeAhead ?? 1,
    );
  }

  /// Sets the consumer style's own parameter [name] on every pass, as a
  /// `float` to a `float4` by the length of [value].
  ///
  /// The style's parameters start at zero. Throws an [ArgumentError] when
  /// [name] is a parameter the package sets itself or [value] holds no
  /// floats or more than four, and a [StateError] when the batch draws in
  /// the built-in style.
  Future<void> setStyleParameter(String name, List<double> value) async {
    checkStyleParameter(name, value);
    if (consumerStyle == null) {
      throw StateError(
        'the batch draws in the built-in style, which has no parameter '
        '"$name"; create it with a consumerStyle',
      );
    }
    if (_destroyed) return;
    for (final p in _passes) {
      final i = p.instance;
      switch (value) {
        case [final x]:
          await i.setParameterFloat(name, x);
        case [final x, final y]:
          await i.setParameterFloat2(name, x, y);
        case [final x, final y, final z]:
          await i.setParameterFloat3(name, x, y, z);
        case [final x, final y, final z, final w]:
          await i.setParameterFloat4(name, x, y, z, w);
        case _:
          // checkStyleParameter admits one to four floats only.
          throw StateError('unreachable: ${value.length} floats');
      }
    }
  }

  /// Sets the model transform applied to every segment.
  Future<void> setTransform(Matrix4 transform) async {
    if (_destroyed) return;
    for (final p in _passes) {
      await p.asset.setTransform(transform);
    }
  }

  Future<void> _setAll(String name, double value) async {
    if (_destroyed) return;
    for (final p in _passes) {
      await p.instance.setParameterFloat(name, value);
    }
  }

  /// Removes the batch from the scene and frees its assets and material
  /// instances. Every other call on the batch does nothing afterwards, so a
  /// late per-frame update cannot reach a destroyed material instance.
  Future<void> destroy() async {
    if (_destroyed) return;
    _destroyed = true;
    _renderer._batches.remove(this);
    // Destroying the uploaded asset destroys its instances with it.
    try {
      for (final p in _passes.skip(1)) {
        await _viewer.removeFromScene(p.asset);
      }
      await _viewer.destroyAsset(_passes.first.asset);
      for (final p in _passes) {
        await p.instance.destroy();
      }
    } on Exception catch (e, stackTrace) {
      _log.warning('line batch destroy failed', e, stackTrace);
    }
  }
}
