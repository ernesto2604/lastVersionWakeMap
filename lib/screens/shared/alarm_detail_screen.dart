import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/alarm_model.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/map/map_wrapper.dart';

class AlarmDetailScreen extends StatefulWidget {
  final AlarmModel alarm;

  const AlarmDetailScreen({super.key, required this.alarm});

  @override
  State<AlarmDetailScreen> createState() => _AlarmDetailScreenState();
}

class _AlarmDetailScreenState extends State<AlarmDetailScreen> {
  late TextEditingController _nameController;
  late double _radius;
  late bool _isActive;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.alarm.name);
    _radius = widget.alarm.radiusMeters;
    _isActive = widget.alarm.isActive;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _markChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  Future<void> _saveChanges() async {
    final updated = widget.alarm.copyWith(
      name: _nameController.text.trim(),
      radiusMeters: _radius,
      isActive: _isActive,
    );
    await context.read<AppStateProvider>().updateAlarm(updated);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _deleteAlarm() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Alarm'),
        content: Text('Delete "${widget.alarm.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
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
    final alarmPos = LatLng(widget.alarm.latitude, widget.alarm.longitude);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alarm Details'),
        actions: [
          if (_hasChanges)
            TextButton.icon(
              onPressed: _saveChanges,
              icon: const Icon(Icons.check),
              label: const Text('Save'),
            ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            onPressed: _deleteAlarm,
            tooltip: 'Delete',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Name
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Alarm Name',
              prefixIcon: Icon(Icons.label_outline),
            ),
            onChanged: (_) => _markChanged(),
          ),
          const SizedBox(height: 20),

          // Active toggle
          Card(
            child: SwitchListTile(
              title: const Text('Active'),
              subtitle: Text(
                _isActive ? 'Alarm is active' : 'Alarm is inactive',
              ),
              value: _isActive,
              onChanged: (val) {
                setState(() => _isActive = val);
                _markChanged();
              },
            ),
          ),
          const SizedBox(height: 16),

          // Coordinates
          Card(
            child: ListTile(
              leading: Icon(
                Icons.location_on,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Coordinates'),
              subtitle: Text(
                '${widget.alarm.latitude.toStringAsFixed(5)}, ${widget.alarm.longitude.toStringAsFixed(5)}',
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Radius slider
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Radius',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${_radius.round()} m',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
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
                    onChanged: (val) {
                      setState(() => _radius = val);
                      _markChanged();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Mini map
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 200,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: alarmPos,
                  zoom: 15,
                ),
                markers: {
                  Marker(markerId: const MarkerId('alarm'), position: alarmPos),
                },
                circles: {
                  Circle(
                    circleId: const CircleId('radius'),
                    center: alarmPos,
                    radius: _radius,
                    fillColor: theme.colorScheme.primary.withValues(
                      alpha: 0.15,
                    ),
                    strokeColor: theme.colorScheme.primary.withValues(
                      alpha: 0.5,
                    ),
                    strokeWidth: 2,
                  ),
                },
                zoomControlsEnabled: false,
                scrollGesturesEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                myLocationButtonEnabled: false,
                liteModeEnabled: MapWrapper.liteModeEnabled,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
