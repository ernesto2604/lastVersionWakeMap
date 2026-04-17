import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_liquid_glass_plus/flutter_liquid_glass.dart';
import 'package:flutter_liquid_glass_plus/buttons/liquid_glass_switch.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/alarm_model.dart';
import '../../providers/app_state_provider.dart';
import '../../services/places_service.dart';
import '../../widgets/map/map_wrapper.dart';

Future<void> showAlarmDetailBottomSheet(
  BuildContext context,
  AlarmModel alarm,
) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (sheetContext) {
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.9;

      return _InteractiveBottomSheetContainer(
        height: maxHeight,
        onDismiss: () => Navigator.of(sheetContext).pop(),
        child: AlarmDetailScreen(alarm: alarm),
      );
    },
  );
}

class AlarmDetailScreen extends StatefulWidget {
  final AlarmModel alarm;

  const AlarmDetailScreen({super.key, required this.alarm});

  @override
  State<AlarmDetailScreen> createState() => _AlarmDetailScreenState();
}

class _AlarmDetailScreenState extends State<AlarmDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _placesService = PlacesService();
  late TextEditingController _nameController;
  late TextEditingController _locationController;
  GoogleMapController? _mapController;
  late LatLng _selectedLocation;
  late double _radius;
  late bool _isActive;
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
    _nameController = TextEditingController(text: widget.alarm.name);
    _locationController = TextEditingController(text: widget.alarm.locationLabel);
    _locationController.addListener(_onLocationFieldChanged);
    _selectedLocation = LatLng(widget.alarm.latitude, widget.alarm.longitude);
    _radius = widget.alarm.radiusMeters;
    _isActive = widget.alarm.isActive;
  }

  @override
  void dispose() {
    _locationController.removeListener(_onLocationFieldChanged);
    _locationDebounce?.cancel();
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  bool _shouldShowEmptyError(TextEditingController controller) {
    return _submitted && controller.text.trim().isEmpty;
  }

  void _onLocationFieldChanged() {
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
    setState(() => _selectedLocation = point);
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(point, 15));
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
      _isLoadingSuggestions = false;
      _locationSuggestions = const [];
      _autocompleteInfoMessage = null;
      _locationNeedsResolve = false;
    });
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(point, 15));
    return true;
  }

  Future<void> _saveChanges() async {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    final appState = context.read<AppStateProvider>();

    if (_locationNeedsResolve) {
      final resolved = await _resolveLocationFromInput();
      if (!resolved) {
        if (!mounted) return;
        await showCupertinoDialog<void>(
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

    final updated = widget.alarm.copyWith(
      name: _nameController.text.trim(),
      locationLabel: _locationController.text.trim(),
      latitude: _selectedLocation.latitude,
      longitude: _selectedLocation.longitude,
      radiusMeters: _radius,
      isActive: _isActive,
    );
    await appState.updateAlarm(updated);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _deleteAlarm() async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Alarm'),
        content: Text('Delete "${widget.alarm.name}"?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      if (!mounted) return;
      final appState = context.read<AppStateProvider>();
      await appState.deleteAlarm(widget.alarm.id);
      if (mounted) Navigator.of(context).pop();
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

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _locationController,
                        autovalidateMode: _submitted
                            ? AutovalidateMode.always
                            : AutovalidateMode.disabled,
                        decoration: InputDecoration(
                          labelText: 'Location',
                          floatingLabelBehavior: _shouldShowEmptyError(_locationController)
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

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      Text(
                        'Active',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      LGSwitch(
                        value: _isActive,
                        onChanged: (value) => setState(() => _isActive = value),
                        width: 62,
                        height: 26,
                        activeColor: CupertinoColors.activeGreen,
                        inactiveColor: CupertinoColors.systemGrey4,
                        useOwnLayer: true,
                        quality: LGQuality.premium,
                        settings: const LiquidGlassSettings(
                          thickness: 28,
                          blur: 14,
                          chromaticAberration: 0.75,
                          lightIntensity: 0.9,
                          refractiveIndex: 1.2,
                          saturation: 1.05,
                          glassColor: Color(0x2CFFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _selectedLocation,
                      zoom: 15,
                    ),
                    onMapCreated: (controller) => _mapController = controller,
                    markers: {
                      Marker(markerId: const MarkerId('alarm'), position: _selectedLocation),
                    },
                    circles: {
                      Circle(
                        circleId: const CircleId('radius'),
                        center: _selectedLocation,
                        radius: _radius,
                        fillColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                        strokeColor: theme.colorScheme.primary.withValues(alpha: 0.5),
                        strokeWidth: 2,
                      ),
                    },
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    compassEnabled: false,
                    scrollGesturesEnabled: false,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    myLocationButtonEnabled: false,
                    liteModeEnabled: MapWrapper.liteModeEnabled,
                  ),
                ),

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
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: GestureDetector(
                          onTap: _deleteAlarm,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                              child: Container(
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: CupertinoColors.white.withValues(alpha: 0.16),
                                  border: Border.all(
                                    color: CupertinoColors.white.withValues(alpha: 0.42),
                                    width: 0.8,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x14000000),
                                      blurRadius: 12,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  'Delete',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: CupertinoColors.destructiveRed,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
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
              onPressed: _saveChanges,
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
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
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
