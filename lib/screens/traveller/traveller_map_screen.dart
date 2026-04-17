import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/alarm_model.dart';
import '../../providers/app_state_provider.dart';
import '../../services/location_service.dart';
import '../../services/route_service.dart';
import '../../widgets/map/map_wrapper.dart';
import '../shared/settings_screen.dart';

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
  final RouteService _routeService = RouteService();

  /// Resolved once for startup. Map is built only after this is non-null.
  LatLng? _initialMapTarget;

  /// True while waiting for the first map camera target.
  bool _isLoadingInitialPosition = true;

  /// True when startup camera had to use fallback (permission/services/error).
  bool _usedFallbackInitialPosition = false;

  /// Enables GoogleMap location layer only after permission is confirmed.
  bool _canShowMyLocation = false;

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

  /// Decoded route points from device location to active alarm.
  List<LatLng> _alarmRoutePoints = const [];

  /// Active alarm id used by the current route.
  String? _routeAlarmId;

  /// Origin used by the current route.
  LatLng? _routeOrigin;

  /// Prevents concurrent route requests.
  bool _isFetchingRoute = false;

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
      _canShowMyLocation = !usedFallback;
      _isLoadingInitialPosition = false;
    });

    _lastFollowedTarget = target;
    _latestDeviceLocation = target;

    if (!usedFallback) {
      _startMapFollowStream();
      _syncAlarmRoute(_appState);
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

    if (_alarmRoutePoints.isNotEmpty) {
      _fitRouteToView(_alarmRoutePoints);
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

    _syncAlarmRoute(_appState);
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
    final allPolylines = <Polyline>{};

    if (_alarmRoutePoints.length >= 2) {
      allPolylines.add(
        Polyline(
          polylineId: const PolylineId('active_alarm_route'),
          points: _alarmRoutePoints,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
          width: 5,
        ),
      );
    }

    final plan = appState.currentPlan;
    if (plan == null || plan.stops.length < 2) return allPolylines;

    final points = plan.stops
        .map((s) => LatLng(s.latitude, s.longitude))
        .toList();

    allPolylines.add(
      Polyline(
        polylineId: const PolylineId('plan_route'),
        points: points,
        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.7),
        width: 3,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      ),
    );

    return allPolylines;
  }

  AlarmModel? _primaryActiveAlarm(AppStateProvider appState) {
    for (final alarm in appState.alarms) {
      if (alarm.isActive) return alarm;
    }
    return null;
  }

  void _syncAlarmRoute(AppStateProvider appState) {
    final alarm = _primaryActiveAlarm(appState);
    if (alarm == null) {
      if (_alarmRoutePoints.isNotEmpty || _routeAlarmId != null) {
        setState(() {
          _alarmRoutePoints = const [];
          _routeAlarmId = null;
          _routeOrigin = null;
        });
      }

      final target = _latestDeviceLocation ?? _initialMapTarget;
      if (target != null && !_isAutoFollowEnabled) {
        _onRecenterPressed();
      }
      return;
    }

    final origin = _latestDeviceLocation ?? _initialMapTarget;
    if (origin == null) return;

    final alarmChanged = _routeAlarmId != alarm.id;
    final originChanged = _routeOrigin == null ||
        _appState.locationService.distanceBetween(
              _routeOrigin!.latitude,
              _routeOrigin!.longitude,
              origin.latitude,
              origin.longitude,
            ) >
            45;

    if (!alarmChanged && !originChanged) return;
    _updateRouteForActiveAlarm(origin: origin, alarm: alarm);
  }

  Future<void> _updateRouteForActiveAlarm({
    required LatLng origin,
    required AlarmModel alarm,
  }) async {
    if (_isFetchingRoute) return;
    _isFetchingRoute = true;

    final destination = LatLng(alarm.latitude, alarm.longitude);
    final points = await _routeService.computeRoutePolyline(
      origin: origin,
      destination: destination,
    );

    if (!mounted) {
      _isFetchingRoute = false;
      return;
    }

    setState(() {
      _alarmRoutePoints = points;
      _routeAlarmId = alarm.id;
      _routeOrigin = origin;
    });

    _isFetchingRoute = false;

    if (points.length >= 2) {
      _fitRouteToView(points);
    }
  }

  Future<void> _fitRouteToView(List<LatLng> points) async {
    if (!_isMapControllerReady || _mapController == null || points.isEmpty) {
      return;
    }

    if (points.length == 1) {
      _recenterCamera(points.first);
      return;
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points.skip(1)) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _isProgrammaticCameraMove = true;
    setState(() {
      _isAutoFollowEnabled = false;
    });

    try {
      await _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 72));
      debugPrint('$_mapTag Route fitted to viewport');
    } catch (_) {
      // Ignore fit failures when bounds are too tight on first frame.
    } finally {
      _isProgrammaticCameraMove = false;
    }
  }

  void _scheduleAlarmRouteSync(AppStateProvider appState) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncAlarmRoute(appState);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingInitialPosition) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Consumer<AppStateProvider>(
      builder: (context, appState, _) {
        _scheduleAlarmRouteSync(appState);

        final theme = Theme.of(context);
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
                    compassEnabled: false,
                    myLocationEnabled: _canShowMyLocation,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
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
                      backgroundColor: theme.colorScheme.onSurface.withValues(
                        alpha: 0.16,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.sparkles,
                            size: 16,
                            color: theme.colorScheme.onSurface,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${appState.currentPlan!.stops.length} stops',
                            style: CupertinoTheme.of(context)
                                .textTheme
                                .tabLabelTextStyle
                                .copyWith(
                                  color: theme.colorScheme.onSurface,
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
