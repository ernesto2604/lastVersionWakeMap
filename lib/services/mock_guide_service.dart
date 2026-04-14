import 'dart:math';
import 'package:uuid/uuid.dart';
import '../models/chat_message_model.dart';
import '../models/mock_plan_model.dart';

class MockGuideService {
  static const _uuid = Uuid();
  static final _random = Random();

  /// Generate a mock travel plan near the given arrival coordinates.
  MockPlanModel generatePlan(double lat, double lng) {
    // Create 3 mock stops near arrival location with small offsets
    final stops = [
      MockPlanStop(
        name: 'Historic City Centre Walk',
        description:
            'Take a scenic walk through the historic centre exploring architecture and local culture.',
        latitude: lat + 0.002,
        longitude: lng + 0.001,
      ),
      MockPlanStop(
        name: 'Local Market & Street Food',
        description:
            'Grab a bite at the popular local market known for authentic street food.',
        latitude: lat - 0.001,
        longitude: lng + 0.003,
      ),
      MockPlanStop(
        name: 'Riverside Park & Viewpoint',
        description:
            'Relax at the riverside park and enjoy panoramic views of the area.',
        latitude: lat + 0.003,
        longitude: lng - 0.002,
      ),
    ];

    return MockPlanModel(
      title: 'Your Quick City Guide',
      summary:
          'A simple 2–3 hour walking plan covering sights, food, and relaxation near your arrival point.',
      estimatedDuration: '~2h',
      estimatedBudget: '£15-£25',
      stops: stops,
    );
  }

  /// Generate a keyword-based chat response and optionally modify the plan.
  /// Returns a tuple of (response text, updated plan or null).
  ({String response, MockPlanModel? updatedPlan}) handleMessage(
    String userMessage,
    MockPlanModel? currentPlan,
    double arrivalLat,
    double arrivalLng,
  ) {
    final msg = userMessage.toLowerCase();

    if (currentPlan == null) {
      final plan = generatePlan(arrivalLat, arrivalLng);
      return (
        response: "Here's a fresh plan I've put together for you!",
        updatedPlan: plan,
      );
    }

    // ── Keyword matching ──

    if (msg.contains('cheap') || msg.contains('budget') || msg.contains('free')) {
      final updatedPlan = MockPlanModel(
        title: currentPlan.title,
        summary: 'A budget-friendly plan focusing on free attractions and affordable eats.',
        estimatedDuration: currentPlan.estimatedDuration ?? '~2h',
        estimatedBudget: '£8-£15',
        stops: [
          MockPlanStop(
            name: 'Free Walking Tour',
            description: 'Join a free guided walking tour of the city highlights.',
            latitude: arrivalLat + 0.001,
            longitude: arrivalLng + 0.001,
          ),
          MockPlanStop(
            name: 'Public Park & Gardens',
            description: 'Enjoy the beautiful public gardens — completely free.',
            latitude: arrivalLat + 0.002,
            longitude: arrivalLng - 0.001,
          ),
          MockPlanStop(
            name: 'Street Food Corner',
            description: 'Grab cheap and delicious street food from local vendors.',
            latitude: arrivalLat - 0.001,
            longitude: arrivalLng + 0.002,
          ),
        ],
      );
      return (
        response:
            "I've updated the plan to be more budget-friendly! Focused on free attractions and affordable food.",
        updatedPlan: updatedPlan,
      );
    }

    if (msg.contains('food') || msg.contains('eat') || msg.contains('restaurant') || msg.contains('hungry')) {
      final newStops = List<MockPlanStop>.from(currentPlan.stops);
      newStops.add(MockPlanStop(
        name: 'Top-Rated Local Restaurant',
        description: 'A highly recommended restaurant with excellent local cuisine.',
        latitude: arrivalLat + 0.001 + _random.nextDouble() * 0.002,
        longitude: arrivalLng + 0.001 + _random.nextDouble() * 0.002,
      ));
      final updatedPlan = MockPlanModel(
        title: currentPlan.title,
        summary: '${currentPlan.summary} Added a food stop!',
        estimatedDuration: currentPlan.estimatedDuration ?? '~3h',
        estimatedBudget: currentPlan.estimatedBudget ?? '£20-£35',
        stops: newStops,
      );
      return (
        response:
            "Great idea! I've added a top-rated local restaurant to your plan. 🍽️",
        updatedPlan: updatedPlan,
      );
    }

    if (msg.contains('short') || msg.contains('quick') || msg.contains('less') || msg.contains('fewer')) {
      final shorterStops = currentPlan.stops.take(2).toList();
      final updatedPlan = MockPlanModel(
        title: currentPlan.title,
        summary: 'A shorter plan with just the top highlights — about 1 hour.',
        estimatedDuration: '~1h',
        estimatedBudget: currentPlan.estimatedBudget ?? '£12-£20',
        stops: shorterStops,
      );
      return (
        response:
            "Done! I've trimmed the plan down to the top 2 stops for a quicker visit. ⚡",
        updatedPlan: updatedPlan,
      );
    }

    if (msg.contains('museum') || msg.contains('art') || msg.contains('culture') || msg.contains('history')) {
      final newStops = List<MockPlanStop>.from(currentPlan.stops);
      newStops.add(MockPlanStop(
        name: 'City Museum',
        description: 'Explore the city\'s history and cultural heritage at the local museum.',
        latitude: arrivalLat - 0.002,
        longitude: arrivalLng - 0.001,
      ));
      final updatedPlan = MockPlanModel(
        title: currentPlan.title,
        summary: '${currentPlan.summary} Added a cultural stop!',
        estimatedDuration: currentPlan.estimatedDuration ?? '~3h',
        estimatedBudget: currentPlan.estimatedBudget ?? '£18-£30',
        stops: newStops,
      );
      return (
        response:
            "I've added a museum visit to your plan. Perfect for culture lovers! 🏛️",
        updatedPlan: updatedPlan,
      );
    }

    if (msg.contains('nature') || msg.contains('park') || msg.contains('outdoor') || msg.contains('walk')) {
      final newStops = List<MockPlanStop>.from(currentPlan.stops);
      newStops.add(MockPlanStop(
        name: 'Nature Trail',
        description: 'A scenic nature trail with beautiful views and fresh air.',
        latitude: arrivalLat + 0.004,
        longitude: arrivalLng + 0.003,
      ));
      final updatedPlan = MockPlanModel(
        title: currentPlan.title,
        summary: '${currentPlan.summary} Added an outdoor activity!',
        estimatedDuration: currentPlan.estimatedDuration ?? '~3h',
        estimatedBudget: currentPlan.estimatedBudget ?? '£15-£25',
        stops: newStops,
      );
      return (
        response:
            "Added a nature trail to your plan — great choice for outdoor lovers! 🌿",
        updatedPlan: updatedPlan,
      );
    }

    // ── Generic responses ──
    final genericResponses = [
      "That's a great point! I've noted it. Is there anything else you'd like to adjust?",
      "Got it! Let me know if you want to change stops, budget, or duration.",
      "I hear you! Try asking me to make it cheaper, shorter, or add food, museums, or nature.",
      "Sure thing! Want me to add specific types of activities? Just say the word.",
    ];
    final response = genericResponses[_random.nextInt(genericResponses.length)];
    return (response: response, updatedPlan: null);
  }

  String conversationalFallback({
    required String userMessage,
    String? destination,
    String? duration,
    String? budget,
    List<String> preferences = const [],
  }) {
    final msg = userMessage.toLowerCase();
    final prefs = preferences.isNotEmpty ? preferences.join(', ') : 'relaxed highlights';
    final where = (destination != null && destination.trim().isNotEmpty)
        ? destination.trim()
        : 'your destination';

    if (msg.contains('food')) {
      return 'If food is your priority in $where, I would mix one classic local spot with a market-style stop and a relaxed evening area. I can tailor this to your budget and turn it into a full plan whenever you say "create the plan".';
    }

    if (msg.contains('budget') || msg.contains('cheap')) {
      return 'Great, I can keep this budget-friendly in $where by prioritizing free sights and lower-cost food areas. If you want, I can now create a full plan based on that.';
    }

    final durationPart = (duration != null && duration.isNotEmpty)
        ? 'for $duration '
        : '';
    final budgetPart = (budget != null && budget.isNotEmpty)
        ? 'with a budget around $budget '
        : '';

    return 'Nice direction. For $where, I suggest a balanced itinerary $durationPart${budgetPart}focused on $prefs. If this sounds right, say "create the plan" and I will turn it into a structured route.';
  }

  MockPlanModel generatePlanFromConversation({
    required double lat,
    required double lng,
    String? destination,
    String? duration,
    String? budget,
    List<String> preferences = const [],
  }) {
    final base = generatePlan(lat, lng);
    final prefText = preferences.isEmpty ? '' : ' Focus: ${preferences.join(', ')}.';
    final durationText = (duration != null && duration.trim().isNotEmpty)
        ? ' Duration target: ${duration.trim()}.'
        : '';
    final budgetText = (budget != null && budget.trim().isNotEmpty)
        ? ' Budget target: ${budget.trim()}.'
        : '';

    return MockPlanModel(
      title: destination != null && destination.trim().isNotEmpty
          ? 'Plan for ${destination.trim()}'
          : base.title,
      summary: '${base.summary}$prefText$durationText$budgetText',
      estimatedDuration: duration?.trim().isNotEmpty == true
          ? duration!.trim()
          : base.estimatedDuration,
      estimatedBudget: budget?.trim().isNotEmpty == true
          ? budget!.trim()
          : base.estimatedBudget,
      stops: base.stops,
    );
  }

  ({String response, MockPlanModel updatedPlan}) refinePlanFallback({
    required String userMessage,
    required MockPlanModel currentPlan,
    required double arrivalLat,
    required double arrivalLng,
  }) {
    final result = handleMessage(
      userMessage,
      currentPlan,
      arrivalLat,
      arrivalLng,
    );

    if (result.updatedPlan != null) {
      return (response: result.response, updatedPlan: result.updatedPlan!);
    }

    return (
      response: 'I kept your current plan unchanged. Tell me what to adjust and I can refine it.',
      updatedPlan: currentPlan,
    );
  }

  /// Generate the initial assistant welcome message.
  ChatMessageModel createWelcomeMessage() {
    return ChatMessageModel(
      id: _uuid.v4(),
      text:
          "Welcome! You've just arrived. 🎉\nI've created a starter plan for you. Ask me to refine it anytime, or tell me the style you want and I'll adjust it.",
      isUser: false,
      timestamp: DateTime.now(),
    );
  }

  /// Create a chat message from the assistant.
  ChatMessageModel createAssistantMessage(String text) {
    return ChatMessageModel(
      id: _uuid.v4(),
      text: text,
      isUser: false,
      timestamp: DateTime.now(),
    );
  }

  /// Create a chat message from the user.
  ChatMessageModel createUserMessage(String text) {
    return ChatMessageModel(
      id: _uuid.v4(),
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );
  }
}
