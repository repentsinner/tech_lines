/// Screen-space lines of constant pixel width in a Thermion scene.
///
/// Segments come in the caller's world coordinates with linear RGBA
/// colours. Each line draws with exact pixel coverage: an opaque body pass
/// that writes depth and a blended edge pass for its anti-aliased rim.
library;

export 'src/filamat_header.dart';
export 'src/line_packer.dart';
export 'src/line_segments.dart';
export 'src/line_style.dart';
export 'src/screen_line_renderer.dart';
