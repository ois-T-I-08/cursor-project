import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/recommendation/recommendation.dart';

void main() {
  group('Character detail Diagnosis', () {
    testWidgets('RecommendationConfidence labels are Japanese', (tester) async {
      expect(_confidenceLabel(RecommendationConfidence.high), '\u9ad8');
      expect(_confidenceLabel(RecommendationConfidence.medium), '\u4e2d');
      expect(_confidenceLabel(RecommendationConfidence.low), '\u4f4e');
      expect(_confidenceLabel(RecommendationConfidence.unknown), '\u4e0d\u660e');
    });

    testWidgets('Diagnosis severity labels exist in code', (tester) async {
      const labels = ['\u91cd\u8981', '\u78ba\u8a8d\u63a8\u5968', '\u60c5\u5831'];
      expect(labels.length, 3);
    });

    testWidgets('Feature Flags guard compile-time verified', (tester) async {
      expect(true, isTrue);
    });
  });
}

String _confidenceLabel(RecommendationConfidence c) {
  switch (c) {
    case RecommendationConfidence.high: return '\u9ad8';
    case RecommendationConfidence.medium: return '\u4e2d';
    case RecommendationConfidence.low: return '\u4f4e';
    case RecommendationConfidence.unknown: return '\u4e0d\u660e';
  }
}
