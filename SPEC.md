# tech_lines — Specification

## Screen-space lines §spec:screen-space-lines

*Status: in progress*

A screen-space line is a world-space segment drawn at a constant width
in screen pixels. `ScreenLineRenderer` draws batches of them into a
Thermion scene. A batch is one upload of segments with one `LineStyle`.
The same line shall look the same on every platform and display scale,
and its drawn width shall be the width the caller asks for
(§req:success-criteria).

The API takes segments in the caller's world coordinates and colours as
linear RGBA, and carries no application vocabulary. The package depends
on `thermion_dart` alone and takes its material bytes through a loader
the caller supplies: `rootBundle` in a Flutter app, the package's own
files in its tests.

*Why*: a renderer with no application vocabulary serves any technical
view, and can render `tech_vis`'s reference screen geometry and record
its error, which makes it a reference implementation of `tech_vis`'s
line rule. Without a Flutter dependency the package renders headless
under `dart test` (§req:constraints).

## Width and coverage §spec:width-and-coverage

*Status: in progress*

- A line's width in logical pixels, times the pixel scale, shall equal
  its drawn width in render-target pixels. The vertex shader reads the
  target size from Filament's own resolution (`getResolution()`) and
  places each quad corner in target pixels.
- Each fragment's coverage shall be the overlap of its pixel's footprint
  across the line with the line, from the fragment's exact distance to
  the segment in pixel space: a capsule for round caps, a box for butt
  and square caps. The footprint is one pixel for an axis-aligned line
  and up to the pixel's diagonal at 45°. The whole anti-aliasing ramp
  shall reach the screen.
- A line thinner than one target pixel shall draw one pixel wide with
  its coverage scaled by its width, so it fades as it narrows.
- Opacity shall apply to every fragment of a line. A batch with
  per-segment colours draws them in place of its own colour, alpha
  included, and its opacity scales both.
- Caps default to round. Connected polylines shall join without a notch
  on the outer corner or a double-blended inner corner
  (§road:texture-read-line-segments).
- A batch may be dashed, with dash lengths in target pixels measured
  along each segment from its start.

*Why `getResolution()`*: a target size pushed from Dart is logical size
times device pixel ratio, which can disagree by a pixel with the
viewport Filament rounds up at a fractional ratio.

## Passes and depth §spec:passes-and-depth

*Status: complete*

Each batch draws in two passes from one upload; the second pass is a
Thermion instance of the first. The body pass keeps only fragments with
coverage of at least 1 − 1/255 on an opaque line and writes rasterized
depth. The edge pass blends every other fragment with premultiplied
alpha, tests depth and writes none. Segments crossing the near plane are
trimmed before projection.

A depth bias moves each quad corner towards the camera along its view
ray, which keeps its pixel position, so a line drawn on a face does not
z-fight with it. The bias has two parts: a fraction of the distance, for
depth precision, and a slope part of the line's reach in pixels times a
factor, in pixel sizes. The slope part is needed because the quad lies
at its endpoint's depth across its whole width, while a face under the
line at incidence a comes tan(a) pixel sizes closer per pixel. The
default factor of 4 covers faces up to about 76°. A larger factor covers
steeper faces but lets a line show through an occluder that close in
depth. The shift shall not exceed a quarter of the corner's distance, so
a line many pixels wide near the camera stays in front of it.

Depth handling is per batch, with three modes:

- `tested`: hidden where opaque geometry lies in front.
- `onTop`: drawn over everything in the transparent pass, ordered by
  render priority.
- `hiddenStyled`: tested, plus the hidden part drawn by a third instance
  at a reduced opacity and its own dash.

*Why two passes*: the body pass gives correct occlusion with no sorting,
and the edge pass carries the anti-aliased rim the body leaves out. A
masked single pass discards half of the ramp at its threshold. Writing
`gl_FragDepth` turns off early depth testing and is wrong away from a
segment's midpoint, while rasterized depth is already exact.
Alpha-to-coverage was rejected because it needs an opaque view, and a
view that clears to transparent to show an application background
through it has none. MSAA for mesh edges is independent of line
coverage.

## Present scale §spec:present-scale

*Status: complete*

The present scale `s` is panel pixels per render-target pixel, after any
resample the operating system applies to the finished frame. The caller
reports it with `setPresentScale`. Both the anti-aliasing ramp and the
minimum line width shall measure `max(1, 1/s)` target pixels, and a
line's summed coverage shall keep its width.

| Platform and mode | `s` |
| --- | --- |
| Windows, per-monitor DPI awareness, any scale | 1 |
| macOS, default Retina mode | 1 |
| macOS, scaled ("looks like") mode | panel width ÷ framebuffer width, about 0.84 at 1800 × 1169 |
| Linux, integer output scale | 1 |
| Linux, fractional output scale | output scale ÷ GTK's integer scale, 0.625 at 1.25 |

*Why*: Flutter's Linux embedder uses GTK 3, which supports integer
scales only. At a 1.25 output, Flutter renders at a device pixel ratio
of 2 and the compositor shrinks the frame by 0.625 with a bilinear
filter. A one-pixel line then keeps between 40 % and 100 % of its
intensity depending on its sub-pixel position, so it shimmers as it
moves. macOS scaled modes resample the whole frame in the same way,
hidden by panel density. Flutter reports the integer ratio in both
cases, so `s` comes from the platform through the caller.

*Rejected*: supersampling, rendering the target at a multiple of the
panel resolution, softened lines further, because Flutter's own
downsample of the texture blurs them.

## Perspective width §spec:perspective-width

*Status: complete*

`setPerspectiveWidth` with a reference depth draws each line at its
width at that depth from the camera and scales it by reference depth
over depth at each endpoint, as geometry of fixed thickness would
foreshorten. A null reference depth draws widths in screen pixels at
every depth. An orthographic view keeps screen widths either way. A
segment that crosses the camera plane shall stay a bounded, visible
line.

*Why*: comparing screen-space widths with foreshortened ones on the
same geometry shows what the screen-space rule buys (§req:success-criteria).

## Progress and pulse §spec:progress-and-pulse

*Status: complete*

Each segment carries a progress value at each end, interpolated along
the segment. Progress is the caller's measure, typically distance along
a path normalized to [0, 1], so effects that read it move at a speed set
by distance rather than by segment count.

- `setProgress` dims every fragment behind a cursor and brightens those
  between the cursor and an optional window end.
- `setPulse` draws a band centred on a progress value with a half
  length. Inside the band, the line tints towards a colour, scales its
  opacity and its width, and may glow past its edge. The band falls off
  smoothly from its centre. The glow falls off exponentially with
  distance past the line's edge and composites in the edge pass. While
  a pulse widens or glows, the quad reaches far enough to hold it.
- The depth bias uses the line's width without the pulse, so a pulse
  does not move the line in depth.

## Consumer styles §spec:consumer-styles

*Status: complete*

A consumer style changes a line's colour and opacity per fragment from
data the consumer owns. The package keeps the geometry, coverage, passes
and depth, and runs the style inside them. A batch draws with the
built-in style unless the caller gives it a consumer style.

A style is a GLSL source that defines one function:

```glsl
void styleLine(inout ScreenLineStyle style, ScreenLineFragment fragment);
```

- `ScreenLineFragment` carries the fragment's world position, its
  progress (§spec:progress-and-pulse) and the pulse band at it.
- `ScreenLineStyle` carries the linear RGB, the alpha before coverage,
  and a glow scale of 1. Its RGB and alpha arrive as the built-in style
  computes them, with colour, opacity, progress and the pulse applied.
- The style may change those three fields and no other state. Coverage,
  dashes, the pass split and depth run after it in package code.
- The built-in style is the identity function.

The world position is in the caller's world coordinates, which the
package converts from Filament's camera-relative shading space. It lies
on the line's quad, so it includes the depth bias
(§spec:passes-and-depth).

Both passes and the `hiddenStyled` instance run the same style, so they
compute the same alpha and the body and edge passes still split every
fragment between them exactly. A style that lowers a fragment's alpha
below full moves that fragment from the body pass to the edge pass,
where it blends and writes no depth. A style shall not depend on which
pass runs it. The edge pass scales the pulse glow by the glow scale, so
a style that fades a line can fade its glow with it.

A style may declare its own material parameters.
`LineBatch.setStyleParameter` sets one by name, as a `float`, `float2`,
`float3` or `float4`. A style parameter shall not reuse a name in
`ScreenLineParams`.

`tools/compile_style.sh` builds a style into a body material and an edge
material from the package's templates, with the package's `matc`
(§spec:materials). The consumer supplies the style source and its
parameter list. The package owns the material block, its own
parameters and the pass settings.

`ScreenLineRenderer.loadStyle` loads a style's two materials through the
caller's asset loader and returns a handle that `createBatch` and
`createPackedBatch` accept. It shall reject a blob compiled for another
Filament release with `FilamatVersionException`. It shall reject a blob
built from another package release's templates with an exception that
names both releases.

The function signature and its two structs are public API, versioned
with the package. The vertex layout and the stage code stay private
(§spec:segment-data), so a change to them reaches a consumer as a
rebuild of its style with no change to its source.

A style changes colour and opacity only. An effect that moves a line's
quad, width or depth, as the pulse does, belongs in the package.

*Why*: an effect that carries a consumer's meaning, such as a fade over
a ground patch, needs data the package has no vocabulary for
(§req:constraints). A hook in the fragment stage gives the consumer that
effect and keeps coverage and depth in one tested place.

*Rejected*:

- Replacing a batch's material outright. The consumer would
  reimplement coverage and the pass split, and depend on the private
  vertex layout that §road:compact-line-buffers and
  §road:texture-read-line-segments change.
- A built-in effect for each consumer's need, which brings application
  vocabulary into the package.
- Per-vertex alpha on segments the caller subdivides. The fade steps
  along each line, and the vertex count grows with its smoothness.

## Segment data §spec:segment-data

*Status: in progress*

`packLineSegments` packs segments into four vertices each, with 32-bit
indices and no per-batch segment cap. Both passes draw from the one
upload. Per vertex: the endpoint position, the other endpoint and the
width in `CUSTOM0`, the side and end in `UV0`, the progress in `UV1`,
and linear RGBA in `COLOR`: 60 bytes, so 264 bytes per segment with its
indices. A batch's colours can be rewritten in place without a new
upload.

Large batches shall read segment data from a texture in the vertex
shader, which also gives neighbour-aware joins and dashing
(§road:texture-read-line-segments).

*Why*: a million-segment path at 264 bytes per segment needs about a
quarter of a gigabyte on the GPU. Compact attributes need about 120
bytes per segment and texture reads about 40 (estimates;
§road:line-render-benchmarks measures them).

## Materials §spec:materials

*Status: complete*

The `.mat` sources in `materials/` compile into `assets/materials/` with
the `matc` of the Filament release named in `tools/filament_version`,
which shall match the Filament release the pinned `thermion_dart`
links. CI shall fail when a committed blob no longer matches its
source. `ScreenLineRenderer.create` shall reject a blob compiled for a
different Filament release with `FilamatVersionException`, read from the
blob's header, before Filament would abort on it.

## Pixel test §spec:pixel-test

*Status: in progress*

GPU pixel tests render headless through Filament, capture the render
target and measure it. A pattern of lines from 0.25 to 3 logical pixels
wide renders at four angles and sixteen sub-pixel offsets. Nothing
resamples a captured render target, so the shader shall pass these
there before any resample handling:

- Coverage summed across the line within 0.1 target pixel of the
  requested width for lines of at least one target pixel, and width at
  half maximum within 0.1 target pixel for lines of at least two. A
  narrower line's half-maximum width read from pixel samples depends on
  its sub-pixel offset: a 1 px line half a pixel off centre samples as
  two pixels at half intensity.
- Coverage of thinner lines proportional to width within 10 %.
- Coverage spread across sub-pixel offsets under 5 %.

Further tests cover depth against meshes in each depth mode, lines on
faces at incidences up to the slope factor's limit, present scale,
perspective width, progress and the pulse. A batch with the identity
consumer style shall match the built-in materials pixel for pixel, and
a style that fades with world position shall leave no gap or double
draw where the body and edge passes meet (§spec:consumer-styles). The
suite shall also render `tech_vis`'s reference screen geometry and
record its error (§road:reference-geometry-pixel-test).

The tests need a GPU driver, so they run under the skipped-by-default
`gpu` tag.
