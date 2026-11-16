# tech_lines — Roadmap

## Reference validation §road:reference-validation

### Reference geometry pixel test §road:reference-geometry-pixel-test

Render `tech_vis`'s reference screen geometry in the GPU-tagged pixel
test and record its error against `tech_vis`'s line rule, reading the
reference vectors as test data so the package takes no dependency on
`tech_vis`, in `test/gpu/`. §spec:pixel-test. Closes section.

**Verify:** `dart test --run-skipped -t gpu` renders the reference
geometry and reports its error, and the error is within `tech_vis`'s
tolerance.

## Consumer styles §road:consumer-styles

### Style hook §road:style-hook

Add the `styleLine` hook to the line materials' fragment stage, with
`tools/compile_style.sh`, `ScreenLineRenderer.loadStyle` and
`LineBatch.setStyleParameter`, in `materials/`, `tools/` and
`lib/src/screen_line_renderer.dart`. §spec:consumer-styles. Closes
section.

**Verify:** In `dart test --run-skipped -t gpu`, the identity style
matches the built-in materials pixel for pixel, and a style that fades
with world position leaves no gap or double draw at the body and edge
seam. The example draws a batch with a consumer style.

## Large batches §road:large-batches

### Compact line buffers §road:compact-line-buffers

Pack the per-vertex data compactly, with endpoints, width, progress and
colour in the fewest attributes both passes can read, in
`lib/src/line_packer.dart` and the line materials.
§spec:segment-data.

### Line render benchmarks §road:line-render-benchmarks

Time buffer build, upload, first frame, GPU frame and progress update
at 10⁴, 10⁵ and 10⁶ segments in GPU-tagged tests, and record bytes per
segment. Depends on §road:compact-line-buffers. §spec:segment-data.

### Texture-read segments and joins §road:texture-read-line-segments

Read large batches' segment data from a texture in the vertex shader,
with miter and bevel joins and dashing, keeping compact buffers as the
fallback. Depends on §road:line-render-benchmarks.
§spec:segment-data, §spec:width-and-coverage. Closes section.

**Verify:** A million-segment batch builds, uploads and draws with the
benchmark's figures recorded. A connected polyline in the example shows
no notch on the outer corner and no double-blended inner corner, and
the pixel tests pass with texture reads on and off.
