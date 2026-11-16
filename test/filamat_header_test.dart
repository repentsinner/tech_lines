import 'dart:io';
import 'dart:typed_data';

import 'package:tech_lines/tech_lines.dart';
import 'package:test/test.dart';

/// Builds a minimal `.filamat` prefix: an 8-byte chunk name stored
/// little-endian, a uint32 payload size, then the payload.
Uint8List _header({String chunk = 'MAT_VERS', int size = 4, int? version}) {
  final bytes = BytesBuilder();
  bytes.add(Uint8List.fromList(chunk.codeUnits.reversed.toList()));
  final trailer = ByteData(8)
    ..setUint32(0, size, Endian.little)
    ..setUint32(4, version ?? 0, Endian.little);
  bytes.add(trailer.buffer.asUint8List());
  return bytes.toBytes();
}

void main() {
  group('readFilamatVersion', () {
    test('reads the version from the MAT_VERS chunk', () {
      expect(readFilamatVersion(_header(version: 75)), 75);
    });

    test('reads a version other than the expected one', () {
      // The stale-toolchain case: matc from Filament 1.58 emits 69.
      expect(readFilamatVersion(_header(version: 69)), 69);
    });

    test('rejects a package that does not start with MAT_VERS', () {
      expect(
        () => readFilamatVersion(_header(chunk: 'NOTAVERS', version: 75)),
        throwsA(isA<FilamatFormatException>()),
      );
    });

    test('rejects a truncated package', () {
      expect(
        () => readFilamatVersion(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<FilamatFormatException>()),
      );
    });
  });

  group('assertFilamatCompatible', () {
    test('accepts a package at the expected version', () {
      expect(
        () => assertFilamatCompatible(
          _header(version: expectedFilamatVersion),
          'assets/materials/x.filamat',
        ),
        returnsNormally,
      );
    });

    test('rejects a package from a different Filament release', () {
      expect(
        () => assertFilamatCompatible(
          _header(version: expectedFilamatVersion - 6),
          'assets/materials/x.filamat',
        ),
        throwsA(
          isA<FilamatVersionException>()
              .having((e) => e.found, 'found', expectedFilamatVersion - 6)
              .having((e) => e.expected, 'expected', expectedFilamatVersion)
              .having((e) => e.assetPath, 'assetPath', contains('x.filamat')),
        ),
      );
    });

    test('the message names both versions and the asset', () {
      final message = const FilamatVersionException(
        assetPath: 'assets/materials/x.filamat',
        found: 69,
        expected: 75,
      ).toString();
      expect(message, contains('69'));
      expect(message, contains('75'));
      expect(message, contains('x.filamat'));
    });
  });

  group('committed material assets', () {
    // Ties the constant to what actually ships. tools/check_materials.sh
    // separately proves those blobs came from the matc matching thermion's
    // Filament, so the two checks together keep the constant honest without
    // anyone maintaining it by hand.
    for (final path in ['assets/materials']) {
      test('every .filamat under $path is at the expected version', () {
        final dir = Directory(path);
        expect(
          dir.existsSync(),
          isTrue,
          reason: 'expected ${dir.absolute.path} to exist',
        );

        final materials = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.filamat'))
            .toList();
        expect(materials, isNotEmpty, reason: 'no .filamat assets found');

        for (final file in materials) {
          final version = readFilamatVersion(file.readAsBytesSync());
          expect(
            version,
            expectedFilamatVersion,
            reason:
                '${file.uri.pathSegments.last} is version $version; recompile '
                'with ./tools/compile_materials.sh',
          );
        }
      });
    }
  });
}
