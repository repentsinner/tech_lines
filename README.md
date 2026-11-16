# tech_lines

`tech_lines` draws lines of constant width in screen pixels into a
Thermion scene. A segment is two endpoints in the caller's world
coordinates. Wherever the camera puts it, the segment draws at the width
asked for, with anti-aliased edges, and it hides behind meshes in front
of it.

The package knows nothing of what the lines mean. It takes segments,
colours in linear RGBA and a style, and leaves categories, themes and
colour spaces to the caller.

Each fragment's colour is weighted by coverage, the fraction of its
pixel that the line covers, so a line sums to its width at any angle and
any sub-pixel position. A line thinner than one pixel draws one pixel
wide at a fraction of its colour, so it fades rather than breaking into
a staircase as it moves. Every batch draws in two passes over the same
segments: an opaque body pass that writes depth, so lines and meshes
occlude each other with no sorting, and an edge pass that blends the
anti-aliased rim.

## Installation

The package isn't on pub.dev. Depend on it by commit:

```yaml
dependencies:
  tech_lines:
    git:
      url: https://github.com/repentsinner/tech_lines.git
      ref: <commit>
```

The compiled materials match the Filament release of the
`thermion_dart` this repository pins in its `dependency_overrides`. An
application overrides `thermion_dart` to the same commit.
`ScreenLineRenderer.create` throws `FilamatVersionException` when the
two disagree.

## Usage

1. Load the materials and create a renderer for a viewer. In a Flutter
   app, load the assets through `rootBundle`:

   ```dart
   final lines = await ScreenLineRenderer.create(
     viewer: viewer,
     loadAsset: (key) async =>
         (await rootBundle.load(key)).buffer.asUint8List(),
     pixelScale: MediaQuery.devicePixelRatioOf(context),
   );
   ```

2. Pack segments as six floats each and create a batch:

   ```dart
   final batch = await lines.createBatch(
     LineSegments(
       endpoints: Float32List.fromList([0, 0, 0, 1, 0, 0]),
     ),
     const LineStyle(widthPixels: 1.5, color: LinearRgba(1, 0.5, 0)),
   );
   ```

3. When the device pixel ratio changes, call `lines.setPixelScale`.

4. Destroy the batch when the lines go, and dispose of the renderer with
   the viewer.

`LineStyle` sets a batch's width in logical pixels, colour, opacity, cap
(`round` by default, `butt` or `square`), dash and Filament render
priority. `LineSegments` can override colour, width and progress per
segment.

`depthMode` picks how a batch meets the depth buffer:

- `tested` hides the line behind meshes in front of it.
- `onTop` draws the line over everything, in the transparent pass, so
  render priority alone orders it against other on-top lines.
- `hiddenStyled` draws the hidden part too, at `hiddenOpacity` with
  `hiddenDash`.

A line drawn on a face would z-fight with it, so each line moves towards
the camera by a small bias. `depthSlopeBias` on the renderer sets how
far the bias grows with the line's width in pixels. A larger factor
keeps lines visible on steeper faces, and lets them show through
occluders that close in depth.

On a batch, `setProgress` dims every segment behind a cursor and
brightens those between the cursor and a window end, from the
per-segment `progress` values. `setPulse` sends a band along the same
progress that tints, fades, widens or makes the line glow.

On the renderer, `setPresentScale` widens the anti-aliasing ramp when
the platform resamples the finished frame, and `setPerspectiveWidth`
draws widths that shrink with depth for comparison.

### Consumer styles

A consumer style changes a line's colour and opacity per fragment from
data the application owns, such as a fade toward the edge of a ground
patch. The package keeps the geometry, coverage, passes and depth, and
runs the style inside them, so a faded fragment still draws exactly
once. A style changes colour and opacity only. An effect that changes a
line's width or shape, as the pulse does, belongs in the package.

1. Write the style in GLSL. It defines one function, which may change
   the fragment's colour, its alpha before coverage, and a scale on the
   pulse glow:

   ```glsl
   void styleLine(inout ScreenLineStyle style, ScreenLineFragment fragment) {
       float reach = distance(fragment.worldPosition.xy,
           materialParams.fadeCenter.xy) / materialParams.fadeRadius;
       float fade = 1.0 - smoothstep(0.0, 1.0, reach);
       style.alpha *= fade;
       style.glowScale *= fade;
   }
   ```

   `fragment.worldPosition` is in the caller's world coordinates. It
   includes the depth bias, which moves it toward the camera, so a fade
   over a plane measures within the plane. `fragment.progress` and
   `fragment.band` carry the progress and the pulse band at the
   fragment.

2. List the style's own parameters in a file, as `matc` parameter
   entries. Their names can't reuse the package's own, which
   `ScreenLineParams.all` lists:

   ```text
   { type : float3, name : fadeCenter, precision : high },
   { type : float, name : fadeRadius, precision : high }
   ```

3. Build the style with this package's `tools/compile_style.sh`, which
   writes a body and an edge material. In an application, the
   package's directory is the `rootUri` of `tech_lines` in
   `.dart_tool/package_config.json`:

   ```sh
   tools/compile_style.sh --params radial_fade.params \
       radial_fade radial_fade.fs assets/styles
   ```

   Rebuild every style whenever the application moves to another
   release of `tech_lines`. `loadStyle` throws `StyleTemplateException`
   for a style built from another release's materials.

4. Load the style once, draw batches in it, and set its parameters on
   each batch. A style's parameters start at zero:

   ```dart
   final fade = await lines.loadStyle(
     bodyAsset: 'assets/styles/radial_fade_body.filamat',
     edgeAsset: 'assets/styles/radial_fade_edge.filamat',
   );
   final batch = await lines.createBatch(segments, style, consumerStyle: fade);
   await batch.setStyleParameter('fadeCenter', [0, 0, 0]);
   await batch.setStyleParameter('fadeRadius', [60]);
   ```

The renderer owns the styles it loads and destroys them in `dispose`.

## Development

The `.mat` sources live in `materials/` and compile into
`assets/materials/` with the `matc` from the Filament release in
`tools/filament_version`. The same script builds the example's consumer
styles from `example/styles/` into `example/assets/styles/`. It
downloads that `matc` on first use:

```sh
./tools/compile_materials.sh
```

`tools/check_materials.sh` fails when a committed blob no longer matches
its source.

The unit tests run with `dart test`. The tests of `tools/compile_style.sh`
need `matc`, so the `matc` tag skips them by default. The pixel tests
render headless through Filament, capture the render target and measure
width, coverage, depth and consumer styles. They need a GPU driver, so the
`gpu` tag skips them by default:

```sh
dart test --run-skipped -t matc
dart test --run-skipped -t gpu
```

`example/` is a Flutter app that draws line patterns chosen to expose
line-rendering defects, with controls for the present scale,
perspective widths and the pulse. One pattern draws a ground grid in a
consumer style. See its README.

SPEC.md specifies the rendering (§spec:screen-space-lines), and
ROADMAP.md lists the work ahead.

## License

BSD 3-Clause. See LICENSE.
