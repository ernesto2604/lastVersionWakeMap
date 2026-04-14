import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/chat_message_model.dart';
import '../../models/mock_plan_model.dart';
import '../../providers/app_state_provider.dart';

class TravellerGuideScreen extends StatefulWidget {
  const TravellerGuideScreen({super.key});

  @override
  State<TravellerGuideScreen> createState() => _TravellerGuideScreenState();
}

class _TravellerGuideScreenState extends State<TravellerGuideScreen> {
  static const _quickActions = <({String label, String prompt})>[
    (label: 'Cheaper', prompt: 'make it cheaper'),
    (label: 'Less walking', prompt: 'less walking'),
    (label: 'More food', prompt: 'add food'),
    (label: 'Shorter', prompt: 'shorter plan'),
  ];

  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage(AppStateProvider appState) {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    appState.sendGuideMessage(text);
    _textController.clear();
    FocusScope.of(context).unfocus();

    _scrollToBottomAfterUpdate();
  }

  void _sendQuickAction(AppStateProvider appState, String prompt) {
    appState.sendGuideMessage(prompt);
    _scrollToBottomAfterUpdate();
  }

  void _scrollToBottomAfterUpdate() {
    Future.delayed(const Duration(milliseconds: 450), () {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _estimatedDuration(MockPlanModel plan) {
    final provided = plan.estimatedDuration?.trim();
    if (provided != null && provided.isNotEmpty) return provided;

    if (plan.stops.length <= 2) return '~1h';
    if (plan.stops.length == 3) return '~2h';
    return '~${plan.stops.length}h';
  }

  String _estimatedBudget(MockPlanModel plan) {
    final provided = plan.estimatedBudget?.trim();
    if (provided != null && provided.isNotEmpty) return provided;

    final min = 5 + (plan.stops.length * 4);
    final max = min + 10;
    return '£$min-£$max';
  }

  Widget _buildHeader(
    BuildContext context,
    AppStateProvider appState,
    bool hasPlan,
  ) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Guide',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasPlan
                      ? 'Personalized for your arrival'
                      : 'Chat first, create the plan when ready',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
                  ),
                ),
              ],
            ),
          ),
          if (hasPlan)
            TextButton(
              onPressed: appState.clearGuideState,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              ),
              child: const Text('Reset'),
            ),
        ],
      ),
    );
  }

  Widget _buildGlassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.48),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.65),
              width: 0.9,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: _buildGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
        child: Column(
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 26,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            ),
            const SizedBox(height: 14),
            Text(
              'Your guide awaits',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask naturally about ideas, food, budget, or pace.\nWhen you are ready, say "create the plan".',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(BuildContext context, MockPlanModel plan) {
    final theme = Theme.of(context);
    final metadata = [
      _MetaDataChip(icon: Icons.schedule_outlined, label: _estimatedDuration(plan)),
      _MetaDataChip(icon: Icons.payments_outlined, label: _estimatedBudget(plan)),
      _MetaDataChip(icon: Icons.place_outlined, label: '${plan.stops.length} stops'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: _buildGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              plan.summary,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                height: 1.34,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: metadata,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, AppStateProvider appState) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _quickActions
            .map(
              (action) => ActionChip(
                label: Text(action.label),
                onPressed: () => _sendQuickAction(appState, action.prompt),
                side: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.22),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.72),
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.88),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildStopsList(BuildContext context, MockPlanModel plan) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Stops',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ...plan.stops.asMap().entries.map((entry) {
            final idx = entry.key;
            final stop = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildGlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${idx + 1}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stop.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            stop.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.67),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMessage(ChatMessageModel message) {
    final theme = Theme.of(context);
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        margin: EdgeInsets.only(
          left: isUser ? 34 : 0,
          right: isUser ? 0 : 34,
          bottom: 8,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9)
              : theme.colorScheme.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          message.text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
            height: 1.35,
          ),
        ),
      ),
    );
  }

  Widget _buildChatSection(
    BuildContext context,
    AppStateProvider appState,
    List<ChatMessageModel> messages,
    bool hasPlan,
  ) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conversation',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (messages.isEmpty)
            Text(
              hasPlan
                  ? 'Ask to refine your plan: budget, walking, food, or timing.'
                  : 'Try: "what do you recommend in York for 4 days?"',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
              ),
            )
          else
            ...messages.map(_buildMessage),

          if (!hasPlan && messages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  label: const Text('Create plan'),
                  onPressed: () {
                    appState.sendGuideMessage('create the plan');
                    _scrollToBottomAfterUpdate();
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputBar(BuildContext context, AppStateProvider appState) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 12),
      child: _buildGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  hintText: 'Ask the guide...',
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                style: theme.textTheme.bodyMedium,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(appState),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: () => _sendMessage(appState),
                icon: Icon(
                  Icons.arrow_upward_rounded,
                  color: theme.colorScheme.primary,
                ),
                tooltip: 'Send',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, appState, _) {
        final messages = appState.chatMessages;
        final plan = appState.currentPlan;
        final hasPlan = plan != null;

        return Scaffold(
          body: SafeArea(
            child: Stack(
              children: [
                CustomScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _buildHeader(context, appState, hasPlan),
                    ),
                    if (plan == null)
                      SliverToBoxAdapter(
                        child: _buildEmptyState(context),
                      )
                    else ...[
                      SliverToBoxAdapter(
                        child: _buildPlanCard(context, plan),
                      ),
                      SliverToBoxAdapter(
                        child: _buildQuickActions(context, appState),
                      ),
                      SliverToBoxAdapter(
                        child: _buildStopsList(context, plan),
                      ),
                    ],
                    SliverToBoxAdapter(
                      child: _buildChatSection(context, appState, messages, hasPlan),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 120),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _buildInputBar(context, appState),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MetaDataChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaDataChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.22),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
