import '../models/grounded_answer.dart';

abstract class GroundedAnswerProvider {
  /// Returns a [GroundedAnswer] for [question], or null if the question is
  /// empty, the provider has no result, or the provider fails gracefully.
  Future<GroundedAnswer?> fetchGroundedAnswer(String question);
}

class NullGroundedAnswerProvider implements GroundedAnswerProvider {
  const NullGroundedAnswerProvider();

  @override
  Future<GroundedAnswer?> fetchGroundedAnswer(String question) async => null;
}
