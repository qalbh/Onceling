import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_colors.dart';
import '../../theme/theme_glyphs.dart';
import '../feed/models/feed_item.dart';
import 'photo_upload_service.dart';

/// What compose hands back when the user sends.
class ComposeResult {
  const ComposeResult({required this.text, this.secretDuration, this.photo});

  final String text;

  /// Null for an ordinary message; set when sealed as a secret.
  final SecretDuration? secretDuration;

  /// A picked, uncompressed file (**P2-13**). The caller uploads it — the
  /// sheet is gone by then, and the progress has to outlive it.
  final File? photo;

  bool get isSecret => secretDuration != null;

  /// A photo send. [text] becomes the caption, and may be empty.
  bool get isPhoto => photo != null;
}

/// Bottom sheet for writing a message. Toggling "Secret" morphs it in place:
/// the title, placeholder and send label change and the timer panel expands.
class ComposeSheet extends StatefulWidget {
  const ComposeSheet({super.key, required this.picker});

  /// Opens the camera or gallery and returns the file, or null on cancel.
  ///
  /// Injected so a widget test can drive the photo path without a platform
  /// channel — the same reason `FeedService` is an interface.
  final Future<File?> Function(PhotoSource source) picker;

  static Future<ComposeResult?> show(
    BuildContext context, {
    required Future<File?> Function(PhotoSource source) picker,
  }) {
    return showModalBottomSheet<ComposeResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (_) => ComposeSheet(picker: picker),
    );
  }

  @override
  State<ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<ComposeSheet> {
  final _controller = TextEditingController();
  bool _isSecret = false;
  SecretDuration _duration = SecretDuration.thirtySeconds;
  File? _photo;
  String? _pickError;

  /// A photo may be sent with no caption, so it satisfies "send" on its own.
  bool get _canSend => _controller.text.trim().isNotEmpty || _photo != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    Navigator.of(context).pop(
      ComposeResult(
        text: _controller.text.trim(),
        // A photo is never a secret — see `_pickPhoto`.
        secretDuration: _isSecret && _photo == null ? _duration : null,
        photo: _photo,
      ),
    );
  }

  /// Camera or gallery. Both platforms prompt for permission on first use;
  /// `PhotoUploadService.pick` translates a refusal into a sentence.
  Future<void> _choosePhotoSource() async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(sheetContext).pop(PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () => Navigator.of(sheetContext).pop(PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    await _pickPhoto(source);
  }

  /// **P2-13.** Picking is local UI state, so `setState` — the *upload* is the
  /// part that outlives this sheet and lives in Riverpod.
  Future<void> _pickPhoto(PhotoSource source) async {
    try {
      final file = await widget.picker(source);
      if (file == null || !mounted) return;
      setState(() {
        _photo = file;
        // Attaching a photo leaves secret mode. Secrets are text-only (P2-13):
        // P3-01's reveal deletes a `secretBodies` document, and a Storage
        // object is a second system it cannot reach in the same operation —
        // so a secret photo could not honour the one promise a secret makes.
        _isSecret = false;
      });
    } on PhotoUploadFailure catch (failure) {
      if (!mounted) return;
      setState(() => _pickError = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      // Lift the sheet above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        // Secret mode adds the timer panel, so the sheet can outgrow a short
        // screen — cap it and let the contents scroll.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _DragHandle(),
                  const SizedBox(height: 18),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Text(
                      _isSecret ? 'A secret' : 'Say something',
                      key: ValueKey(_isSecret),
                      style: AppTheme.wordmark(context, 30),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _field(),
                  const SizedBox(height: 18),
                  _chips(),
                  if (_photo case final photo?) ...[
                    const SizedBox(height: 16),
                    _PhotoPreview(
                      photo: photo,
                      onRemove: () => setState(() => _photo = null),
                    ),
                  ],
                  if (_pickError case final message?) ...[
                    const SizedBox(height: 12),
                    Text(
                      message,
                      style: Theme.of(context).textTheme.titleSmall!.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  // Timer panel only exists in secret mode.
                  if (_isSecret) ...[
                    const SizedBox(height: 18),
                    _TimerPanel(
                      selected: _duration,
                      onSelect: (d) => setState(() => _duration = d),
                    ),
                  ],
                  const SizedBox(height: 22),
                  _sendButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field() {
    final theme = Theme.of(context);

    return Container(
      height: 120,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: TextField(
        controller: _controller,
        autofocus: false,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: theme.textTheme.headlineLarge!.copyWith(height: 1.35),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          hintText: _isSecret
              ? 'Only they will see this. Once.'
              : 'What is it?',
          hintStyle: theme.textTheme.headlineLarge!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _chips() {
    // Wrap rather than Row so long labels or large text settings push the
    // second chip onto its own line instead of overflowing.
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _ComposeChip(
          label: _photo == null ? 'Add photo' : 'Photo attached',
          leading: '🖼️',
          selected: _photo != null,
          onTap: _photo == null
              ? _choosePhotoSource
              : () => setState(() => _photo = null),
        ),
        // Hidden once a photo is attached rather than disabled: a secret photo
        // is not a thing this app can honour (see `_pickPhoto`), and offering
        // a control that silently does nothing is the mistake P2-42 removed
        // from the sign-in screen.
        if (_photo == null)
          _ComposeChip(
            label: 'Secret',
            leading: '🔒',
            selected: _isSecret,
            onTap: () => setState(() => _isSecret = !_isSecret),
          ),
      ],
    );
  }

  Widget _sendButton() {
    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      height: 58,
      child: FilledButton(
        onPressed: _canSend ? _send : null,
        style: FilledButton.styleFrom(
          backgroundColor: context.palette.bubbleMine,
          foregroundColor: theme.colorScheme.onPrimary,
          disabledBackgroundColor: context.palette.sageDisabled,
          disabledForegroundColor: theme.colorScheme.onPrimary,
          elevation: 0,
          shape: const StadiumBorder(),
          textStyle: AppTheme.bold(theme.textTheme.headlineLarge!),
        ),
        child: Text(_isSecret ? 'Seal & send' : 'Send'),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 46,
        height: 5,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outline,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _ComposeChip extends StatelessWidget {
  const _ComposeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
  });

  final String label;
  final String? leading;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: ShapeDecoration(
          color: selected
              ? palette.bubbleMine
              : theme.colorScheme.surfaceContainerLowest,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? palette.bubbleMine : theme.colorScheme.outline,
              width: 1.2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            if (leading != null) Glyph(leading!, size: context.glyphs.chipLock),
            Text(
              label,
              style: theme.textTheme.bodyLarge!.copyWith(
                fontWeight: FontWeight.w600,
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "They can read it for" — how long the recipient gets once they open it.
class _TimerPanel extends StatelessWidget {
  const _TimerPanel({required this.selected, required this.onSelect});

  final SecretDuration selected;
  final ValueChanged<SecretDuration> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'They can read it for',
            style: theme.textTheme.bodyLarge!.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final duration in SecretDuration.values)
                _DurationChip(
                  label: duration.label,
                  selected: duration == selected,
                  onTap: () => onSelect(duration),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Then it is gone from our servers too. You will see the moment it '
            'is opened.',
            style: theme.textTheme.titleMedium!.copyWith(
              height: 1.4,
              color: context.palette.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: ShapeDecoration(
          color: selected
              ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.5)
              : theme.colorScheme.surfaceContainerLowest,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.outline,
              width: 1.2,
            ),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.headlineSmall!.copyWith(
            fontWeight: FontWeight.w600,
            color: selected
                ? theme.colorScheme.onSecondaryContainer
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// The attached photo, before it is sent.
///
/// Shown from the local file rather than a network URL: nothing has been
/// uploaded yet, and the point is to confirm *this* is the right picture
/// before it goes to the other person.
class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.photo, required this.onRemove});

  final File photo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topRight,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            // Capped rather than fixed: a portrait photo and a landscape one
            // are both allowed to be themselves.
            constraints: const BoxConstraints(maxHeight: 220),
            child: Image.file(photo, width: double.infinity, fit: BoxFit.cover),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Material(
            color: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.86),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close),
              tooltip: 'Remove photo',
            ),
          ),
        ),
      ],
    );
  }
}
