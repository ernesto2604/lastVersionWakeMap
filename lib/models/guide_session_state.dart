class GuideSessionState {
  final String? conversationDestination;
  final String? conversationDuration;
  final String? conversationBudget;
  final List<String> conversationPreferences;
  final String? lastConversationSummary;
  final bool hasConfirmedPlan;

  const GuideSessionState({
    this.conversationDestination,
    this.conversationDuration,
    this.conversationBudget,
    this.conversationPreferences = const [],
    this.lastConversationSummary,
    this.hasConfirmedPlan = false,
  });

  GuideSessionState copyWith({
    String? conversationDestination,
    String? conversationDuration,
    String? conversationBudget,
    List<String>? conversationPreferences,
    String? lastConversationSummary,
    bool? hasConfirmedPlan,
  }) {
    return GuideSessionState(
      conversationDestination:
          conversationDestination ?? this.conversationDestination,
      conversationDuration: conversationDuration ?? this.conversationDuration,
      conversationBudget: conversationBudget ?? this.conversationBudget,
      conversationPreferences:
          conversationPreferences ?? this.conversationPreferences,
      lastConversationSummary:
          lastConversationSummary ?? this.lastConversationSummary,
      hasConfirmedPlan: hasConfirmedPlan ?? this.hasConfirmedPlan,
    );
  }
}

enum GuideIntent {
  chatOnly,
  planGeneration,
  planRefinement,
}
