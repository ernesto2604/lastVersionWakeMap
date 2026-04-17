import 'package:flutter/cupertino.dart';
import 'package:flutter_liquid_glass_plus/flutter_liquid_glass.dart';
import 'package:provider/provider.dart';
import '../../models/app_mode.dart';
import '../../providers/app_state_provider.dart';
import '../../services/local_notification_service.dart';

Future<void> showSettingsBottomSheet(BuildContext context) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (sheetContext) {
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.84;

      return _InteractiveBottomSheetContainer(
        height: maxHeight,
        onDismiss: () => Navigator.of(sheetContext).pop(),
        child: _SettingsScaffold(
          showNavigationBar: false,
          onClose: () => Navigator.of(sheetContext).pop(),
        ),
      );
    },
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _SettingsScaffold(
      showNavigationBar: true,
      onClose: () => Navigator.of(context).pop(),
    );
  }
}

class _SettingsScaffold extends StatelessWidget {
  const _SettingsScaffold({
    required this.showNavigationBar,
    required this.onClose,
  });

  final bool showNavigationBar;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      top: showNavigationBar,
      child: _SettingsContent(onClose: onClose),
    );

    if (showNavigationBar) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(
          middle: Text('Settings'),
        ),
        child: content,
      );
    }

    return Column(
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: SizedBox(
            height: 40,
            child: Stack(
              children: [
                const Align(
                  alignment: Alignment.center,
                  child: Text(
                    'Settings',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: CupertinoColors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: _SettingsGlassIconButton(
                    icon: CupertinoIcons.xmark,
                    semanticLabel: 'Close settings',
                    onTap: onClose,
                    size: 36,
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          height: 1,
          color: CupertinoColors.separator,
        ),
        Expanded(child: content),
      ],
    );
  }
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    final modeIcon = appState.mode == AppMode.commuter
        ? CupertinoIcons.car_detailed
        : CupertinoIcons.airplane;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _CupertinoSettingsSection(
          children: [
            _CupertinoSettingsRow(
              leading: Icon(
                modeIcon,
                color: CupertinoTheme.of(context).primaryColor,
              ),
              title: 'Current Mode',
              subtitle: appState.mode?.displayName ?? 'Not set',
              trailing: _SettingsGlassIconButton(
                icon: CupertinoIcons.arrow_2_circlepath,
                semanticLabel: 'Switch mode',
                size: 34,
                onTap: () => _switchMode(context, appState, onClose),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _CupertinoSettingsSection(
          children: [
            _CupertinoSettingsRow(
              leading: const Icon(CupertinoIcons.bell),
              title: 'Notifications',
              subtitle: 'Enable arrival alerts',
              trailing: _SettingsGlassIconButton(
                icon: CupertinoIcons.check_mark_circled,
                semanticLabel: 'Enable notifications',
                size: 34,
                onTap: () => _enableNotifications(context),
              ),
            ),
            const _CupertinoSettingsRow(
              leading: Icon(CupertinoIcons.moon),
              title: 'Dark Mode',
              subtitle: 'Coming soon',
            ),
            const _CupertinoSettingsRow(
              leading: Icon(CupertinoIcons.info),
              title: 'About WakeMap',
              subtitle: 'Version 1.0.0 MVP',
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _enableNotifications(BuildContext context) async {
    await LocalNotificationService.instance.requestPermissionsIfNeeded();
    if (!context.mounted) return;
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Notifications'),
        content: const Text(
          'If permission was granted, WakeMap can now show arrival alerts.',
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
  }

  void _switchMode(
    BuildContext context,
    AppStateProvider appState,
    VoidCallback closeSettings,
  ) {
    final newMode = appState.mode == AppMode.commuter
        ? AppMode.traveller
        : AppMode.commuter;

    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Switch Mode'),
        content: Text(
          'Switch to ${newMode.displayName} mode? The app layout will change.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              closeSettings();
              appState.setMode(newMode);
            },
            child: const Text('Switch'),
          ),
        ],
      ),
    );
  }
}

class _SettingsGlassIconButton extends StatelessWidget {
  const _SettingsGlassIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.size = 36,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final baseIconColor =
        CupertinoTheme.of(context).textTheme.textStyle.color ??
            CupertinoColors.label;

    return LGButton.custom(
      label: semanticLabel,
      onTap: onTap,
      width: size,
      height: size,
      quality: LGQuality.premium,
      useOwnLayer: true,
      settings: const LiquidGlassSettings(
        thickness: 32,
        blur: 18,
        chromaticAberration: 0.85,
        lightIntensity: 0.95,
        refractiveIndex: 1.28,
        saturation: 1.1,
        glassColor: Color(0x2CFFFFFF),
      ),
      glowColor: const Color(0x0EFFFFFF),
      glowRadius: 0.95,
      child: Icon(
        icon,
        size: size * 0.5,
        color: baseIconColor.withValues(alpha: 0.78),
      ),
    );
  }
}

class _CupertinoSettingsSection extends StatelessWidget {
  const _CupertinoSettingsSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: children),
    );
  }
}

class _CupertinoSettingsRow extends StatelessWidget {
  const _CupertinoSettingsRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: CupertinoColors.separator,
            width: 0.4,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(width: 24, child: Center(child: leading)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .textStyle
                        .copyWith(decoration: TextDecoration.none),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: CupertinoTheme.of(context).textTheme.tabLabelTextStyle
                        .copyWith(
                          color: CupertinoColors.secondaryLabel,
                          decoration: TextDecoration.none,
                        ),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
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
                  color: CupertinoTheme.of(context).scaffoldBackgroundColor,
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
