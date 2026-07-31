import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/providers.dart';
import '../../../common/time_format.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';
import '../../../theme/theme_glyphs.dart';
import '../models/pairing_request.dart';

/// **P2-24** — what B sees after sending, driven by `outgoingRequestProvider`.
///
/// Three states, and the copy for each is load-bearing:
///
/// - **pending** — says plainly that the partner sees it *next time they open
///   Onceling*. Push is **P3-04**; implying an instant notification would make
///   the app look broken when nothing happens for an hour.
/// - **expired** — the answer is no, and it must never say anyone refused
///   (**PI-05**). A decline and the 7-day timeout write the same status on
///   purpose, so this copy cannot distinguish them even if it wanted to.
/// - **cancelled** — B's own doing; falls back to the entry state.
class WaitingCard extends ConsumerStatefulWidget {
  const WaitingCard({super.key, required this.request, required this.onReset});

  final PairingRequest request;

  /// Returns the screen to the code-entry state.
  final VoidCallback onReset;

  @override
  ConsumerState<WaitingCard> createState() => _WaitingCardState();
}

class _WaitingCardState extends ConsumerState<WaitingCard> {
  bool _cancelling = false;

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    try {
      await ref
          .read(pairingServiceProvider)
          .cancelPairingRequest(widget.request.id);
      // No local state change on success: the request stream carries the new
      // status back and the card re-renders from that.
    } catch (error) {
      developer.log('cancelPairingRequest failed: $error', name: 'WaitingCard');
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;

    return switch (request.status) {
      PairingRequestStatus.pending => _Shell(
        glyph: '💌',
        title: 'Waiting to hear back',
        body: request.createdAt == null
            ? 'Your request is on its way.'
            : 'Sent ${formatRelativeTime(request.createdAt!)}.',
        footnote:
            'They will see it next time they open Onceling. '
            'We will not nudge them for you.',
        action: _cancelling ? null : 'Cancel request',
        onAction: _cancel,
      ),

      // Never "declined", never "rejected" — see the class comment.
      PairingRequestStatus.expired => _Shell(
        key: const Key('waiting-expired'),
        glyph: '🌙',
        title: 'No answer yet',
        body: 'That request is no longer waiting.',
        footnote: 'You can try another code whenever you like.',
        action: 'Try another code',
        onAction: widget.onReset,
      ),

      PairingRequestStatus.cancelled => _Shell(
        key: const Key('waiting-cancelled'),
        glyph: '🕊️',
        title: 'Request withdrawn',
        body: 'You cancelled that request.',
        footnote: 'Nothing was shared.',
        action: 'Enter a code',
        onAction: widget.onReset,
      ),

      // Accepted is a transient state: the profile stream is already carrying
      // the new coupleId and the gate is about to take over (P2-26).
      PairingRequestStatus.accepted => const _Shell(
        glyph: '🤍',
        title: 'Paired',
        body: 'Opening your space…',
        footnote: '',
      ),
    };
  }
}

class _Shell extends StatelessWidget {
  const _Shell({
    super.key,
    required this.glyph,
    required this.title,
    required this.body,
    required this.footnote,
    this.action,
    this.onAction,
  });

  final String glyph;
  final String title;
  final String body;
  final String footnote;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Glyph(glyph, size: context.glyphs.sealBadge),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTheme.wordmark(context, 24),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge!.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (footnote.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              footnote,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium!.copyWith(
                color: context.palette.inkFaint,
              ),
            ),
          ],
          if (action case final label?) ...[
            const SizedBox(height: 22),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurface,
                textStyle: AppTheme.bold(theme.textTheme.bodyLarge!),
              ),
              child: Text(label),
            ),
          ],
        ],
      ),
    );
  }
}
