# tech_lines

`tech_lines` draws lines of constant width in screen pixels into a
Thermion scene. A segment is two endpoints in the caller's world
coordinates. Wherever the camera puts it, the segment draws at the width
asked for, with anti-aliased edges, and it hides behind meshes in front
of it.

The package knows nothing of what the lines mean. It takes segments,
colours in linear RGBA and a style, and leaves categories, themes and
colour spaces to the caller.

## Coverage

Each fragment's colour is weighted by coverage: the fraction of its pixel
that the line covers. Coverage is the overlap of the pixel's footprint
across the line with the line itself, so a line sums to its width at any
angle and any sub-pixel position. A line thinner than one pixel draws one
pixel wide at a fraction of its colour, so it fades rather than breaking
into a staircase as it moves.

Every batch draws in two passes over the same segments. The body pass
keeps only fully covered fragments of an opaque line, draws them opaque
and writes depth, so lines and meshes occlude each other with no
sorting. The edge pass blends every other fragment: the anti-aliased rim
of an opaque line, and the whole of a translucent or sub-pixel one.

## Draw lines

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

## Styles

`LineStyle` sets a batch's width in logical pixels, colour, opacity, cap
(`round` by default, `butt` or `square`), dash and Filament render
priority. `LineSegments` can override colour and width per segment.

`depthMode` picks how a batch meets the depth buffer:

- `tested` hides the line behind meshes in front of it.
- `onTop` draws the line over everything, in the transparent pass, so
  render priority alone orders it against other on-top lines.
- `hiddenStyled` draws the hidden part too, at `hiddenOpacity` with
  `hiddenDash`.

A line drawn on a face would z-fight with it, so each line moves towards
the camera by a small bias. The bias has a part relative to distance and
a part that grows with the line's width in pixels, set by
`depthSlopeBias` on the renderer. A larger slope factor keeps lines
visible on steeper faces, and lets them show through occluders that
close in depth.

`setProgress` on a batch dims every segment behind a cursor and
brightens those between the cursor and a window end, from the per-segment
`progress` values.

## Materials

The `.mat` sources live in `materials/` and compile into
`assets/materials/` with the `matc` from the Filament release in
`tools/filament_version`, which must match the Filament the pinned
`thermion_dart` links. The script downloads that `matc` on first use:

```sh
./tools/compile_materials.sh
```

`tools/check_materials.sh` fails when a committed blob no longer matches
its source. `ScreenLineRenderer.create` throws `FilamatVersionException` on a
blob compiled for a different Filament release, before Filament would
abort on it.

## Tests

The unit tests run with `dart test`. The pixel tests render headless
through Filament, capture the render target and measure width, coverage
and depth against the pass criteria. They need a GPU driver, so the
`gpu` tag skips them by default. To run them, enter the package directory
and run:

```sh
dart test --run-skipped -t gpu
```

## Example

`example/` is a Flutter app that draws line patterns chosen to expose
line-rendering defects, with controls for the present scale and
perspective widths. See its README.
