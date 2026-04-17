import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_liquid_glass_plus/flutter_liquid_glass.dart';
import 'package:flutter_liquid_glass_plus/buttons/liquid_glass_switch.dart';
import '../../models/alarm_model.dart';

class AlarmCard extends StatelessWidget {
  final AlarmModel alarm;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final EdgeInsetsGeometry margin;

  const AlarmCard({
    super.key,
    required this.alarm,
    required this.onTap,
    required this.onToggle,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
  });

  String _displayLocation() {
    final raw = alarm.locationLabel.trim();
    if (raw.isNotEmpty) {
      final firstChunk = raw.split(',').first.trim();
      if (firstChunk.isNotEmpty) return firstChunk;
    }

    return '${alarm.latitude.toStringAsFixed(4)}, ${alarm.longitude.toStringAsFixed(4)}';
  }

  @override
  Widget build(BuildContext context) {
    final primary = CupertinoTheme.of(context).primaryColor;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: alarm.isActive
                        ? primary
                        : CupertinoColors.systemGrey3,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alarm.name,
                        style: CupertinoTheme.of(context)
                            .textTheme
                            .textStyle
                            .copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: alarm.isActive
                                  ? CupertinoColors.label
                                  : CupertinoColors.secondaryLabel,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _displayLocation(),
                        style: CupertinoTheme.of(context)
                            .textTheme
                            .tabLabelTextStyle
                            .copyWith(color: CupertinoColors.secondaryLabel),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Radius: ${alarm.radiusMeters.round()} m',
                        style: CupertinoTheme.of(context)
                            .textTheme
                            .tabLabelTextStyle
                            .copyWith(
                              color: primary.withValues(alpha: 0.92),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
                LGSwitch(
                  value: alarm.isActive,
                  onChanged: (_) => onToggle(),
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
        ),
      ),
    );
  }
}
