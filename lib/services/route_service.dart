import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteService {
  RouteService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<LatLng>> computeRoutePolyline({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final uri = Uri.https(
      'router.project-osrm.org',
      '/route/v1/driving/${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}',
      {
        'overview': 'full',
        'geometries': 'geojson',
      },
    );

    final response = await _client.get(
      uri,
      headers: {
        'User-Agent': 'WakeMap/1.0 (OpenStreetMap flutter_map client)',
      },
    );

    if (response.statusCode != 200) return const [];

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = body['routes'] as List<dynamic>? ?? const [];
    if (routes.isEmpty) return const [];

    final firstRoute = routes.first as Map<String, dynamic>;
    final geometry = firstRoute['geometry'] as Map<String, dynamic>?;
    final coordinates = geometry?['coordinates'] as List<dynamic>? ?? const [];

    return coordinates
        .whereType<List<dynamic>>()
        .map((coord) {
          final lng = (coord[0] as num).toDouble();
          final lat = (coord[1] as num).toDouble();
          return LatLng(lat, lng);
        })
        .toList(growable: false);
  }
}
