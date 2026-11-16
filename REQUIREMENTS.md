# tech_lines — Requirements

## Problem statement §req:problem-statement

Technical 3D views draw most of their information as lines: toolpaths,
axes, grids, dimensions, callout leaders and outlines. These lines carry
meaning at a fixed weight on screen, so they shall keep their width in
screen pixels wherever the camera puts them, where a mesh would shrink
with distance. Filament draws no such line. Each application that
builds one on Filament rebuilds the same quad expansion, coverage and
depth handling, and fixes or misses the same defects on its own.

`tech_lines` is that line renderer, built once for a Thermion scene and
tested on its own.

## Users §req:users

- **Application developers** who draw technical lines into a Thermion
  scene. The first consumers are the 3D view of a CNC controller
  application and the example application of `tech_vis`.
- **Renderer developers** who evaluate a change to the line rendering
  and need to see its defects outside any application.

## Success criteria §req:success-criteria

- A line of a given width looks the same on every platform and display
  scale, and its drawn width is the width asked for.
- A line hides behind a mesh in front of it and stops at the mesh's
  surface. A line drawn on a face shows on that face.
- A thin line fades as it narrows instead of breaking into a staircase
  as it moves.
- An animation along a line moves at a speed set by distance along the
  line, whatever the lengths of the segments it crosses.
- Screen-space widths can be compared side by side with widths that
  shrink with depth, on the same geometry.
- A renderer developer can see each known line defect in a standalone
  example, one pattern per defect.

## Constraints §req:constraints

- The package depends on `thermion_dart` and nothing above it: no
  Flutter, no application vocabulary, no colour spaces or themes. The
  caller supplies segments in its own world coordinates and colours as
  linear RGBA.
- The package renders headless under `dart test`, so its pixel tests run
  wherever a GPU driver is installed.
- The compiled materials match the Filament release that the pinned
  `thermion_dart` links.
