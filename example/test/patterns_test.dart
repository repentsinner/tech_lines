import 'package:flutter_test/flutter_test.dart';
import 'package:tech_lines_example/patterns.dart';

void main() {
  for (final progressByCount in [false, true]) {
    final options = BuildOptions(progressByCount: progressByCount);

    group('progressByCount: $progressByCount', () {
      for (final pattern in patterns) {
        test('${pattern.name} builds segments', () {
          final batches = pattern.build(options);

          expect(batches, isNotEmpty);
          for (final batch in batches) {
            expect(batch.segments.segmentCount, greaterThan(0));
            if (batch.consumerStyle case final style?) {
              expect(consumerStyles, contains(style));
            }
          }
        });
      }
    });
  }
}
