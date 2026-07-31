import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/app_router.dart';
import '../../../common/app_toast.dart';
import '../../../common/providers.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';
import '../../../theme/theme_glyphs.dart';
import '../../feed/models/sample_thread.dart';
import '../../feed/widgets/feed_header.dart';
import '../../feed/widgets/reaction_tray.dart';
import '../widgets/settings_rows.dart';
import '../widgets/unpair_sheet.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    this.viewerId = mayaUid,
    this.coupleName = 'Maya & Devon',
    this.anniversary = '4 November 2023',
    this.streak = 47,
  });

  final String viewerId;
  final String coupleName;
  final String anniversary;
  final int streak;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final List<String> _favourites = List.of(
    widget.viewerId == mayaUid ? mayaTrayEmoji : devonTrayEmoji,
  );

  bool _secretAlerts = true;
  bool _screenshotAlerts = true;
  _NudgeLevel _nudges = _NudgeLevel.quiet;

  String get _partnerId => partnerOf(widget.viewerId);

  Future<void> _swapFavourite(int index) async {
    final picked = await ReactionTray.show(context, title: 'Pick a favourite');
    if (picked == null || !mounted) return;
    setState(() => _favourites[index] = picked);
  }

  Future<void> _signOut() async {
    // No navigation here: the redirect sees the auth change and lands the
    // whole app on sign-in. Navigating too would race it.
    await ref.read(authServiceProvider).signOut();
  }

  Future<void> _unpair() async {
    final confirmed = await UnpairSheet.show(
      context,
      partnerName: memberName(_partnerId),
      streak: widget.streak,
    );
    if (confirmed != true || !mounted) return;

    // Mock path until the unpair Function exists. The real flow clears
    // coupleId server-side and the gate lands on pairing — a signed-in user
    // cannot reach sign-in, the redirect would bounce them straight back.
    if (mounted) context.go(AppRoutes.pairing);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _header(context),
            const SizedBox(height: 26),
            _profile(),
            const SizedBox(height: 26),
            SettingsCard(
              children: [
                SettingsRow(label: 'Couple name', value: widget.coupleName),
                SettingsRow(label: 'Anniversary', value: widget.anniversary),
                SettingsRow(label: 'Streak', value: '${widget.streak}-day'),
              ],
            ),
            const SizedBox(height: 26),
            const SettingsSectionLabel('FAVOURITE EMOJI'),
            _favouritesCard(),
            const SizedBox(height: 26),
            SettingsCard(
              children: [
                SettingsRow(
                  label: 'Tell me when a secret is opened',
                  value: _secretAlerts ? 'On' : 'Off',
                  onTap: () => setState(() => _secretAlerts = !_secretAlerts),
                ),
                SettingsRow(
                  label: 'Mood nudges',
                  value: _nudges.label,
                  onTap: () => setState(() => _nudges = _nudges.next),
                ),
                SettingsRow(
                  label: 'Screenshot alerts',
                  value: _screenshotAlerts ? 'On' : 'Off',
                  onTap: () =>
                      setState(() => _screenshotAlerts = !_screenshotAlerts),
                ),
              ],
            ),
            const SizedBox(height: 26),
            SettingsCard(
              children: [SettingsRow(label: 'Sign out', onTap: _signOut)],
            ),
            const SizedBox(height: 26),
            SettingsCard(
              children: [
                SettingsRow(
                  label: 'Unpair from ${memberName(_partnerId)}',
                  destructive: true,
                  onTap: _unpair,
                ),
                SettingsRow(
                  label: 'Delete my account',
                  destructive: true,
                  onTap: () => showAppToast(context, 'Not wired up yet'),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Center(
              child: Text(
                'Onceling · 1.0',
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: context.palette.inkFaint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      spacing: 16,
      children: [
        GestureDetector(
          onTap: () => context.pop(),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chevron_left, size: 26),
          ),
        ),
        Text('Settings', style: AppTheme.wordmark(context, 30)),
      ],
    );
  }

  Widget _profile() {
    return Row(
      spacing: 18,
      children: [
        PersonAvatar(initial: memberInitial(widget.viewerId), size: 78),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                memberName(widget.viewerId),
                style: AppTheme.wordmark(context, 26),
              ),
              const SizedBox(height: 4),
              Text(
                'paired with ${memberName(_partnerId)}',
                style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                  color: context.palette.inkFaint,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _favouritesCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eight slots across a phone is tight, so scale down rather than
          // overflow when the row cannot fit.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              spacing: 8,
              children: [
                for (var i = 0; i < _favourites.length; i++)
                  GestureDetector(
                    onTap: () => _swapFavourite(i),
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Glyph(
                        _favourites[i],
                        size: context.glyphs.favouriteSlot,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Tap a slot to swap it.',
            style: Theme.of(
              context,
            ).textTheme.titleLarge!.copyWith(color: context.palette.inkFaint),
          ),
        ],
      ),
    );
  }
}

enum _NudgeLevel {
  quiet('Quiet'),
  loud('Loud'),
  off('Off');

  const _NudgeLevel(this.label);

  final String label;

  _NudgeLevel get next =>
      _NudgeLevel.values[(index + 1) % _NudgeLevel.values.length];
}
