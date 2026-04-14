import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state_provider.dart';
import '../../services/location_service.dart';
import '../../app/routes.dart';
import '../../widgets/map/map_wrapper.dart';

class TravellerMapScreen extends StatefulWidget {
  const TravellerMapScreen({super.key});

  @override
  State<TravellerMapScreen> createState() => _TravellerMapScreenState();
}

class _TravellerMapScreenState extends State<TravellerMapScreen> {
  static const String _tag = '[TravellerMap]';
  static const String _mapTag = '[Map]';

  /// Fallback used ONLY when location is unavailable (permission denied,
  /// services disabled, or error). London city center.
  static const LatLng _fallbackLocation = LatLng(51.5074, -0.1278);

  GoogleMapController? _mapController;
  StreamSubscription? _mapFollowSub;
  late final AppStateProvider _appState;

  /// Resolved once for startup. Map is built only after this is non-null.
  LatLng? _initialMapTarget;

  /// True while waiting for the first map camera target.
  bool _isLoadingInitialPosition = true;

  /// True when startup camera had to use fallback (permission/services/error).
  bool _usedFallbackInitialPosition = false;

  /// Auto-follow is enabled by default and is disabled after manual map gestures.
  bool _isAutoFollowEnabled = true;

  /// Distinguishes app-driven camera moves from user gestures.
  bool _isProgrammaticCameraMove = false;

  /// True when map controller has been created.
  bool _isMapControllerReady = false;

  /// Last location we used to re-center the camera.
  LatLng? _lastFollowedTarget;

  /// Latest device location received from map follow stream.
  LatLng? _latestDeviceLocation;

  @override
  void initState() {
    super.initState();
    _appState = context.read<AppStateProvider>();
    _resolveInitialMapTarget();
  }

  @override
  void dispose() {
    _mapFollowSub?.cancel();
    super.dispose();
  }

  /// One-time startup target resolution for map camera, independent of tracking.
  Future<void> _resolveInitialMapTarget() async {
    debugPrint('$_mapTag Loading initial position for traveller map');

    final cached = _appState.currentPosition;
    if (cached != null) {
      _setInitialTarget(
        LatLng(cached.latitude, cached.longitude),
        usedFallback: false,
      );
      return;
    }

    try {
      final permission = await _appState.locationService
          .checkAndRequestPermission();

      if (permission == LocationPermissionStatus.granted) {
        final position = await _appState.locationService.getPositionUnchecked();
        if (position != null) {
          _setInitialTarget(
            LatLng(position.latitude, position.longitude),
            usedFallback: false,
          );
          return;
        }

        debugPrint('$_mapTag Using fallback due to location fetch failure');
      } else {
        debugPrint('$_mapTag Using fallback due to $permission');
      }
    } catch (e) {
      debugPrint('$_tag Error resolving initial map target: $e');
      debugPrint('$_mapTag Using fallback due to location error');
    }

    _setInitialTarget(_fallbackLocation, usedFallback: true);
  }

  void _setInitialTarget(LatLng target, {required bool usedFallback}) {
    if (!mounted) return;
    debugPrint(
      '$_mapTag Initial map position resolved: ${target.latitude}, ${target.longitude}',
    );
    setState(() {
      _initialMapTarget = target;
      _usedFallbackInitialPosition = usedFallback;
      _isLoadingInitialPosition = false;
    });

    _lastFollowedTarget = target;

    if (!usedFallback) {
      _startMapFollowStream();
      debugPrint('$_mapTag Auto-follow enabled for traveller map');
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _isMapControllerReady = true;
    debugPrint('$_mapTag Building map with initial device-centered camera');

    final current = _latestDeviceLocation;
    if (current != null && _isAutoFollowEnabled) {
      _recenterCamera(current);
    }
  }

  void _startMapFollowStream() {
    if (_mapFollowSub != null) return;

    _mapFollowSub = _appState.locationService.getMapFollowStream().listen(
      (position) {
        _handleLocationUpdate(LatLng(position.latitude, position.longitude));
      },
      onError: (error) {
        debugPrint('$_tag Map follow stream error: $error');
      },
    );
  }

  void _handleLocationUpdate(LatLng nextLocation) {
    _latestDeviceLocation = nextLocation;
    debugPrint(
      '$_mapTag Device location updated: ${nextLocation.latitude}, ${nextLocation.longitude}',
    );

    final previous = _lastFollowedTarget;
    if (previous != null) {
      final movedDistance = _appState.locationService.distanceBetween(
        previous.latitude,
        previous.longitude,
        nextLocation.latitude,
        nextLocation.longitude,
      );
      if (movedDistance < 12) {
        return;
      }
    }

    if (_isAutoFollowEnabled) {
      _recenterCamera(nextLocation);
    }
  }

  Future<void> _recenterCamera(LatLng target) async {
    _lastFollowedTarget = target;

    if (!_isMapControllerReady || _mapController == null) {
      return;
    }

    _isProgrammaticCameraMove = true;
    try {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(target, 14),
      );
      debugPrint('$_mapTag Auto-follow recentered camera');
    } catch (e) {
      debugPrint('$_tag Failed to recenter camera: $e');
    } finally {
      _isProgrammaticCameraMove = false;
    }
  }

  void _onCameraMoveStarted() {
    if (_isProgrammaticCameraMove || !_isAutoFollowEnabled) return;

    setState(() {
      _isAutoFollowEnabled = false;
    });
    debugPrint('$_mapTag User manually moved map, auto-follow disabled');
  }

  void _onRecenterPressed() {
    debugPrint('$_mapTag Recenter requested manually');
    setState(() {
      _isAutoFollowEnabled = true;
    });

    final target = _latestDeviceLocation ?? _initialMapTarget;
    if (target != null) {
      _recenterCamera(target);
    }
  }

  Set<Marker> _buildMarkers(AppStateProvider appState) {
    final markers = <Marker>{};

    // Alarm markers
    for (final alarm in appState.alarms) {
      if (!alarm.isActive) continue;
      markers.add(
        Marker(
          markerId: MarkerId('alarm_${alarm.id}'),
          position: LatLng(alarm.latitude, alarm.longitude),
          infoWindow: InfoWindow(
            title: alarm.name,
            snippet: '${alarm.radiusMeters.round()} m radius',
          ),
          icon: MapWrapper.markerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
    }

    // Mock plan stop markers
    final plan = appState.currentPlan;
    if (plan != null) {
      for (int i = 0; i < plan.stops.length; i++) {
        final stop = plan.stops[i];
        markers.add(
          Marker(
            markerId: MarkerId('stop_$i'),
            position: LatLng(stop.latitude, stop.longitude),
            infoWindow: InfoWindow(
              title: '${i + 1}. ${stop.name}',
              snippet: stop.description,
            ),
            icon: MapWrapper.markerWithHue(BitmapDescriptor.hueOrange),
          ),
        );
      }
    }

    return markers;
  }

  Set<Circle> _buildCircles(AppStateProvider appState) {
    final circles = <Circle>{};
    final theme = Theme.of(context);
    for (final alarm in appState.alarms) {
      if (!alarm.isActive) continue;
      circles.add(
        Circle(
          circleId: CircleId(alarm.id),
          center: LatLng(alarm.latitude, alarm.longitude),
          radius: alarm.radiusMeters,
          fillColor: theme.colorScheme.primary.withValues(alpha: 0.1),
          strokeColor: theme.colorScheme.primary.withValues(alpha: 0.4),
          strokeWidth: 1,
        ),
      );
    }
    return circles;
  }

  Set<Polyline> _buildPolylines(AppStateProvider appState) {
    final plan = appState.currentPlan;
    if (plan == null || plan.stops.length < 2) return {};

    final points = plan.stops
        .map((s) => LatLng(s.latitude, s.longitude))
        .toList();

    return {
      Polyline(
        polylineId: const PolylineId('plan_route'),
        points: points,
        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.7),
        width: 3,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoadingInitialPosition) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Consumer<AppStateProvider>(
      builder: (context, appState, _) {
        final initialTarget = _initialMapTarget ?? _fallbackLocation;

        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: MapWrapper.withLayoutDiagnostics(
                  tag: 'traveller_main_map',
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: initialTarget,
                      zoom: 14,
                    ),
                    onMapCreated: _onMapCreated,
                    onCameraMoveStarted: _onCameraMoveStarted,
                    markers: _buildMarkers(appState),
                    circles: _buildCircles(appState),
                    polylines: _buildPolylines(appState),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    zoomControlsEnabled: false,
                  ),
                ),
              ),

              if (_usedFallbackInitialPosition)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 60,
                  left: 12,
                  right: 12,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        'Location unavailable. Showing fallback area.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ),

              // Top-left settings button
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                child: MapWrapper.overlay(
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.surface,
                    child: IconButton(
                      icon: Icon(
                        Icons.settings_outlined,
                        color: theme.colorScheme.onSurface,
                      ),
                      onPressed: () =>
                          Navigator.of(context).pushNamed(AppRoutes.settings),
                      tooltip: 'Settings',
                    ),
                  ),
                ),
              ),

              // Plan badge (if plan exists)
              if (appState.currentPlan != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  right: 12,
                  child: MapWrapper.overlay(
                    Card(
                      color: theme.colorScheme.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 16,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${appState.currentPlan!.stops.length} stops',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Mic button (inactive placeholder)
              Positioned(
                bottom: 24,
                right: 16,
                child: MapWrapper.overlay(
                  FloatingActionButton(
                    heroTag: 'mic_traveller',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Voice input coming soon!'),
                        ),
                      );
                    },
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    child: Icon(
                      Icons.mic,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),

              if (!_isAutoFollowEnabled)
                Positioned(
                  bottom: 96,
                  right: 16,
                  child: MapWrapper.overlay(
                    FloatingActionButton.small(
                      heroTag: 'recenter_traveller',
                      onPressed: _onRecenterPressed,
                      tooltip: 'Recenter',
                      child: const Icon(Icons.my_location),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
