# tech_lines example

This app draws line patterns chosen to expose line-rendering defects:
width, sub-pixel fade, angle-dependent aliasing, moiré, shimmer under a
slow pan, z-fighting on faces, lines piercing solids, near-plane spikes,
translucency and polyline corners. One pattern draws a ground grid in
a consumer style that fades it toward the edge of its patch.

## Run the example

Each release on GitHub carries a build of the example for Linux, macOS
and Windows. The macOS build is unsigned, so macOS quarantines it on
download. To clear the quarantine, run
`xattr -dr com.apple.quarantine tech_lines_example.app` after unzipping.

To build it yourself, run from this directory with `linux`, `macos` or
`windows` as the device:

```sh
flutter run -d linux --release
```

To open on a pattern, pass its name or a prefix of it after `--`, for
example `flutter run -d linux --release -- --pattern=lines`. To start
with pulse effects on, pass `--pulse=` with their names, for example
`--pulse=color,glow`.

On Linux, Flutter 3.50's embedder deadlocks on a Wayland window resize,
so build with Flutter 3.47 there or leave the window at its first size.

## Controls

- ← and → change the pattern.
- Pulse sends a band along each path pattern, such as Toolpath, that
  changes the lines' colour, opacity, width or glow. It moves at a
  constant speed in world units, because each segment's progress is its
  distance along the path. "Progress by segment count" gives every
  segment equal progress instead, for comparison.
- D starts and stops a slow sub-pixel pan.
- P switches between screen-space widths and perspective widths, which
  foreshorten with depth and match the screen-space width at the orbit
  target.
- Drag to orbit and scroll to zoom.
- Supersample renders the 3D view at twice the frame's resolution, so
  Flutter's 2:1 sample averages it down before the platform resamples
  the frame.
- Present scale tunes the renderer for a platform that shrinks the
  finished frame: below 1, the ramp and minimum width widen to 1/s
  target pixels. A 1.25 Linux display, where Flutter renders at a pixel
  ratio of 2, presents at 0.625.
