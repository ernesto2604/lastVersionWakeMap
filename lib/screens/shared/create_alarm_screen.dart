import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state_provider.dart';

class CreateAlarmScreen extends StatefulWidget {
  const CreateAlarmScreen({super.key});

  @override
  State<CreateAlarmScreen> createState() => _CreateAlarmScreenState();
}

class _CreateAlarmScreenState extends State<CreateAlarmScreen> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  LatLng? _selectedLocation;
  double _radius = 500;
  GoogleMapController? _mapController;
  LatLng _initialCenter = const LatLng(51.5074, -0.1278); // London default
  bool _loadingLocation = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  Future<void> _loadCurrentLocation() async {
    // Reuse the provider's LocationService singleton — avoids duplicate
    // permission checks and a second location fetch.
    final appState = context.read<AppStateProvider>();
    final position = appState.currentPosition;
    if (position != null && mounted) {
      setState(() {
        _initialCenter = LatLng(position.latitude, position.longitude);
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
    _nameController.dispose();
    super.dispose();
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
    if (!_formKey.currentState!.validate()) return;

    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please tap the map to select a location')),
      );
      return;
    }

    await context.read<AppStateProvider>().createAlarm(
          name: _nameController.text.trim(),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Alarm'),
        actions: [
          TextButton.icon(
            onPressed: _saveAlarm,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Name field
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Alarm Name',
                  hintText: 'e.g. Home, Work, York Station',
                  prefixIcon: Icon(Icons.label_outline),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
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
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
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
                    max: 2000,
                    divisions: 19,
                    label: '${_radius.round()} m',
                    onChanged: (val) => setState(() => _radius = val),
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
                        '2000 m',
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
    );
  }
}
