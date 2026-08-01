import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/app_toast.dart';
import '../../../common/providers.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/theme_colors.dart';
import '../models/pairing_request.dart';
import '../widgets/code_tiles.dart';
import '../widgets/incoming_request_card.dart';
import '../widgets/partner_code_field.dart';
import '../widgets/send_confirmation_sheet.dart';
import '../widgets/waiting_card.dart';

/// Pairing step: share your own code, or enter your partner's.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key, this.myCode = 'MK4Q7B', this.onPair});

  /// Fallback while the profile has no code yet — mock-era placeholder.
  final String myCode;

  /// Called with the partner's code once six characters are entered.
  final ValueChanged<String>? onPair;

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  static const _codeLength = 6;
  final _partnerCode = TextEditingController();

  /// One claim attempt per screen visit; the callable is idempotent anyway.
  bool _codeRequested = false;

  /// Resolved in build(): the profile's real code, or the mock fallback.
  String _shownCode = '';

  /// Set when the sender dismisses a settled request, so the entry form comes
  /// back without waiting for the document to disappear — it never does.
  String? _dismissedRequestId;

  bool get _canPair => _partnerCode.text.length == _codeLength;

  /// **P2-23.** Confirm, echoing the code back so a typo is catchable, before
  /// anything is sent. The sheet owns the send and the error copy.
  Future<void> _confirmSend() async {
    final code = _partnerCode.text.toUpperCase();
    if (widget.onPair case final onPair?) {
      onPair(code);
      return;
    }

    final sent = await showSendConfirmationSheet(context, code);
    if (sent != true || !mounted) return;

    // The outgoing stream now carries a pending request, which swaps this form
    // for the waiting card. Clear the field so returning here later is clean.
    setState(() {
      _partnerCode.clear();
      _dismissedRequestId = null;
    });
  }

  @override
  void dispose() {
    _partnerCode.dispose();
    super.dispose();
  }

  /// P2-08 client edge: if the signed-in profile has no code, claim one. The
  /// document stream repaints the tiles when the server write lands.
  void _ensureCodeIfMissing() {
    final profile = ref.read(currentUserProvider).valueOrNull;
    if (_codeRequested ||
        profile == null ||
        profile.isPaired ||
        profile.pairingCode != null) {
      return;
    }
    _codeRequested = true;
    ref.read(pairingServiceProvider).ensurePairingCode().catchError((
      Object error,
    ) {
      developer.log('ensurePairingCode failed: $error', name: 'PairingScreen');
      if (mounted) setState(() => _codeRequested = false); // allow retry
      return '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    ref.listen(currentUserProvider, (_, _) => _ensureCodeIfMissing());
    _ensureCodeIfMissing();
    _shownCode =
        ref.watch(currentUserProvider).valueOrNull?.pairingCode ??
        widget.myCode;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Find your person', style: AppTheme.wordmark(context, 30)),
              const SizedBox(height: 14),
              Text(
                'One code, one partner, forever after.',
                style: theme.textTheme.headlineMedium!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              ..._incomingSection(),
              ..._outgoingSection(theme),
              const SizedBox(height: 26),
              Center(
                child: Text(
                  'You can only ever be paired with one person.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium!.copyWith(
                    color: context.palette.inkFaint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// **P2-25.** Requests addressed to me, newest first. Loading and error are
  /// handled explicitly rather than collapsing to an empty list — a silent
  /// empty state here would hide the single most important thing on the screen.
  List<Widget> _incomingSection() {
    final incoming = ref.watch(incomingRequestsProvider);

    return switch (incoming) {
      AsyncData(:final value) when value.isEmpty => const [],
      AsyncData(:final value) => [
        for (final request in value) ...[
          IncomingRequestCard(request: request),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 8),
      ],
      AsyncError() => const [
        _Notice('Could not load requests. Pull the app open again.'),
        SizedBox(height: 14),
      ],
      // Nothing while it resolves: a spinner above the code would flash on
      // every cold start for a list that is almost always empty.
      _ => const [],
    };
  }

  /// **P2-24.** A live outgoing request replaces the entry form entirely —
  /// having both would invite sending a second request while one is pending.
  List<Widget> _outgoingSection(ThemeData theme) {
    final outgoing = ref.watch(outgoingRequestProvider);
    final request = outgoing.valueOrNull;

    final settled =
        request != null &&
        !request.isPending &&
        request.id == _dismissedRequestId;

    // An accepted request on THIS screen belongs to a couple that no longer
    // exists — being here at all means `coupleId` is null. After an unpair
    // (**P2-36**) the most recent outgoing request stays 'accepted' forever,
    // and rendering its card left the user stuck on "Paired / Opening your
    // space…" with no code and no way to enter one. Seen on device.
    //
    // Falling through to the entry form is also right in the brief window
    // just after accepting, before `coupleId` arrives: the form shows for an
    // instant and the gate then moves them on.
    final staleAccept =
        request != null && request.status == PairingRequestStatus.accepted;

    if (request == null || settled || staleAccept) return _entryForm(theme);

    return [
      WaitingCard(
        request: request,
        onReset: () => setState(() => _dismissedRequestId = request.id),
      ),
    ];
  }

  List<Widget> _entryForm(ThemeData theme) => [
    _Card(child: _shareSection()),
    const SizedBox(height: 18),
    Center(
      child: Text(
        'or',
        style: theme.textTheme.titleLarge!.copyWith(
          color: context.palette.inkFaint,
        ),
      ),
    ),
    const SizedBox(height: 18),
    _Card(child: _enterSection()),
  ];

  Widget _shareSection() {
    return Column(
      children: [
        const _SectionLabel('YOUR CODE'),
        const SizedBox(height: 20),
        CodeTiles(code: _shownCode),
        const SizedBox(height: 22),
        Row(
          spacing: 14,
          children: [
            Expanded(
              child: _PairingButton(
                label: 'Copy code',
                filled: false,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _shownCode));
                  if (!mounted) return;
                  showAppToast(context, 'Code copied');
                },
              ),
            ),
            Expanded(
              child: _PairingButton(
                label: 'Share link',
                filled: true,
                onPressed: () => showAppToast(context, 'Share link tapped'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _enterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('ENTER THEIRS'),
        const SizedBox(height: 20),
        PartnerCodeField(
          controller: _partnerCode,
          length: _codeLength,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        _PairingButton(
          label: 'Pair us',
          filled: true,
          onPressed: _canPair ? _confirmSend : null,
        ),
      ],
    );
  }
}

/// Read-only banner for the error branch of a stream.
class _Notice extends StatelessWidget {
  const _Notice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.titleMedium!.copyWith(color: context.palette.inkFaint),
    );
  }
}

/// White rounded panel the two sections sit in.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.labelSmall!.copyWith(color: context.palette.inkFaint),
    );
  }
}

/// Pill button sized for the pairing cards — shorter than the sign-in ones.
class _PairingButton extends StatelessWidget {
  const _PairingButton({
    required this.label,
    required this.filled,
    this.onPressed,
  });

  final String label;
  final bool filled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = AppTheme.bold(theme.textTheme.bodyLarge!);

    return SizedBox(
      height: 52,
      child: filled
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                disabledBackgroundColor: context.palette.disabled,
                disabledForegroundColor: theme.colorScheme.onPrimary,
                elevation: 0,
                shape: const StadiumBorder(),
                textStyle: textStyle,
              ),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurface,
                side: BorderSide(color: theme.colorScheme.outline, width: 1.2),
                shape: const StadiumBorder(),
                textStyle: textStyle,
              ),
              child: Text(label),
            ),
    );
  }
}
