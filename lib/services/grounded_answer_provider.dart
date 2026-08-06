import '../models/grounded_answer_provider_outcome.dart';

abstract class GroundedAnswerProvider {
  Future<GroundedAnswerProviderOutcome> fetchGroundedAnswer(String question);
}

class NullGroundedAnswerProvider implements GroundedAnswerProvider {
  const NullGroundedAnswerProvider();

  @override
  Future<GroundedAnswerProviderOutcome> fetchGroundedAnswer(
          String question) async =>
      const GroundedAnswerNotConfigured();
}
