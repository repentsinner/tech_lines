import 'line_segments.dart';

/// How a line ends. The index is the shader's `capStyle`.
enum LineCap {
  /// Stops at the endpoint.
  butt,

  /// Extends a half-width disc past the endpoint.
  round,

  /// Extends a half-width square past the endpoint.
  square,
}

/// How a line meets the depth buffer.
enum LineDepthMode {
  /// Hidden where opaque geometry lies in front.
  tested,

  /// Drawn over everything, in the transparent pass, ordered by priority.
  onTop,

  /// Tested, plus the hidden part drawn at [LineStyle.hiddenOpacity] with
  /// [LineStyle.hiddenDash].
  hiddenStyled,
}

/// A dash pattern in target pixels, measured from each segment's start.
final class LineDash {
  const LineDash(this.onPixels, this.offPixels);

  final double onPixels;
  final double offPixels;
}

/// Uniform appearance of one batch of lines.
final class LineStyle {
  const LineStyle({
    required this.widthPixels,
    required this.color,
    this.opacity = 1,
    this.cap = LineCap.round,
    this.depthMode = LineDepthMode.tested,
    this.dash,
    this.hiddenOpacity = defaultHiddenOpacity,
    this.hiddenDash = defaultHiddenDash,
    this.priority = defaultPriority,
    this.progressDim = defaultProgressDim,
    this.progressBoost = defaultProgressBoost,
  });

  /// Opacity of the hidden part of a [LineDepthMode.hiddenStyled] line,
  /// relative to the visible part.
  static const defaultHiddenOpacity = 0.35;

  /// Dash of the hidden part of a [LineDepthMode.hiddenStyled] line.
  static const defaultHiddenDash = LineDash(4, 3);

  /// Filament's default render priority, the middle of its 0–7 range.
  static const defaultPriority = 4;

  /// RGB factor behind the progress cursor.
  static const defaultProgressDim = 0.3;

  /// RGB factor between the progress cursor and the window end.
  static const defaultProgressBoost = 2.0;

  /// Width in logical pixels where [LineSegments.widthsPixels] is null.
  final double widthPixels;

  /// Colour where [LineSegments.colors] is null.
  final LinearRgba color;

  final double opacity;
  final LineCap cap;
  final LineDepthMode depthMode;

  /// Dash of the visible line, or null for a solid line.
  final LineDash? dash;

  final double hiddenOpacity;
  final LineDash? hiddenDash;

  /// Filament render priority, 0 (first) to 7 (last).
  final int priority;

  final double progressDim;
  final double progressBoost;
}

/// A band that travels along a batch's progress, changing how the lines
/// inside it draw.
///
/// Progress comes from [LineSegments.progress] and interpolates across
/// each segment, so with progress measured as distance along a path the
/// band moves at constant speed however the path is split into segments.
final class LinePulse {
  const LinePulse({
    required this.center,
    required this.halfLength,
    this.color = const LinearRgba(1, 1, 1),
    this.colorMix = 1,
    this.opacity = 1,
    this.widthScale = 1,
    this.glowPixels = 0,
  });

  /// Progress at the middle of the band.
  final double center;

  /// Progress from the middle of the band to where it fades out.
  final double halfLength;

  /// Colour the band tints the line towards, and the glow's colour.
  final LinearRgba color;

  /// How far, 0 to 1, the band tints the line towards [color].
  final double colorMix;

  /// Opacity factor at the middle of the band.
  final double opacity;

  /// Width factor at the middle of the band.
  final double widthScale;

  /// Length in target pixels over which the glow falls to about a third
  /// of its strength past the line's edge; 0 draws no glow.
  final double glowPixels;
}
