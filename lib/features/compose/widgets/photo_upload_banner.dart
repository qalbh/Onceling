import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../photo_send_controller.dart';
import '../photo_upload_service.dart';

/// Progress and failure for a photo upload in flight (**P2-13**).
///
/// Lives on the feed rather than in the compose sheet because the sheet closes
/// the moment "Send" is tapped. Without this, several seconds pass with no
/// evidence the tap did anything — and the natural response to that is to send
/// the photo again.
///
/// Renders nothing when idle. A finished upload also renders nothing: the item
/// itself arrives in the thread through the listener, which is a better
/// confirmation than any banner.
class PhotoUploadBanner extends ConsumerWidget {
  const PhotoUploadBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(photoSendControllerProvider);
    final theme = Theme.of(context);

    if (state.status == PhotoUploadStatus.idle ||
        state.status == PhotoUploadStatus.done) {
      return const SizedBox.shrink();
    }

    final failed = state.status == PhotoUploadStatus.failed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: failed
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      switch (state.status) {
                        PhotoUploadStatus.compressing => 'Preparing photo…',
                        PhotoUploadStatus.uploading => 'Sending photo…',
                        PhotoUploadStatus.failed =>
                          state.error ?? 'That photo did not send.',
                        _ => '',
                      },
                      style: theme.textTheme.titleSmall!.copyWith(
                        color: failed
                            ? theme.colorScheme.onErrorContainer
                            : theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    if (state.isBusy) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        // Indeterminate while compressing: it is fast and has
                        // no measurable fraction, and a fake bar that jumps to
                        // 100% is worse than an honest spinner.
                        value: state.status == PhotoUploadStatus.uploading
                            ? state.progress
                            : null,
                        minHeight: 3,
                      ),
                    ],
                  ],
                ),
              ),
              if (failed)
                IconButton(
                  tooltip: 'Dismiss',
                  onPressed: () =>
                      ref.read(photoSendControllerProvider.notifier).reset(),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
