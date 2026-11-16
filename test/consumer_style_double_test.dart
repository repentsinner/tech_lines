import 'package:tech_lines/tech_lines.dart';
import 'package:test/test.dart';

/// A consumer's test double: a style it can hand a mocked renderer, which
/// never reads the materials a real style holds.
class _StyleDouble implements ConsumerStyle {
  @override
  String get name => 'fade';
}

void main() {
  test('a consumer can stand in a ConsumerStyle in its own tests', () {
    final ConsumerStyle style = _StyleDouble();

    expect(style.name, 'fade');
  });
}
