import 'dart:io';
import 'dart:typed_data';

import 'package:tech_lines/tech_lines.dart';
import 'package:test/test.dart';

/// Builds a `.filamat` prefix of a version chunk and a name chunk, as matc
/// lays them out: an 8-byte chunk name stored little-endian, a uint32
/// payload size, then the payload.
Uint8List _blob({int? version, String? name}) {
  final bytes = BytesBuilder();
  void chunk(String type, List<int> payload) {
    bytes.add(Uint8List.fromList(type.codeUnits.reversed.toList()));
    bytes.add(
      (ByteData(
        4,
      )..setUint32(0, payload.length, Endian.little)).buffer.asUint8List(),
    );
    bytes.add(payload);
  }

  chunk(
    'MAT_VERS',
    (ByteData(4)
          ..setUint32(0, version ?? expectedFilamatVersion, Endian.little))
        .buffer
        .asUint8List(),
  );
  chunk('MAT_FEAT', [1]);
  if (name != null) chunk('MAT_NAME', [...name.codeUnits, 0]);

  return bytes.toBytes();
}

String _stamp(String release, String style, String pass) =>
    'tech_lines $release style:$style pass:$pass';

/// Names in a material's `parameters` block.
Set<String> _declaredParameters(String matPath) {
  final source = File(matPath).readAsStringSync();
  final block = RegExp(
    r'parameters\s*:\s*\[(.*?)\]',
    dotAll: true,
  ).firstMatch(source)!.group(1)!;

  return {
    for (final m in RegExp(r'name\s*:\s*(\w+)').allMatches(block)) m.group(1)!,
  };
}

void main() {
  group('readFilamatName', () {
    test('reads the name chunk', () {
      expect(readFilamatName(_blob(name: 'ScreenLineBody')), 'ScreenLineBody');
    });

    test('rejects a package with no name chunk', () {
      expect(
        () => readFilamatName(_blob()),
        throwsA(isA<FilamatFormatException>()),
      );
    });

    test('reads the name from the committed body material', () {
      final bytes = File(
        'assets/materials/screen_line_body.filamat',
      ).readAsBytesSync();
      expect(readFilamatName(bytes), 'ScreenLineBody');
    });
  });

  group('checkConsumerStyle', () {
    test('accepts a style built from this release and returns its name', () {
      final bytes = _blob(name: _stamp(techLinesVersion, 'fade', 'body'));
      expect(
        checkConsumerStyle(bytes, 'fade_body.filamat', ConsumerStylePass.body),
        'fade',
      );
    });

    test('rejects a style built from another release, naming both', () {
      final bytes = _blob(name: _stamp('0.0.1', 'fade', 'edge'));
      expect(
        () => checkConsumerStyle(
          bytes,
          'fade_edge.filamat',
          ConsumerStylePass.edge,
        ),
        throwsA(
          isA<StyleTemplateException>()
              .having((e) => e.found, 'found', '0.0.1')
              .having((e) => e.expected, 'expected', techLinesVersion)
              .having(
                (e) => e.toString(),
                'message',
                allOf(
                  contains('0.0.1'),
                  contains(techLinesVersion),
                  contains('fade_edge.filamat'),
                ),
              ),
        ),
      );
    });

    test('rejects a material that compile_style.sh did not build', () {
      final bytes = _blob(name: 'ScreenLineBody');
      expect(
        () => checkConsumerStyle(bytes, 'x.filamat', ConsumerStylePass.body),
        throwsA(
          isA<StyleTemplateException>().having((e) => e.found, 'found', null),
        ),
      );
    });

    test('rejects a material built for the other pass', () {
      final bytes = _blob(name: _stamp(techLinesVersion, 'fade', 'edge'));
      expect(
        () => checkConsumerStyle(bytes, 'x.filamat', ConsumerStylePass.body),
        throwsA(isA<StyleTemplateException>()),
      );
    });

    test('rejects a material for another Filament release first', () {
      final bytes = _blob(
        version: expectedFilamatVersion - 1,
        name: _stamp(techLinesVersion, 'fade', 'body'),
      );
      expect(
        () => checkConsumerStyle(bytes, 'x.filamat', ConsumerStylePass.body),
        throwsA(isA<FilamatVersionException>()),
      );
    });
  });

  group('checkStyleParameter', () {
    test('accepts a style parameter of one to four floats', () {
      for (final length in [1, 2, 3, 4]) {
        expect(
          () => checkStyleParameter('fadeCenter', List.filled(length, 0)),
          returnsNormally,
        );
      }
    });

    test('rejects a name the package sets itself', () {
      for (final name in ScreenLineParams.all) {
        expect(
          () => checkStyleParameter(name, [1]),
          throwsArgumentError,
          reason: name,
        );
      }
    });

    test('rejects a value of no floats or more than four', () {
      expect(() => checkStyleParameter('fade', []), throwsArgumentError);
      expect(
        () => checkStyleParameter('fade', [1, 2, 3, 4, 5]),
        throwsArgumentError,
      );
    });
  });

  test('ScreenLineParams.all names every parameter the materials declare', () {
    expect(
      ScreenLineParams.all,
      _declaredParameters('materials/screen_line_body.mat'),
    );
    expect(
      ScreenLineParams.all,
      _declaredParameters('materials/screen_line_edge.mat'),
    );
  });

  test('techLinesVersion is the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version: (\S+)$',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(techLinesVersion, version);
  });
}
