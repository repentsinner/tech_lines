import 'dart:typed_data';

import 'filamat_header.dart';
import 'screen_line_renderer.dart';
import 'version.dart';

/// The pass a consumer style's material draws.
enum ConsumerStylePass {
  /// The opaque pass of fully covered fragments, which writes depth.
  body,

  /// The blended pass of every other fragment.
  edge,
}

/// The material name `tools/compile_style.sh` gives a style's material:
/// `tech_lines <release> style:<name> pass:<body|edge>`.
final _stamp = RegExp(r'^tech_lines (\S+) style:([a-z0-9_]+) pass:(\w+)$');

/// Thrown when a consumer style's material was not built from this
/// release's templates, or not for the pass it is loaded as.
///
/// The templates hold the package's vertex layout and fragment stage, so
/// a style built from another release's templates can read attributes this
/// release no longer packs.
class StyleTemplateException implements Exception {
  const StyleTemplateException({
    required this.assetPath,
    required this.found,
    required this.expected,
    required this.message,
  });

  /// Asset that carried the material.
  final String assetPath;

  /// Release whose templates built the material, or null when
  /// `tools/compile_style.sh` did not build it.
  final String? found;

  /// This package's release.
  final String expected;

  /// What is wrong with the material.
  final String message;

  @override
  String toString() => 'StyleTemplateException: $assetPath $message';
}

/// Checks that [bytes] is a consumer style's material for [pass], built for
/// this Filament release from this package release's templates, and returns
/// the style's name.
///
/// Throws [FilamatVersionException] when the material was compiled for
/// another Filament release, and [StyleTemplateException] when
/// `tools/compile_style.sh` did not build it, built it from another
/// release's templates, or built it for the other pass.
String checkConsumerStyle(
  Uint8List bytes,
  String assetPath,
  ConsumerStylePass pass,
) {
  assertFilamatCompatible(bytes, assetPath);
  final name = readFilamatName(bytes);
  final stamp = _stamp.firstMatch(name);
  if (stamp == null) {
    throw StyleTemplateException(
      assetPath: assetPath,
      found: null,
      expected: techLinesVersion,
      message:
          'is the material "$name", not a consumer style. Build styles with '
          'tools/compile_style.sh.',
    );
  }
  final release = stamp.group(1)!;
  if (release != techLinesVersion) {
    throw StyleTemplateException(
      assetPath: assetPath,
      found: release,
      expected: techLinesVersion,
      message:
          'was built from the templates of tech_lines $release, but this is '
          'tech_lines $techLinesVersion. Rebuild it with the '
          'tools/compile_style.sh of tech_lines $techLinesVersion.',
    );
  }
  if (stamp.group(3) != pass.name) {
    throw StyleTemplateException(
      assetPath: assetPath,
      found: release,
      expected: techLinesVersion,
      message:
          'is the ${stamp.group(3)} material of style "${stamp.group(2)}", '
          'loaded as its ${pass.name} material.',
    );
  }

  return stamp.group(2)!;
}

/// Throws an [ArgumentError] unless [name] and [value] can set a consumer
/// style's own parameter: a name the package does not set itself, and one
/// to four floats.
void checkStyleParameter(String name, List<double> value) {
  if (ScreenLineParams.all.contains(name)) {
    throw ArgumentError.value(
      name,
      'name',
      'is a parameter the package sets itself',
    );
  }
  if (value.isEmpty || value.length > 4) {
    throw ArgumentError.value(
      value,
      'value',
      'must hold one to four floats, for a float to a float4',
    );
  }
}
