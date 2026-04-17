import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.description,
  });

  final String placeId;
  final String description;
}

class PlaceCoordinates {
  const PlaceCoordinates({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

class PlacesAutocompleteResult {
  const PlacesAutocompleteResult({
    required this.suggestions,
    required this.status,
    this.errorMessage,
  });

  final List<PlaceSuggestion> suggestions;
  final String status;
  final String? errorMessage;
}

class PlacesService {
  PlacesService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _placesHost = 'places.googleapis.com';

  Future<List<PlaceSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
  }) async {
    final result = await autocompleteDetailed(
      query: query,
      sessionToken: sessionToken,
    );
    return result.suggestions;
  }

  Future<PlacesAutocompleteResult> autocompleteDetailed({
    required String query,
    required String sessionToken,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const PlacesAutocompleteResult(
        suggestions: [],
        status: 'EMPTY_QUERY',
      );
    }

    final uri = Uri.https(_placesHost, '/v1/places:autocomplete');

    final response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': AppConfig.googleMapsApiKey,
        'X-Goog-FieldMask':
            'suggestions.placePrediction.placeId,suggestions.placePrediction.text.text',
      },
      body: jsonEncode({
        'input': trimmed,
        'sessionToken': sessionToken,
        'languageCode': 'es',
      }),
    );

    if (response.statusCode != 200) {
      String? errorMessage;
      String status = 'HTTP_${response.statusCode}';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final error = body['error'] as Map<String, dynamic>?;
        status = error?['status'] as String? ?? status;
        errorMessage = error?['message'] as String?;
      } catch (_) {
        // Keep fallback status/message when body is not JSON.
      }

      return PlacesAutocompleteResult(
        suggestions: const [],
        status: status,
        errorMessage:
            errorMessage ?? 'Autocomplete request failed (${response.statusCode}).',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final rawSuggestions = body['suggestions'] as List<dynamic>? ?? const [];
    if (rawSuggestions.isEmpty) {
      return const PlacesAutocompleteResult(
        suggestions: [],
        status: 'ZERO_RESULTS',
      );
    }

    final suggestions = rawSuggestions
        .map((item) => item as Map<String, dynamic>)
        .map((entry) => entry['placePrediction'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .map(
          (map) => PlaceSuggestion(
            placeId: map['placeId'] as String? ?? '',
            description:
                (map['text'] as Map<String, dynamic>?)?['text'] as String? ?? '',
          ),
        )
        .where((s) => s.placeId.isNotEmpty && s.description.isNotEmpty)
        .toList(growable: false);

    return PlacesAutocompleteResult(
      suggestions: suggestions,
      status: suggestions.isEmpty ? 'ZERO_RESULTS' : 'OK',
    );
  }

  Future<PlaceCoordinates?> getPlaceCoordinates({
    required String placeId,
    required String sessionToken,
  }) async {
    if (placeId.isEmpty) return null;

    final uri = Uri.https(_placesHost, '/v1/places/$placeId');

    final response = await _client.get(
      uri,
      headers: {
        'X-Goog-Api-Key': AppConfig.googleMapsApiKey,
        'X-Goog-FieldMask': 'location',
      },
    );

    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final location = body['location'] as Map<String, dynamic>?;
    final lat = ((location?['latitude'] ?? location?['lat']) as num?)?.toDouble();
    final lng = ((location?['longitude'] ?? location?['lng']) as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    return PlaceCoordinates(latitude: lat, longitude: lng);
  }
}
