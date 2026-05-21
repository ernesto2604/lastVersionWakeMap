import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state_provider.dart';
import '../../services/location_service.dart';
import '../../services/route_service.dart';
import '../../widgets/map/map_wrapper.dart';
import '../shared/settings_screen.dart';
import '../../config/map_tile_config.dart';

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

  final MapController _mapController = MapController();
  StreamSubscription? _mapFollowSub;
  late final AppStateProvider _appState;

  /// Resolved once for startup. Map is built only after this is non-null.
  LatLng? _initialMapTarget;

  /// True while waiting for the first map camera target.
  bool _isLoadingInitialPosition = true;

  /// True when startup camera had to use fallback (permission/services/error).
  bool _usedFallbackInitialPosition = false;

  /// Enables the current-location marker only after permission is confirmed.
  bool _canShowMyLocation = false;

  /// Auto-follow is disabled by default; enabled only when alarms are active.
  bool _isAutoFollowEnabled = false;

  /// Distinguishes app-driven camera moves from user gestures.
  bool _isProgrammaticCameraMove = false;

  /// Tracks previous active alarm count to detect activation/deactivation.
  int _previousActiveAlarmCount = 0;

  /// The polyline route to the active alarm(s).
  List<LatLng>? _alarmRoute;
  final RouteService _routeService = RouteService();

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
    _appState.addListener(_onAppStateChanged);
    _previousActiveAlarmCount = _appState.alarms.where((a) => a.isActive).length;
    _resolveInitialMapTarget();
  }

  @override
  void dispose() {
    _appState.removeListener(_onAppStateChanged);
    _mapFollowSub?.cancel();
    super.dispose();
  }

  /// React to alarm activation/deactivation transitions.
  void _onAppStateChanged() {
    final activeCount = _appState.alarms.where((a) => a.isActive).length;

    if (activeCount > 0 && _previousActiveAlarmCount == 0) {
      // Alarm(s) just activated → fit bounds to show device + alarm destinations
      debugPrint('$_tag Alarm activated, fitting bounds and fetching route');
      setState(() => _isAutoFollowEnabled = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitBoundsToActiveAlarms();
        _fetchAlarmRoute();
      });
    } else if (activeCount == 0 && _previousActiveAlarmCount > 0) {
      // All alarms deactivated → recenter on device, allow free movement
      debugPrint('$_tag All alarms deactivated, recentering on device');
      setState(() {
        _isAutoFollowEnabled = false;
        _alarmRoute = null;
      });
      final target = _latestDeviceLocation ?? _initialMapTarget;
      if (target != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _recenterCamera(target);
        });
      }
    }

    _previousActiveAlarmCount = activeCount;
  }

  Future<void> _fetchAlarmRoute() async {
    final activeAlarms = _appState.alarms.where((a) => a.isActive).toList();
    if (activeAlarms.isEmpty) return;

    final origin = _latestDeviceLocation ?? _initialMapTarget;
    if (origin == null) return;

    final destination = LatLng(activeAlarms.first.latitude, activeAlarms.first.longitude);

    try {
      final route = await _routeService.computeRoutePolyline(
        origin: origin,
        destination: destination,
      );
      if (mounted && route.isNotEmpty) {
        setState(() {
          _alarmRoute = route;
        });
      }
    } catch (e) {
      debugPrint('$_tag Failed to fetch alarm route: $e');
    }
  }

  /// Zoom to fit all active alarm positions + device location.
  Future<void> _fitBoundsToActiveAlarms() async {
    if (!_isMapControllerReady) return;

    final activeAlarms = _appState.alarms.where((a) => a.isActive).toList();
    if (activeAlarms.isEmpty) return;

    final points = <LatLng>[];
    final device = _latestDeviceLocation ?? _initialMapTarget;
    if (device != null) points.add(device);
    for (final alarm in activeAlarms) {
      points.add(LatLng(alarm.latitude, alarm.longitude));
    }
    if (points.length < 2) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    final bounds = LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );

    _isProgrammaticCameraMove = true;
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(80),
        ),
      );
      debugPrint('$_mapTag Fitted bounds to active alarms');
    } catch (e) {
      debugPrint('$_tag Failed to fit bounds: $e');
    } finally {
      _isProgrammaticCameraMove = false;
    }
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
      _canShowMyLocation = !usedFallback;
      _isLoadingInitialPosition = false;
    });

    _lastFollowedTarget = target;

    if (!usedFallback) {
      _startMapFollowStream();
      debugPrint('$_mapTag Auto-follow enabled for traveller map');
    }
  }

  void _onMapReady() {
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

    if (!_isMapControllerReady) {
      return;
    }

    _isProgrammaticCameraMove = true;
    try {
      _mapController.move(target, 14);
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

  List<Marker> _buildMarkers(AppStateProvider appState) {
    final markers = <Marker>[];
    final currentLocation = _latestDeviceLocation ?? _initialMapTarget;
    if (_canShowMyLocation && currentLocation != null) {
      markers.add(_currentLocationMarker(currentLocation));
    }

    // Alarm markers
    for (final alarm in appState.alarms) {
      if (!alarm.isActive) continue;
      markers.add(
        Marker(
          point: LatLng(alarm.latitude, alarm.longitude),
          width: 44,
          height: 44,
          child: Tooltip(
            message: '${alarm.name}\n${alarm.radiusMeters.round()} m radius',
            child: Icon(
              CupertinoIcons.location_solid,
              color: Theme.of(context).colorScheme.primary,
              size: 38,
            ),
          ),
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
            point: LatLng(stop.latitude, stop.longitude),
            width: 40,
            height: 40,
            child: Tooltip(
              message: '${i + 1}. ${stop.name}\n${stop.description}',
              child: Icon(
                CupertinoIcons.flag_fill,
                color: Theme.of(context).colorScheme.secondary,
                size: 34,
              ),
            ),
          ),
        );
      }
    }

    return markers;
  }

  Marker _currentLocationMarker(LatLng point) {
    final color = CupertinoTheme.of(context).primaryColor;
    return Marker(
      point: point,
      width: 26,
      height: 26,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ),
    );
  }

  List<CircleMarker> _buildCircles(AppStateProvider appState) {
    final circles = <CircleMarker>[];
    final theme = Theme.of(context);
    for (final alarm in appState.alarms) {
      if (!alarm.isActive) continue;
      circles.add(
        CircleMarker(
          point: LatLng(alarm.latitude, alarm.longitude),
          radius: alarm.radiusMeters,
          useRadiusInMeter: true,
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderColor: theme.colorScheme.primary.withValues(alpha: 0.4),
          borderStrokeWidth: 1,
        ),
      );
    }
    return circles;
  }

  List<Polyline> _buildPolylines(AppStateProvider appState) {
    final polylines = <Polyline>[];

    // 1. Draw alarm route if available
    if (_alarmRoute != null && _alarmRoute!.isNotEmpty) {
      polylines.add(
        Polyline(
          points: _alarmRoute!,
          color: Theme.of(context).colorScheme.primary,
          strokeWidth: 6,
        ),
      );
    }

    // 2. Draw plan route if active
    final plan = appState.currentPlan;
    if (plan != null && plan.stops.length >= 2) {
      final points = plan.stops
          .map((s) => LatLng(s.latitude, s.longitude))
          .toList();

      polylines.add(
        Polyline(
          points: points,
          color: Theme.of(context).colorScheme.secondary,
          strokeWidth: 6,
        ),
      );
    }

    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingInitialPosition) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Consumer<AppStateProvider>(
      builder: (context, appState, _) {
        final initialTarget = _initialMapTarget ?? _fallbackLocation;
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        final navBottomPadding = math.max(10.0, bottomInset * 0.55);
        final navOverlayHeight = 62.0 + navBottomPadding;
        final controlsBottomOffset = navOverlayHeight + 16;

        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: MapWrapper.withLayoutDiagnostics(
                  tag: 'traveller_main_map',
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: initialTarget,
                      initialZoom: 14,
                      onMapReady: _onMapReady,
                      onPositionChanged: (_, hasGesture) {
                        if (hasGesture) _onCameraMoveStarted();
                      },
                    ),
                    children: [
                      MapTileConfig.tileLayer(),
                      CircleLayer(circles: _buildCircles(appState)),
                      PolylineLayer(polylines: _buildPolylines(appState)),
                      MarkerLayer(markers: _buildMarkers(appState)),
                      MapTileConfig.attributionWidget(),
                    ],
                  ),
                ),
              ),

              if (_usedFallbackInitialPosition)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 60,
                  left: 12,
                  right: 12,
                  child: MapWrapper.overlay(
                    MapWrapper.frostedPill(
                      child: Row(
                        children: [
                          const Icon(
                            CupertinoIcons.location_slash,
                            size: 16,
                            color: CupertinoColors.systemOrange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Location unavailable. Showing fallback area.',
                              style: CupertinoTheme.of(context)
                                  .textTheme
                                  .tabLabelTextStyle
                                  .copyWith(
                                    color: CupertinoColors.label,
                                    fontSize: 13,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Top-left settings button
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                child: MapWrapper.circularControl(
                  context: context,
                  onPressed: () => showSettingsBottomSheet(context),
                  icon: CupertinoIcons.settings,
                  tooltip: 'Settings',
                ),
              ),

              // Plan badge (if plan exists)
              if (appState.currentPlan != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  right: 12,
                  child: MapWrapper.overlay(
                    MapWrapper.frostedPill(
                      backgroundColor: CupertinoColors.systemTeal.withValues(
                        alpha: 0.16,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            CupertinoIcons.sparkles,
                            size: 16,
                            color: CupertinoColors.systemTeal,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${appState.currentPlan!.stops.length} stops',
                            style: CupertinoTheme.of(context)
                                .textTheme
                                .tabLabelTextStyle
                                .copyWith(
                                  color: CupertinoColors.systemTeal,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              if (appState.currentPlan != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 52,
                  right: 12,
                  child: MapWrapper.overlay(
                    MapWrapper.frostedPill(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        'Route active',
                        style: CupertinoTheme.of(context)
                            .textTheme
                            .tabLabelTextStyle
                            .copyWith(
                              color: CupertinoColors.secondaryLabel,
                              fontSize: 12,
                            ),
                      ),
                    ),
                  ),
                ),

              if (!_isAutoFollowEnabled)
                Positioned(
                  bottom: controlsBottomOffset,
                  right: 16,
                  child: MapWrapper.circularControl(
                    context: context,
                    onPressed: _onRecenterPressed,
                    icon: CupertinoIcons.location_fill,
                    tooltip: 'Recenter',
                    size: 44,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
