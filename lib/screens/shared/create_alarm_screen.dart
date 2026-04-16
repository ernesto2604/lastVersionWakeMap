import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/map/map_wrapper.dart';

Future<void> showCreateAlarmBottomSheet(BuildContext context) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (sheetContext) {
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.9;

      return Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Container(
            height: maxHeight,
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(
              color: CupertinoColors.systemGroupedBackground,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: const CreateAlarmScreen(),
          ),
        ),
      );
    },
  );
}

class CreateAlarmScreen extends StatefulWidget {
  const CreateAlarmScreen({super.key});

  @override
  State<CreateAlarmScreen> createState() => _CreateAlarmScreenState();
}

class _CreateAlarmScreenState extends State<CreateAlarmScreen> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  LatLng? _selectedLocation;
  double _radius = 500;
  GoogleMapController? _mapController;
  LatLng _initialCenter = const LatLng(51.5074, -0.1278); // London default
  bool _loadingLocation = true;
  bool _canShowMyLocation = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onFieldChanged);
    _locationController.addListener(_onFieldChanged);
    _loadCurrentLocation();
  }

  void _onFieldChanged() {
    if (_submitted && mounted) {
      setState(() {});
    }
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
    _locationController.removeListener(_onFieldChanged);
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

    if (_selectedLocation == null) {
      showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Location Required'),
          content: const Text('Please tap the map to select a location.'),
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

    await context.read<AppStateProvider>().createAlarm(
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
                  child: TextFormField(
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
                      Slider(
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
