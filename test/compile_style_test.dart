@Tags(['matc'])
library;

import 'dart:io';

import 'package:tech_lines/tech_lines.dart';
import 'package:test/test.dart';

/// Runs tools/compile_style.sh with [args].
Future<ProcessResult> _compile(List<String> args) =>
    Process.run('tools/compile_style.sh', args);

void main() {
  late Directory out;

  setUp(() => out = Directory.systemTemp.createTempSync('compile_style_'));
  tearDown(() => out.deleteSync(recursive: true));

  test('builds a body and an edge material stamped with the release', () async {
    final result = await _compile([
      '--params',
      'test/styles/fade.params',
      'fade',
      'test/styles/fade.fs',
      out.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');

    for (final pass in ConsumerStylePass.values) {
      final file = File('${out.path}/fade_${pass.name}.filamat');
      expect(file.existsSync(), isTrue, reason: file.path);
      expect(
        checkConsumerStyle(file.readAsBytesSync(), file.path, pass),
        'fade',
      );
    }
  });

  test(
    'stamps the templates\' revision, which a release leaves alone',
    () async {
      final result = await _compile([
        'identity',
        'test/styles/identity.fs',
        out.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');

      // The release automation bumps the version after a merge, so a stamp
      // that held it would leave every committed style blob stale.
      expect(
        readFilamatName(
          File('${out.path}/identity_edge.filamat').readAsBytesSync(),
        ),
        'tech_lines templates:$styleTemplateRevision style:identity pass:edge',
      );
    },
  );

  test('builds a style that declares no parameters', () async {
    final result = await _compile([
      'identity',
      'test/styles/identity.fs',
      out.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(File('${out.path}/identity_body.filamat').existsSync(), isTrue);
  });

  test('rejects a parameter that reuses a package name', () async {
    final params = File('${out.path}/clash.params')
      ..writeAsStringSync('{ type : float, name : opacity }\n');
    final result = await _compile([
      '--params',
      params.path,
      'clash',
      'test/styles/identity.fs',
      out.path,
    ]);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('opacity'));
    expect(File('${out.path}/clash_body.filamat').existsSync(), isFalse);
  });

  test('rejects a style name that is not lower snake case', () async {
    final result = await _compile([
      'Bad-Name',
      'test/styles/identity.fs',
      out.path,
    ]);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Bad-Name'));
  });
}
