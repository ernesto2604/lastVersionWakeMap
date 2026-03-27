import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Result of a permission check with actionable detail.
enum LocationPermissionStatus {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

class LocationService {
  static const String _tag = '[LocationService]';

  /// Check and request location permissions.
  /// Returns a detailed status enum instead of a plain bool.
  Future<LocationPermissionStatus> checkAndRequestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('$_tag Location services are DISABLED');
      return LocationPermissionStatus.serviceDisabled;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      debugPrint('$_tag Permission denied, requesting...');
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('$_tag Permission denied by user');
        return LocationPermissionStatus.denied;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      debugPrint('$_tag Permission denied forever');
      return LocationPermissionStatus.deniedForever;
    }

    debugPrint('$_tag Permission granted ($permission)');
    return LocationPermissionStatus.granted;
  }

  /// Convenience: returns true only if granted.
  Future<bool> ensurePermission() async {
    final status = await checkAndRequestPermission();
    return status == LocationPermissionStatus.granted;
  }

  /// Get current position once — uses HIGH accuracy for precise marker placement.
  /// Checks permission first. Use this from screens that may not have checked yet.
  Future<Position?> getCurrentPosition() async {
    final hasPermission = await ensurePermission();
    if (!hasPermission) return null;
    return _fetchPosition();
  }

  /// Get current position WITHOUT re-checking permission.
  /// Use this when the caller has already verified permission (e.g. the provider).
  Future<Position?> getPositionUnchecked() => _fetchPosition();

  Future<Position?> _fetchPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      debugPrint('$_tag Current position: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      debugPrint('$_tag Error getting current position: $e');
      return null;
    }
  }

  /// Stream of position updates for alarm monitoring.
  ///
  /// Uses MEDIUM accuracy (WiFi/cell) — sufficient for 100m+ alarm radii
  /// and significantly reduces battery drain vs GPS.
  /// Distance filter of 50m avoids excessive updates while keeping reliability.
  ///
  /// NOTE: This is foreground-only. The stream pauses when the app is
  /// fully backgrounded by the OS. True background geofencing would
  /// require a platform-specific solution (e.g. WorkManager + native geofence API).
  Stream<Position> getAlarmMonitoringStream() {
    debugPrint('$_tag Starting alarm monitoring stream (medium accuracy, 50m filter)');
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 50,
      ),
    );
  }

  /// Stream of position updates for map camera auto-follow.
  ///
  /// Uses HIGH accuracy with a 15m distance filter so the camera can follow
  /// meaningful movement without reacting to tiny GPS jitter.
  Stream<Position> getMapFollowStream() {
    debugPrint('$_tag Starting map follow stream (high accuracy, 15m filter)');
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    );
  }

  /// Calculate distance in meters between two coordinates.
  double distanceBetween(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }
}
