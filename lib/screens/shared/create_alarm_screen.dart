import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../providers/app_state_provider.dart';
import '../../services/places_service.dart';
import '../../services/voice_alarm_service.dart';
import '../../widgets/map/map_wrapper.dart';

Future<void> showCreateAlarmBottomSheet(
  BuildContext context, {
  VoiceAlarmDraft? initialDraft,
}) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (sheetContext) {
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.9;

      return _InteractiveBottomSheetContainer(
        height: maxHeight,
        onDismiss: () => Navigator.of(sheetContext).pop(),
        child: CreateAlarmScreen(initialDraft: initialDraft),
      );
    },
  );
}

class CreateAlarmScreen extends StatefulWidget {
  const CreateAlarmScreen({super.key, this.initialDraft});

  final VoiceAlarmDraft? initialDraft;

  @override
  State<CreateAlarmScreen> createState() => _CreateAlarmScreenState();
}

class _CreateAlarmScreenState extends State<CreateAlarmScreen> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _placesService = PlacesService();

  LatLng? _selectedLocation;
  double _radius = 500;
  GoogleMapController? _mapController;
  LatLng _initialCenter = const LatLng(51.5074, -0.1278); // London default
  bool _loadingLocation = true;
  bool _canShowMyLocation = false;
  bool _submitted = false;
  bool _isLoadingSuggestions = false;
  bool _isApplyingSuggestion = false;
  bool _locationNeedsResolve = false;
  List<PlaceSuggestion> _locationSuggestions = const [];
  String? _autocompleteInfoMessage;
  Timer? _locationDebounce;
  late final String _placesSessionToken;

  @override
  void initState() {
    super.initState();
    _placesSessionToken = const Uuid().v4();
    _nameController.addListener(_onFieldChanged);
    _locationController.addListener(_onLocationFieldChanged);

    final draft = widget.initialDraft;
    if (draft != null) {
      _nameController.text = draft.alarmName;
      _locationController.text = draft.location;
      _radius = draft.radiusMeters.clamp(100, 1000).toDouble();
      _locationNeedsResolve = draft.location.trim().isNotEmpty;
    }

    _loadCurrentLocation();

    if (draft != null && _locationNeedsResolve) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _resolveLocationFromInput();
      });
    }
  }

  void _onFieldChanged() {
    if (_submitted && mounted) {
      setState(() {});
    }
  }

  void _onLocationFieldChanged() {
    _onFieldChanged();
    if (!_isApplyingSuggestion) {
      _locationNeedsResolve = true;
    }
    _scheduleAutocomplete();
  }

  void _scheduleAutocomplete() {
    if (_isApplyingSuggestion) return;

    _locationDebounce?.cancel();
    final query = _locationController.text.trim();

    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoadingSuggestions = false;
        _locationSuggestions = const [];
        _autocompleteInfoMessage = null;
      });
      return;
    }

    setState(() => _isLoadingSuggestions = true);
    _locationDebounce = Timer(const Duration(milliseconds: 280), () {
      _fetchAutocomplete(query);
    });
  }

  Future<void> _fetchAutocomplete(String query) async {
    final result = await _placesService.autocompleteDetailed(
      query: query,
      sessionToken: _placesSessionToken,
    );

    if (!mounted) return;
    if (_locationController.text.trim() != query.trim()) return;

    setState(() {
      _isLoadingSuggestions = false;
      _locationSuggestions = result.suggestions;
      if (result.status == 'ZERO_RESULTS') {
        _autocompleteInfoMessage = 'No matching locations found.';
      } else if (result.status != 'OK') {
        final detail = (result.errorMessage ?? result.status).trim();
        _autocompleteInfoMessage = 'Places error: $detail';
      } else {
        _autocompleteInfoMessage = null;
      }
    });
  }

  Future<void> _applySuggestion(PlaceSuggestion suggestion) async {
    _isApplyingSuggestion = true;
    _locationController.text = suggestion.description;
    _locationController.selection = TextSelection.fromPosition(
      TextPosition(offset: _locationController.text.length),
    );
    _isApplyingSuggestion = false;

    setState(() {
      _isLoadingSuggestions = false;
      _locationSuggestions = const [];
      _autocompleteInfoMessage = null;
      _locationNeedsResolve = false;
    });

    final coordinates = await _placesService.getPlaceCoordinates(
      placeId: suggestion.placeId,
      sessionToken: _placesSessionToken,
    );
    if (!mounted || coordinates == null) return;

    final point = LatLng(coordinates.latitude, coordinates.longitude);
    setState(() {
      _selectedLocation = point;
      _initialCenter = point;
    });
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(point, 14));
  }

  Future<bool> _resolveLocationFromInput() async {
    final query = _locationController.text.trim();
    if (query.isEmpty) return false;

    PlaceSuggestion? suggestion;
    for (final item in _locationSuggestions) {
      if (item.description.toLowerCase() == query.toLowerCase()) {
        suggestion = item;
        break;
      }
    }

    if (suggestion == null) {
      final result = await _placesService.autocompleteDetailed(
        query: query,
        sessionToken: _placesSessionToken,
      );
      if (!mounted) return false;

      if (result.suggestions.isEmpty) {
        setState(() {
          final detail = (result.errorMessage ?? result.status).trim();
          _autocompleteInfoMessage =
              result.status == 'ZERO_RESULTS' ? 'No matching locations found.' : 'Places error: $detail';
        });
        return false;
      }

      suggestion = result.suggestions.first;
    }

    final coordinates = await _placesService.getPlaceCoordinates(
      placeId: suggestion.placeId,
      sessionToken: _placesSessionToken,
    );
    if (!mounted || coordinates == null) return false;

    final point = LatLng(coordinates.latitude, coordinates.longitude);
    _isApplyingSuggestion = true;
    _locationController.text = suggestion.description;
    _locationController.selection = TextSelection.fromPosition(
      TextPosition(offset: _locationController.text.length),
    );
    _isApplyingSuggestion = false;

    setState(() {
      _selectedLocation = point;
      _initialCenter = point;
      _isLoadingSuggestions = false;
      _locationSuggestions = const [];
      _autocompleteInfoMessage = null;
      _locationNeedsResolve = false;
    });
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(point, 14));
    return true;
  }

  Future<void> _loadCurrentLocation() async {
    // Reuse the provider's LocationService singleton — avoids duplicate
    // permission checks and a second location fetch.
    final appState = context.read<AppStateProvider>();
    final position = appState.currentPosition;
    if (position != null && mounted) {
      setState(() {
        _initialCenter = LatLng(position.latitude, position.longitude);
        _canShowMyLocation = true;
        _loadingLocation = false;
      });
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_initialCenter, 14),
      );
    } else {
      // Fall back to fetching via the shared service
      final fetched = await appState.locationService.getCurrentPosition();
      if (fetched != null && mounted) {
        setState(() {
          _initialCenter = LatLng(fetched.latitude, fetched.longitude);
          _canShowMyLocation = true;
          _loadingLocation = false;
        });
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(_initialCenter, 14),
        );
      } else if (mounted) {
        setState(() => _loadingLocation = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_onFieldChanged);
    _locationController.removeListener(_onLocationFieldChanged);
    _locationDebounce?.cancel();
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  bool _shouldShowEmptyError(TextEditingController controller) {
    return _submitted && controller.text.trim().isEmpty;
  }

  void _onMapTap(LatLng position) {
    setState(() {
      _selectedLocation = position;
      _locationSuggestions = const [];
      _autocompleteInfoMessage = null;
      _locationNeedsResolve = false;
    });
  }

  Set<Marker> _buildMarkers() {
    if (_selectedLocation == null) return {};
    return {
      Marker(
        markerId: const MarkerId('selected'),
        position: _selectedLocation!,
        infoWindow: const InfoWindow(title: 'Alarm Location'),
      ),
    };
  }

  Set<Circle> _buildCircles() {
    if (_selectedLocation == null) return {};
    return {
      Circle(
        circleId: const CircleId('radius'),
        center: _selectedLocation!,
        radius: _radius,
        fillColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
        strokeColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
        strokeWidth: 2,
      ),
    };
  }

  Future<void> _saveAlarm() async {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    final appState = context.read<AppStateProvider>();

    if (_selectedLocation == null || _locationNeedsResolve) {
      final resolved = await _resolveLocationFromInput();
      if (!resolved) {
        if (!mounted) return;
        showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Invalid Location'),
            content: const Text(
              'Could not place that address on the map. Pick a suggestion or adjust the text.',
            ),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
    }

    if (!mounted) return;

    if (_selectedLocation == null) {
      showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Location Required'),
          content: const Text('Please enter a valid location.'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    await appState.createAlarm(
          name: _nameController.text.trim(),
          locationLabel: _locationController.text.trim(),
          latitude: _selectedLocation!.latitude,
          longitude: _selectedLocation!.longitude,
          radiusMeters: _radius,
        );

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const topControlsOffset = 14.0;
    const controlsClearance = topControlsOffset + 48;

    return Scaffold(
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey3,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                SizedBox(height: controlsClearance),

                // Name field
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: TextFormField(
                    controller: _nameController,
                    autovalidateMode: _submitted
                        ? AutovalidateMode.always
                        : AutovalidateMode.disabled,
                    decoration: InputDecoration(
                      labelText: 'Alarm Name',
                      floatingLabelBehavior: _shouldShowEmptyError(_nameController)
                          ? FloatingLabelBehavior.always
                          : FloatingLabelBehavior.auto,
                      filled: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.only(top: 6, bottom: 10),
                      labelStyle: theme.textTheme.titleMedium?.copyWith(
                        color: _shouldShowEmptyError(_nameController)
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.22),
                          width: 1,
                        ),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary.withValues(alpha: 0.9),
                          width: 2,
                        ),
                      ),
                      errorBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: theme.colorScheme.error,
                          width: 2,
                        ),
                      ),
                      focusedErrorBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: theme.colorScheme.error,
                          width: 2,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a name';
                      }
                      return null;
                    },
                  ),
                ),

                // Location / address field
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _locationController,
                        autovalidateMode: _submitted
                            ? AutovalidateMode.always
                            : AutovalidateMode.disabled,
                        decoration: InputDecoration(
                          labelText: 'Location',
                          floatingLabelBehavior:
                              _shouldShowEmptyError(_locationController)
                                  ? FloatingLabelBehavior.always
                                  : FloatingLabelBehavior.auto,
                          filled: false,
                          isDense: true,
                          contentPadding: const EdgeInsets.only(top: 6, bottom: 10),
                          labelStyle: theme.textTheme.titleMedium?.copyWith(
                            color: _shouldShowEmptyError(_locationController)
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.22),
                              width: 1,
                            ),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: theme.colorScheme.primary.withValues(alpha: 0.9),
                              width: 2,
                            ),
                          ),
                          errorBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: theme.colorScheme.error,
                              width: 2,
                            ),
                          ),
                          focusedErrorBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: theme.colorScheme.error,
                              width: 2,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a location';
                          }
                          return null;
                        },
                      ),
                      if (_isLoadingSuggestions ||
                          _locationSuggestions.isNotEmpty ||
                          _autocompleteInfoMessage != null)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: CupertinoColors.secondarySystemGroupedBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outline.withValues(alpha: 0.16),
                            ),
                          ),
                          constraints: const BoxConstraints(maxHeight: 190),
                          child: _isLoadingSuggestions
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                      SizedBox(width: 10),
                                      Text('Searching locations...'),
                                    ],
                                  ),
                                )
                              : _locationSuggestions.isNotEmpty
                                  ? ListView.separated(
                                      shrinkWrap: true,
                                      padding: EdgeInsets.zero,
                                      itemCount: _locationSuggestions.length,
                                      separatorBuilder: (context, index) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final suggestion = _locationSuggestions[index];
                                        return ListTile(
                                          dense: true,
                                          title: Text(
                                            suggestion.description,
                                            style: theme.textTheme.bodyMedium,
                                          ),
                                          onTap: () => _applySuggestion(suggestion),
                                        );
                                      },
                                    )
                                  : Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(
                                        _autocompleteInfoMessage ??
                                            'No matching locations found.',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.75),
                                        ),
                                      ),
                                    ),
                        ),
                    ],
                  ),
                ),

                // Map
                Expanded(
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _initialCenter,
                          zoom: 14,
                        ),
                        onMapCreated: (controller) => _mapController = controller,
                        onTap: _onMapTap,
                        markers: _buildMarkers(),
                        circles: _buildCircles(),
                        myLocationEnabled: _canShowMyLocation,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                        compassEnabled: false,
                      ),
                      if (_loadingLocation)
                        Positioned.fill(
                          child: Container(
                            color: theme.colorScheme.surface.withValues(alpha: 0.7),
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 12),
                                  Text('Getting your location...'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (_selectedLocation != null)
                        Positioned(
                          top: 12,
                          left: 12,
                          right: 12,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Text(
                                '📍 ${_selectedLocation!.latitude.toStringAsFixed(4)}, ${_selectedLocation!.longitude.toStringAsFixed(4)}',
                                style: theme.textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Radius slider
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Alert Radius',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_radius.round()} m',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          activeTrackColor:
                              theme.colorScheme.primary.withValues(alpha: 0.95),
                          inactiveTrackColor:
                              theme.colorScheme.onSurface.withValues(alpha: 0.22),
                          thumbColor: theme.colorScheme.primary,
                          overlayColor:
                              theme.colorScheme.primary.withValues(alpha: 0.14),
                        ),
                        child: Slider(
                          value: _radius,
                          min: 100,
                          max: 1000,
                          label: '${_radius.round()} m',
                          onChanged: (val) {
                            final snapped =
                                ((val / 50).round() * 50).clamp(100, 1000);
                            setState(() => _radius = snapped.toDouble());
                          },
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '100 m',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          Text(
                            '1000 m',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: topControlsOffset,
            left: 12,
            child: MapWrapper.circularControl(
              context: context,
              onPressed: () => Navigator.of(context).pop(),
              icon: CupertinoIcons.back,
              tooltip: 'Back',
            ),
          ),
          Positioned(
            top: topControlsOffset,
            right: 12,
            child: MapWrapper.circularControl(
              context: context,
              onPressed: _saveAlarm,
              icon: CupertinoIcons.check_mark,
              tooltip: 'Save',
            ),
          ),
        ],
      ),
    );
  }
}

class _InteractiveBottomSheetContainer extends StatefulWidget {
  const _InteractiveBottomSheetContainer({
    required this.height,
    required this.child,
    required this.onDismiss,
  });

  final double height;
  final Widget child;
  final VoidCallback onDismiss;

  @override
  State<_InteractiveBottomSheetContainer> createState() =>
      _InteractiveBottomSheetContainerState();
}

class _InteractiveBottomSheetContainerState
    extends State<_InteractiveBottomSheetContainer> {
  double _sheetOffset = 0;
  bool _isDragging = false;

  static const double _dismissDistance = 120;
  static const double _dismissVelocity = 900;

  void _onDragUpdate(DragUpdateDetails details) {
    final nextOffset =
        (_sheetOffset + details.delta.dy).clamp(0, double.infinity).toDouble();
    setState(() {
      _isDragging = true;
      _sheetOffset = nextOffset;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldDismiss = _sheetOffset > _dismissDistance ||
        velocity > _dismissVelocity;

    if (shouldDismiss) {
      widget.onDismiss();
      return;
    }

    setState(() {
      _isDragging = false;
      _sheetOffset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        bottom: false,
        child: AnimatedContainer(
          duration: _isDragging
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, _sheetOffset, 0),
          child: Stack(
            children: [
              Container(
                height: widget.height,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: widget.child,
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: _onDragUpdate,
                    onVerticalDragEnd: _onDragEnd,
                    child: const SizedBox(width: 180, height: 56),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
