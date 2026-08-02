import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/providers.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';
import '../device_timezone.dart';
import '../models/pairing_request.dart';

/// **P2-25** — someone is asking to enter a space that holds one other person.
///
/// Asymmetric on purpose: the sender's name and avatar are shown here, while
/// **P2-23** shows the sender nothing about the recipient. B revealed
/// themselves by asking; A seeing who is asking costs B nothing they had not
/// already given up.
///
/// The name comes denormalised on the request document, not from a profile
/// read — a rule permitting "anyone who has messaged me can read my profile"
/// would be a surface an enumerator can create at will.
class IncomingRequestCard extends ConsumerStatefulWidget {
  const IncomingRequestCard({super.key, required this.request});

  final PairingRequest request;

  @override
  ConsumerState<IncomingRequestCard> createState() =>
      _IncomingRequestCardState();
}

class _IncomingRequestCardState extends ConsumerState<IncomingRequestCard> {
  bool _busy = false;

  Future<void> _respond({required bool accept}) async {
    setState(() => _busy = true);
    try {
      // **P2-40**: the accepting device names the couple's timezone. Read
      // before the call and never allowed to fail it — a device that cannot
      // report its own zone still gets to pair, and the server falls back.
      final timezone = accept ? await ref.read(deviceTimezoneProvider)() : null;

      await ref
          .read(pairingServiceProvider)
          .respondToPairing(
            widget.request.id,
            accept: accept,
            timezone: timezone,
          );
      // Nothing to navigate to on accept: the profile stream carries the new
      // coupleId, which arms the pairing moment and moves the gate (P2-26).
      // The accept transaction also expires every other pending request, so
      // the list shrinks on its own without a second call.
    } catch (error) {
      developer.log('respondToPairing failed: $error', name: 'IncomingRequest');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = widget.request;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _SenderAvatar(request: request),
              const SizedBox(width: 14),
              // Flexible, not a fixed width: a 40-character display name at
              // 200% text scale must wrap rather than overflow the row.
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.fromDisplayName,
                      style: AppTheme.bold(theme.textTheme.bodyLarge!),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'would like to pair with you',
                      style: theme.textTheme.titleMedium!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _busy ? null : () => _respond(accept: true),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                disabledBackgroundColor: context.palette.disabled,
                disabledForegroundColor: theme.colorScheme.onPrimary,
                elevation: 0,
                shape: const StadiumBorder(),
                textStyle: AppTheme.bold(theme.textTheme.bodyLarge!),
              ),
              child: const Text('Accept'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: TextButton(
              // "Not now", never "Reject" — the softer word matches the
              // register of the unpair copy, and the server writes 'expired'
              // so the sender is never told a person refused (PI-05).
              onPressed: _busy ? null : () => _respond(accept: false),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant,
                textStyle: AppTheme.bold(theme.textTheme.bodyLarge!),
              ),
              child: const Text('Not now'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The sender's avatar, or their initial when there is no image.
class _SenderAvatar extends StatelessWidget {
  const _SenderAvatar({required this.request});

  final PairingRequest request;

  @override
  Widget build(BuildContext context) {
    final url = request.fromAvatarUrl;
    const size = 46.0;

    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // A broken or hostile URL must not take the surface down with it.
          errorBuilder: (_, _, _) => _InitialAvatar(request: request),
        ),
      );
    }
    return _InitialAvatar(request: request);
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.request});

  final PairingRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = request.fromDisplayName;

    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.palette.blushPale,
        shape: BoxShape.circle,
      ),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: AppTheme.bold(theme.textTheme.bodyLarge!),
      ),
    );
  }
}
