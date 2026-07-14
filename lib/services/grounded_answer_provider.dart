import '../models/grounded_answer.dart';

abstract class GroundedAnswerProvider {
  /// Returns a [GroundedAnswer] for [question], or null if the question is
  /// empty, the provider has no result, or the provider fails gracefully.
  Future<GroundedAnswer?> fetchGroundedAnswer(String question);

  /// True when this provider can return real results.
  /// Stub/null providers override this to false so callers can skip
  /// expensive pipeline work before a real integration is wired up.
  bool get isConfigured => true;
}

class NullGroundedAnswerProvider implements GroundedAnswerProvider {
  const NullGroundedAnswerProvider();

  @override
  bool get isConfigured => false;

  @override
  Future<GroundedAnswer?> fetchGroundedAnswer(String question) async => null;
}
