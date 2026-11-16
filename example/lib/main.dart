import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:thermion_flutter/thermion_flutter.dart' hide KeyEvent;
import 'package:tech_lines/tech_lines.dart';

import 'patterns.dart';

/// Starts on the pattern whose name `--pattern=<name>` gives, matched
/// case-insensitively by prefix, or on the first.
void main(List<String> args) {
  final arg = args
      .where((a) => a.startsWith('--pattern='))
      .map((a) => a.substring('--pattern='.length).toLowerCase())
      .firstOrNull;
  final index = arg == null
      ? 0
      : patterns.indexWhere((p) => p.name.toLowerCase().startsWith(arg));
  // `--pulse=color,glow` starts with those pulse effects on.
  final pulse = args
      .where((a) => a.startsWith('--pulse='))
      .expand((a) => a.substring('--pulse='.length).split(','))
      .map((name) => PulseEffect.values.where((e) => e.name == name))
      .expand((e) => e)
      .toSet();
  runApp(
    LinePatternsApp(initialPattern: index < 0 ? 0 : index, initialPulse: pulse),
  );
}

/// What a pulse changes as it travels along a path.
enum PulseEffect { color, opacity, width, glow }

class LinePatternsApp extends StatelessWidget {
  const LinePatternsApp({
    super.key,
    this.initialPattern = 0,
    this.initialPulse = const {},
  });

  final int initialPattern;
  final Set<PulseEffect> initialPulse;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Line patterns',
    theme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark),
    home: LinePatternsPage(
      initialPattern: initialPattern,
      initialPulse: initialPulse,
    ),
  );
}

class LinePatternsPage extends StatefulWidget {
  const LinePatternsPage({
    super.key,
    this.initialPattern = 0,
    this.initialPulse = const {},
  });

  final int initialPattern;
  final Set<PulseEffect> initialPulse;

  @override
  State<LinePatternsPage> createState() => _LinePatternsPageState();
}

class _LinePatternsPageState extends State<LinePatternsPage>
    with SingleTickerProviderStateMixin {
  ThermionViewer? _viewer;
  ScreenLineRenderer? _lines;
  final List<LineBatch> _batches = [];

  // Consumer styles by name, loaded once with the renderer, which owns them.
  final Map<String, ConsumerStyle> _styles = {};

  // Batches that carry a path, with its length in world units.
  final List<(LineBatch, double)> _paths = [];

  // The pulse travelling along every path.
  late final Set<PulseEffect> _effects = {...widget.initialPulse};
  double _pulseSpeed = 40;
  double _pulseLength = 12;
  bool _progressByCount = false;
  Duration _elapsed = Duration.zero;
  final List<ThermionAsset<dynamic>> _boxes = [];
  String? _error;

  late int _pattern = widget.initialPattern;
  bool _drift = false;

  // Whether the new renderer foreshortens widths from the orbit target.
  bool _perspectiveWidth = false;

  // Orbit camera around the origin.
  double _yaw = 0;
  double _pitch = 0.25;
  double _distance = 180;
  double _driftOffset = 0;
  late final Ticker _ticker = createTicker(_tick);

  Size _viewport = Size.zero;
  double _dpr = 1;

  // Render-target pixels per Flutter pixel. At 2, the 3D view renders at
  // twice the frame's resolution and Flutter's bilinear 2:1 sample
  // averages each 2×2 block on the way into the frame.
  int _supersample = 1;

  // Panel pixels per render-target pixel the new renderer tunes its ramp
  // and minimum width for.
  double _presentScale = 1;

  // Serializes scene rebuilds so a fast key repeat cannot interleave them.
  Future<void> _rebuilding = Future.value();

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      // Thermion's Linux OpenGL path presents the frame mirrored; the app
      // pins Vulkan there for the same reason.
      if (Platform.isLinux) {
        ThermionFlutterPlugin.instance.setOptions(
          const ThermionFlutterOptions(
            nativeOptions: NativeOptions(backend: Backend.VULKAN),
          ),
        );
      }
      final viewer = await ThermionFlutterPlugin.createViewer();
      await viewer.setRendering(true);
      await viewer.setPostProcessing(false);
      await viewer.setBackgroundColor(0.08, 0.08, 0.09, 1);
      final lines = await ScreenLineRenderer.create(
        viewer: viewer,
        loadAsset: (key) async {
          final data = await rootBundle.load(key);

          return data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        },
      );
      for (final name in consumerStyles) {
        _styles[name] = await lines.loadStyle(
          bodyAsset: 'assets/styles/${name}_body.filamat',
          edgeAsset: 'assets/styles/${name}_edge.filamat',
        );
      }
      setState(() {
        _viewer = viewer;
        _lines = lines;
      });
      await _updateCamera();
      _rebuild();
      _updateTicker();
    } on Exception catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    unawaited(_lines?.dispose());
    unawaited(_viewer?.dispose());
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _elapsed).inMicroseconds / 1e6;
    _elapsed = elapsed;
    if (_drift) {
      // A slow sweep of about one pixel's worth of world space at the
      // default distance, so lines cross pixel boundaries visibly slowly.
      _driftOffset = 0.6 * math.sin(elapsed.inMilliseconds / 4000);
      unawaited(_updateCamera());
    }
    if (_effects.isNotEmpty) {
      _pulseDistance += _pulseSpeed * dt;
      unawaited(_updatePulses());
    }
  }

  // Distance in world units the pulse has travelled since it started.
  double _pulseDistance = 0;

  /// Moves the pulse along every path at [_pulseSpeed] world units per
  /// second, wrapping past the path's end with room for the band to
  /// leave it.
  Future<void> _updatePulses() async {
    for (final (batch, length) in _paths) {
      if (_effects.isEmpty) {
        await batch.setPulse(null);
        continue;
      }
      final cycle = length + 2 * _pulseLength;
      final along = _pulseDistance % cycle - _pulseLength;
      await batch.setPulse(
        LinePulse(
          center: along / length,
          halfLength: _pulseLength / length,
          color: const LinearRgba(1, 0.85, 0.2),
          colorMix: _effects.contains(PulseEffect.color) ? 1 : 0,
          opacity: _effects.contains(PulseEffect.opacity) ? 0.15 : 1,
          widthScale: _effects.contains(PulseEffect.width) ? 3 : 1,
          glowPixels: _effects.contains(PulseEffect.glow) ? 5 : 0,
        ),
      );
    }
  }

  void _updateTicker() {
    final run = _drift || _effects.isNotEmpty;
    if (run && !_ticker.isActive) {
      _elapsed = Duration.zero;
      unawaited(_ticker.start());
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  Future<void> _updateCamera() async {
    final viewer = _viewer;
    if (viewer == null) return;
    final camera = await viewer.getActiveCamera();
    final target = Vector3(_driftOffset, _driftOffset * 0.37, 0);
    final eye =
        target +
        Vector3(
          _distance * math.cos(_pitch) * math.sin(_yaw),
          _distance * math.sin(_pitch),
          _distance * math.cos(_pitch) * math.cos(_yaw),
        );
    await camera.lookAt(eye, focus: target, up: Vector3(0, 1, 0));
    // Lines at the orbit target keep their pixel width, so the two width
    // modes agree there and differ only nearer and farther.
    await _lines?.setPerspectiveWidth(_perspectiveWidth ? _distance : null);
  }

  Future<void> _updateViewport(Size size, double dpr) async {
    if (size == _viewport && dpr == _dpr) return;
    _viewport = size;
    _dpr = dpr;
    final camera = await _viewer?.getActiveCamera();
    await camera?.setLensProjection(
      far: 10000,
      aspect: size.width / math.max(size.height, 1),
    );
    await _applyScale();
  }

  /// Pushes the render-target scale and present scale to the renderer.
  Future<void> _applyScale() async {
    final targetScale = _dpr * _supersample;
    await _lines?.setPixelScale(targetScale);
    // Supersampling adds a 2:1 downsample before the platform's own, so
    // the scale the shader tunes for multiplies by it.
    await _lines?.setPresentScale(_presentScale / _supersample);
  }

  void _rebuild() {
    // A failed rebuild reports and lets the next one run, rather than
    // leaving the chain errored and every later rebuild skipped.
    _rebuilding = _rebuilding.then((_) => _rebuildNow()).catchError((
      Object e,
      StackTrace stackTrace,
    ) {
      debugPrint('pattern rebuild failed: $e\n$stackTrace');
    });
  }

  Future<void> _rebuildNow() async {
    final viewer = _viewer;
    final lines = _lines;
    if (viewer == null || lines == null) return;

    for (final batch in _batches) {
      await batch.destroy();
    }
    _batches.clear();
    _paths.clear();
    for (final box in _boxes) {
      await viewer.destroyAsset(box);
    }
    _boxes.clear();

    final pattern = patterns[_pattern];
    for (final box in pattern.boxes) {
      final material = await FilamentApp.instance!
          .createUbershaderMaterialInstance(unlit: true);
      final g = box.shade;
      await material.setParameterFloat4('baseColorFactor', g, g, g * 1.1, 1);
      // Thermion's cube and sphere span -1 to 1; its cylinder has radius
      // 1 and length 1 along y.
      final (geometry, scale) = switch (box.shape) {
        SolidShape.box => (GeometryUtils.cube(), box.size / 2),
        SolidShape.sphere => (GeometryUtils.sphere(), box.size / 2),
        // Thermion's cylinder emits more UVs than vertices, which its
        // Geometry rejects; an unlit solid needs none.
        SolidShape.cylinder => (
          GeometryUtils.cylinder(uvs: false),
          Vector3(box.size.x / 2, box.size.y, box.size.z / 2),
        ),
      };
      final asset = await viewer.createGeometry(
        geometry,
        materialInstances: [material],
      );
      await asset.setTransform(
        Matrix4.compose(box.center, box.rotation, scale),
      );
      _boxes.add(asset);
    }

    for (final batch in pattern.build(
      BuildOptions(progressByCount: _progressByCount),
    )) {
      final styleName = batch.consumerStyle;
      final drawn = await lines.createBatch(
        batch.segments,
        batch.style,
        consumerStyle: styleName == null ? null : _styles[styleName]!,
      );
      for (final MapEntry(:key, :value) in batch.styleParameters.entries) {
        await drawn.setStyleParameter(key, value);
      }
      _batches.add(drawn);
      final length = batch.pathLength;
      if (length != null) _paths.add((drawn, length));
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      setState(() => _pattern = (_pattern + 1) % patterns.length);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      setState(
        () => _pattern = (_pattern - 1 + patterns.length) % patterns.length,
      );
    } else if (key == LogicalKeyboardKey.keyP) {
      setState(() => _perspectiveWidth = !_perspectiveWidth);
      unawaited(_updateCamera());

      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyD) {
      _toggleDrift(!_drift);

      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    _rebuild();

    return KeyEventResult.handled;
  }

  void _toggleDrift(bool on) {
    setState(() => _drift = on);
    _updateTicker();
    if (!on) {
      _driftOffset = 0;
      unawaited(_updateCamera());
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewer = _viewer;
    final pattern = patterns[_pattern];

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        unawaited(
                          _updateViewport(
                            constraints.biggest,
                            MediaQuery.devicePixelRatioOf(context),
                          ),
                        );
                        if (_error != null) {
                          return Center(child: Text(_error!));
                        }
                        if (viewer == null) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        return Listener(
                          onPointerSignal: (signal) {
                            if (signal is PointerScrollEvent) {
                              _distance =
                                  (_distance *
                                          math.pow(
                                            1.001,
                                            signal.scrollDelta.dy,
                                          ))
                                      .clamp(5.0, 3000.0);
                              unawaited(_updateCamera());
                            }
                          },
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              _yaw -= details.delta.dx * 0.005;
                              _pitch = (_pitch + details.delta.dy * 0.005)
                                  .clamp(-1.5, 1.5);
                              unawaited(_updateCamera());
                            },
                            child: MediaQuery(
                              // Thermion sizes its texture from this ratio.
                              data: MediaQuery.of(
                                context,
                              ).copyWith(devicePixelRatio: _dpr * _supersample),
                              child: ThermionWidget(viewer: viewer),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  _StatusBar(pattern: pattern, dpr: _dpr),
                ],
              ),
            ),
            SizedBox(
              width: 300,
              child: _ControlPanel(
                pattern: _pattern,
                drift: _drift,
                onPattern: (i) {
                  setState(() => _pattern = i);
                  _rebuild();
                },
                onDrift: _toggleDrift,
                effects: _effects,
                onEffect: (effect, on) {
                  setState(
                    () => on ? _effects.add(effect) : _effects.remove(effect),
                  );
                  _updateTicker();
                  unawaited(_updatePulses());
                },
                pulseSpeed: _pulseSpeed,
                onPulseSpeed: (v) => setState(() => _pulseSpeed = v),
                pulseLength: _pulseLength,
                onPulseLength: (v) => setState(() => _pulseLength = v),
                progressByCount: _progressByCount,
                onProgressByCount: (v) {
                  setState(() => _progressByCount = v);
                  _rebuild();
                },
                perspectiveWidth: _perspectiveWidth,
                onPerspectiveWidth: (v) {
                  setState(() => _perspectiveWidth = v);
                  unawaited(_updateCamera());
                },
                supersample: _supersample,
                onSupersample: (k) {
                  setState(() => _supersample = k);
                  unawaited(_applyScale());
                },
                presentScale: _presentScale,
                onPresentScale: (s) {
                  setState(() => _presentScale = s);
                  unawaited(_applyScale());
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.pattern, required this.dpr});

  final LinePattern pattern;
  final double dpr;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                pattern.description,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              'device pixel ratio ${dpr.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.pattern,
    required this.drift,
    required this.onPattern,
    required this.onDrift,
    required this.effects,
    required this.onEffect,
    required this.pulseSpeed,
    required this.onPulseSpeed,
    required this.pulseLength,
    required this.onPulseLength,
    required this.progressByCount,
    required this.onProgressByCount,
    required this.perspectiveWidth,
    required this.onPerspectiveWidth,
    required this.supersample,
    required this.onSupersample,
    required this.presentScale,
    required this.onPresentScale,
  });

  final int pattern;
  final bool drift;
  final ValueChanged<int> onPattern;
  final ValueChanged<bool> onDrift;
  final Set<PulseEffect> effects;
  final void Function(PulseEffect effect, bool on) onEffect;
  final double pulseSpeed;
  final ValueChanged<double> onPulseSpeed;
  final double pulseLength;
  final ValueChanged<double> onPulseLength;
  final bool progressByCount;
  final ValueChanged<bool> onProgressByCount;
  final bool perspectiveWidth;
  final ValueChanged<bool> onPerspectiveWidth;
  final int supersample;
  final ValueChanged<int> onSupersample;
  final double presentScale;
  final ValueChanged<double> onPresentScale;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sub-pixel drift'),
          subtitle: const Text('Pans slowly to show shimmer'),
          value: drift,
          onChanged: onDrift,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Perspective width'),
          subtitle: const Text(
            'Lines foreshorten with depth, at their '
            'pixel width at the orbit target',
          ),
          value: perspectiveWidth,
          onChanged: onPerspectiveWidth,
        ),
        const Divider(),
        Text('Supersample', style: text.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('1×')),
            ButtonSegment(value: 2, label: Text('2×')),
          ],
          selected: {supersample},
          onSelectionChanged: (s) => onSupersample(s.single),
        ),
        const SizedBox(height: 16),
        Text(
          'Present scale ${presentScale.toStringAsFixed(3)}',
          style: text.titleSmall,
        ),
        Slider(
          min: 0.5,
          max: 1,
          divisions: 20,
          value: presentScale,
          onChanged: onPresentScale,
        ),
        Text(
          'Panel pixels per frame pixel after the platform resamples. '
          'Output scale over Flutter\'s pixel ratio: 1.25 / 2 = 0.625 on '
          'a 1.25 Linux display. Widens the ramp to 1/s.',
          style: text.bodySmall,
        ),
        const Divider(),
        Text('Pulse', style: text.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final effect in PulseEffect.values)
              FilterChip(
                label: Text(effect.name),
                selected: effects.contains(effect),
                onSelected: (on) => onEffect(effect, on),
              ),
          ],
        ),
        Text(
          'Speed ${pulseSpeed.toStringAsFixed(0)} units/s',
          style: text.bodySmall,
        ),
        Slider(min: 5, max: 200, value: pulseSpeed, onChanged: onPulseSpeed),
        Text(
          'Band ${pulseLength.toStringAsFixed(0)} units',
          style: text.bodySmall,
        ),
        Slider(min: 2, max: 60, value: pulseLength, onChanged: onPulseLength),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Progress by segment count'),
          subtitle: const Text(
            'Gives each segment equal progress, to compare against '
            'progress by distance',
          ),
          value: progressByCount,
          onChanged: onProgressByCount,
        ),
        const Divider(),
        Text('Pattern', style: text.titleSmall),
        for (var i = 0; i < patterns.length; i++)
          ListTile(
            dense: true,
            selected: i == pattern,
            title: Text(patterns[i].name),
            onTap: () => onPattern(i),
          ),
        const Divider(),
        Text(
          '← and → change pattern, D toggles '
          'drift, P toggles perspective width. Drag to orbit, scroll to '
          'zoom.',
          style: text.bodySmall,
        ),
      ],
    );
  }
}
