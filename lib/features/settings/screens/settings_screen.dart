import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../common/app_toast.dart';
import '../../../common/providers.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';
import '../../../theme/theme_glyphs.dart';
import '../../feed/feed_emoji.dart';
import '../../pairing/couple_names.dart';
import '../../feed/widgets/feed_header.dart';
import '../../feed/widgets/reaction_tray.dart';
import '../widgets/settings_rows.dart';
import '../widgets/unpair_sheet.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// The reader's own favourites, seeded from their profile.
  ///
  /// This used to be chosen by comparing a mock uid, which showed one fixed
  /// person's set to everyone. Editing them is still local-only — persisting
  /// a change back to `favoriteEmojis` is not built yet.
  List<String>? _favourites;

  List<String> get _favouriteEmoji =>
      _favourites ??
      ref.watch(currentUserProvider).valueOrNull?.favoriteEmojis ??
      defaultTrayEmoji;

  bool _secretAlerts = true;
  bool _screenshotAlerts = true;
  _NudgeLevel _nudges = _NudgeLevel.quiet;

  Future<void> _swapFavourite(int index) async {
    final picked = await ReactionTray.show(context, title: 'Pick a favourite');
    if (picked == null || !mounted) return;
    setState(() {
      final next = List.of(_favouriteEmoji);
      next[index] = picked;
      _favourites = next;
    });
  }

  Future<void> _signOut() async {
    // No navigation here: the redirect sees the auth change and lands the
    // whole app on sign-in. Navigating too would race it.
    await ref.read(authServiceProvider).signOut();
  }

  Future<void> _unpair() async {
    // The sheet owns the call now (**P2-36**): it needs to stay open and hold
    // the error when the callable fails, which it cannot do from here once it
    // has popped.
    //
    // Still no navigation on success. Clearing `coupleId` makes the gate want
    // /pairing, and /settings is inside that area's allowed set, so it returns
    // STAY and this screen remains — the partner, sitting on /feed, is the one
    // the gate actually moves. See P2-37 for what manual navigation cost here.
    await UnpairSheet.show(
      context,
      partnerName: ref.watch(partnerNameProvider),
      streak: ref.read(streakProvider).count,
    );
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
                SettingsRow(
                  label: 'Couple name',
                  value: ref.watch(coupleTitleProvider),
                ),
                SettingsRow(
                  label: 'Anniversary',
                  value: ref.watch(anniversaryLabelProvider),
                ),
                SettingsRow(
                  label: 'Streak',
                  value: switch (ref.watch(streakProvider)) {
                    (count: 0, faded: _) => 'Not started',
                    // Says out loud what the faded pill only implies.
                    (count: final n, faded: true) => '$n-day, ended',
                    (count: final n, faded: false) => '$n-day',
                  },
                ),
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
                  label: 'Unpair from ${ref.watch(partnerNameProvider)}',
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
        PersonAvatar(
          initial: ref.watch(myNameProvider).characters.first.toUpperCase(),
          size: 78,
        ),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ref.watch(myNameProvider),
                style: AppTheme.wordmark(context, 26),
              ),
              const SizedBox(height: 4),
              Text(
                'paired with ${ref.watch(partnerNameProvider)}',
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
                for (var i = 0; i < _favouriteEmoji.length; i++)
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
                        _favouriteEmoji[i],
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
