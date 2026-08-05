import 'grounded_answer.dart';

sealed class GroundedAnswerProviderOutcome {
  const GroundedAnswerProviderOutcome();
}

class GroundedAnswerSuccess extends GroundedAnswerProviderOutcome {
  final GroundedAnswer answer;
  const GroundedAnswerSuccess(this.answer);
}

class GroundedAnswerNotConfigured extends GroundedAnswerProviderOutcome {
  const GroundedAnswerNotConfigured();
}

class GroundedAnswerPlanUnavailable extends GroundedAnswerProviderOutcome {
  const GroundedAnswerPlanUnavailable();
}

class GroundedAnswerUnauthorized extends GroundedAnswerProviderOutcome {
  const GroundedAnswerUnauthorized();
}

class GroundedAnswerRateLimited extends GroundedAnswerProviderOutcome {
  const GroundedAnswerRateLimited();
}

class GroundedAnswerNetworkFailure extends GroundedAnswerProviderOutcome {
  const GroundedAnswerNetworkFailure();
}

class GroundedAnswerEmpty extends GroundedAnswerProviderOutcome {
  const GroundedAnswerEmpty();
}
