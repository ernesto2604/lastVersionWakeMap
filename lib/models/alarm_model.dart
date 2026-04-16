import 'dart:convert';

class AlarmModel {
  final String id;
  String name;
  String locationLabel;
  double latitude;
  double longitude;
  double radiusMeters;
  bool isActive;
  final DateTime createdAt;
  bool hasTriggered;

  AlarmModel({
    required this.id,
    required this.name,
    this.locationLabel = '',
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 500,
    this.isActive = true,
    required this.createdAt,
    this.hasTriggered = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'locationLabel': locationLabel,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        'hasTriggered': hasTriggered,
      };

  factory AlarmModel.fromJson(Map<String, dynamic> json) => AlarmModel(
        id: json['id'] as String,
        name: json['name'] as String,
        locationLabel: json['locationLabel'] as String? ?? '',
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        radiusMeters: (json['radiusMeters'] as num).toDouble(),
        isActive: json['isActive'] as bool,
        createdAt: DateTime.parse(json['createdAt'] as String),
        hasTriggered: json['hasTriggered'] as bool? ?? false,
      );

  String encode() => jsonEncode(toJson());

  factory AlarmModel.decode(String source) =>
      AlarmModel.fromJson(jsonDecode(source) as Map<String, dynamic>);

  AlarmModel copyWith({
    String? name,
    String? locationLabel,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    bool? isActive,
    bool? hasTriggered,
  }) {
    return AlarmModel(
      id: id,
      name: name ?? this.name,
      locationLabel: locationLabel ?? this.locationLabel,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      hasTriggered: hasTriggered ?? this.hasTriggered,
    );
  }
}
