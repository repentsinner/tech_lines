import 'dart:typed_data';

/// The material-package version this build's Filament runtime accepts.
///
/// Filament defines it as `MATERIAL_VERSION` in `filament/MaterialEnums.h`,
/// bundled with Thermion's downloaded artifacts. Thermion exposes neither that
/// constant nor the chunk name to Dart, so the number is restated here.
///
/// It cannot drift unnoticed. A test asserts every committed `.filamat` is at
/// this version, and `tools/check_materials.sh` asserts those same blobs are what
/// the `matc` matching Thermion's Filament produces. Together they pin this
/// constant to the runtime without anyone tracking it by hand.
///
/// It moves when Thermion moves to a Filament release with a new material
/// format — recompile the materials, and this follows.
const int expectedFilamatVersion = 77;

/// The first chunk of every `.filamat`, stored little-endian on disk.
const String _versionChunkName = 'MAT_VERS';

/// The chunk name (8 bytes) plus its uint32 size plus the uint32 version.
const int _headerLength = 16;

/// Thrown when a byte sequence is not a readable material package.
class FilamatFormatException implements Exception {
  const FilamatFormatException(this.message);

  final String message;

  @override
  String toString() => 'FilamatFormatException: $message';
}

/// Thrown when a material package was compiled for a different Filament
/// release than the one this build links against.
///
/// Filament panics on a package it cannot parse rather than returning an
/// error, and Thermion passes the builder's result back unchecked, so the
/// failure would otherwise abort the process on the render thread. Raising
/// this first keeps it a catchable Dart error.
class FilamatVersionException implements Exception {
  const FilamatVersionException({
    required this.assetPath,
    required this.found,
    required this.expected,
  });

  /// Asset that carried the mismatched package.
  final String assetPath;

  /// Material version found in the package.
  final int found;

  /// Material version this build's Filament accepts.
  final int expected;

  @override
  String toString() =>
      'FilamatVersionException: $assetPath is material version $found, but '
      'this build of Filament accepts $expected. The material was compiled by '
      'a matc from a different Filament release. Run '
      './tools/compile_materials.sh to rebuild it.';
}

/// Reads the material version from the head of a `.filamat` package.
///
/// Throws [FilamatFormatException] when [bytes] is too short or does not begin
/// with the version chunk.
int readFilamatVersion(Uint8List bytes) {
  if (bytes.lengthInBytes < _headerLength) {
    throw FilamatFormatException(
      'package is ${bytes.lengthInBytes} bytes; a material package opens with '
      'a $_headerLength-byte $_versionChunkName chunk',
    );
  }

  // The chunk name is a 64-bit little-endian word, so it reads back reversed.
  final name = String.fromCharCodes(bytes.sublist(0, 8).reversed);
  if (name != _versionChunkName) {
    throw FilamatFormatException(
      'package opens with "$name", not "$_versionChunkName" — it is not a '
      'material package, or it is truncated',
    );
  }

  return ByteData.sublistView(bytes, 12, 16).getUint32(0, Endian.little);
}

/// Throws unless [bytes] is a material package this build's Filament accepts.
///
/// [assetPath] names the source in the error, since a caller loading several
/// materials otherwise cannot tell which one is stale.
void assertFilamatCompatible(Uint8List bytes, String assetPath) {
  final version = readFilamatVersion(bytes);
  if (version != expectedFilamatVersion) {
    throw FilamatVersionException(
      assetPath: assetPath,
      found: version,
      expected: expectedFilamatVersion,
    );
  }
}
