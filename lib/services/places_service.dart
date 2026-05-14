import 'dart:convert';

import 'package:http/http.dart' as http;

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
  static const String _placesHost = 'nominatim.openstreetmap.org';

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

    final uri = Uri.https(_placesHost, '/search', {
      'q': trimmed,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '6',
      'accept-language': 'es',
    });

    final response = await _client.get(
      uri,
      headers: {
        'User-Agent': 'WakeMap/1.0 (OpenStreetMap flutter_map client)',
      },
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

    final rawSuggestions = jsonDecode(response.body) as List<dynamic>? ?? const [];
    if (rawSuggestions.isEmpty) {
      return const PlacesAutocompleteResult(
        suggestions: [],
        status: 'ZERO_RESULTS',
      );
    }

    final suggestions = rawSuggestions
        .map((item) => item as Map<String, dynamic>)
        .map(
          (map) => PlaceSuggestion(
            placeId: '${map['lat'] ?? ''},${map['lon'] ?? ''}',
            description:
                map['display_name'] as String? ?? map['name'] as String? ?? '',
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

    final parts = placeId.split(',');
    if (parts.length != 2) return null;

    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    if (lat == null || lng == null) return null;

    return PlaceCoordinates(latitude: lat, longitude: lng);
  }
}
