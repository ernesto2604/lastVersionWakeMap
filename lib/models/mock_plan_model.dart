class MockPlanStop {
  final String name;
  final String description;
  final double latitude;
  final double longitude;

  MockPlanStop({
    required this.name,
    required this.description,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory MockPlanStop.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] ?? '').toString().trim();
    final description = (json['description'] ?? '').toString().trim();
    final latitude = (json['latitude'] as num?)?.toDouble();
    final longitude = (json['longitude'] as num?)?.toDouble();

    if (name.isEmpty || description.isEmpty || latitude == null || longitude == null) {
      throw const FormatException('Invalid plan stop schema');
    }

    return MockPlanStop(
      name: name,
      description: description,
      latitude: latitude,
      longitude: longitude,
    );
  }
}

class MockPlanModel {
  final String title;
  String summary;
  String? estimatedDuration;
  String? estimatedBudget;
  List<MockPlanStop> stops;

  MockPlanModel({
    required this.title,
    required this.summary,
    this.estimatedDuration,
    this.estimatedBudget,
    required this.stops,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'summary': summary,
      'estimated_duration': estimatedDuration ?? '',
      'estimated_budget': estimatedBudget ?? '',
      'stops': stops.map((s) => s.toJson()).toList(),
    };
  }

  factory MockPlanModel.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] ?? '').toString().trim();
    final summary = (json['summary'] ?? '').toString().trim();
    final estimatedDuration = (json['estimated_duration'] ?? '').toString().trim();
    final estimatedBudget = (json['estimated_budget'] ?? '').toString().trim();
    final stopsRaw = json['stops'];

    if (title.isEmpty || summary.isEmpty || stopsRaw is! List) {
      throw const FormatException('Invalid guide plan schema');
    }

    final parsedStops = stopsRaw
        .map((item) => MockPlanStop.fromJson(item as Map<String, dynamic>))
        .toList();

    if (parsedStops.length < 2 || parsedStops.length > 4) {
      throw const FormatException('Guide plan must contain 2 to 4 stops');
    }

    return MockPlanModel(
      title: title,
      summary: summary,
      estimatedDuration: estimatedDuration.isEmpty ? null : estimatedDuration,
      estimatedBudget: estimatedBudget.isEmpty ? null : estimatedBudget,
      stops: parsedStops,
    );
  }
}
