import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state_provider.dart';
import '../../services/location_service.dart';
import '../../services/route_service.dart';
import '../../widgets/map/map_wrapper.dart';
import '../shared/settings_screen.dart';

class CommuterMapScreen extends StatefulWidget {
  const CommuterMapScreen({super.key});

  @override
  State<CommuterMapScreen> createState() => _CommuterMapScreenState();
}

class _CommuterMapScreenState extends State<CommuterMapScreen> {
  static const String _tag = '[CommuterMap]';
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

  /// Enables GoogleMap location layer only after permission is confirmed.
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
      debugPrint('$_tag Alarm activated, fitting bounds and fetching route');
      setState(() => _isAutoFollowEnabled = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitBoundsToActiveAlarms();
        _fetchAlarmRoute();
      });
    } else if (activeCount == 0 && _previousActiveAlarmCount > 0) {
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
    if (!_isMapControllerReady || _mapController == null) return;

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
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _isProgrammaticCameraMove = true;
    try {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 80),
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
    debugPrint('$_mapTag Loading initial position for commuter map');

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
      debugPrint('$_mapTag Auto-follow enabled for commuter map');
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
    for (final alarm in appState.alarms) {
      if (!alarm.isActive) continue;
      markers.add(
        Marker(
          markerId: MarkerId(alarm.id),
          position: LatLng(alarm.latitude, alarm.longitude),
          infoWindow: InfoWindow(
            title: alarm.name,
            snippet: '${alarm.radiusMeters.round()} m radius',
          ),
          icon: MapWrapper.markerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
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

  Set<Polyline> _buildPolylines() {
    final polylines = <Polyline>{};

    if (_alarmRoute != null && _alarmRoute!.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('alarm_route'),
          points: _alarmRoute!,
          color: Theme.of(context).colorScheme.primary,
          width: 6,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
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
                  tag: 'commuter_main_map',
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: initialTarget,
                      zoom: 14,
                    ),
                    onMapCreated: _onMapCreated,
                    onCameraMoveStarted: _onCameraMoveStarted,
                    markers: _buildMarkers(appState),
                    circles: _buildCircles(appState),
                    polylines: _buildPolylines(),
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
