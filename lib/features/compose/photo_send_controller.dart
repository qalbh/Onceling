import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../feed/feed_providers.dart';
import 'photo_upload_service.dart';

final firebaseStorageProvider = Provider<FirebaseStorage>(
  (ref) => FirebaseStorage.instance,
);

final photoUploadServiceProvider = Provider<PhotoUploader>(
  (ref) => PhotoUploadService(ref.watch(firebaseStorageProvider)),
);

/// Drives one photo from picked file to visible item (**P2-13**).
///
/// Riverpod rather than `setState` because the progress outlives the compose
/// sheet: the sheet closes on send, and the upload keeps running behind the
/// feed. A 2 MB upload on a slow connection is several seconds of somebody
/// wondering whether the tap registered, and that reassurance has to live
/// somewhere the closing sheet cannot take with it.
class PhotoSendController extends Notifier<PhotoUploadState> {
  @override
  PhotoUploadState build() =>
      const PhotoUploadState(status: PhotoUploadStatus.idle);

  /// Compresses, uploads, then writes the item — **in that order**.
  ///
  /// See `PhotoUploadService` for why. In short: a failure here leaves an
  /// invisible orphan in the bucket, whereas writing the item first would
  /// leave a permanently broken message in the thread.
  ///
  /// Returns true when the whole chain landed.
  Future<bool> send({
    required File file,
    required String coupleId,
    required String senderId,
    String? caption,
  }) async {
    final uploader = ref.read(photoUploadServiceProvider);
    final feed = ref.read(feedServiceProvider);

    // Minted before either write, so the object and the document share a key
    // even if only one of them ever exists.
    final itemId = feed.mintItemId();

    try {
      state = const PhotoUploadState(status: PhotoUploadStatus.compressing);
      final bytes = await uploader.compress(file);

      state = const PhotoUploadState(status: PhotoUploadStatus.uploading);
      final uploaded = await uploader.upload(
        coupleId: coupleId,
        itemId: itemId,
        bytes: bytes,
        onProgress: (progress) {
          state = PhotoUploadState(
            status: PhotoUploadStatus.uploading,
            progress: progress,
          );
        },
      );

      await feed.sendPhoto(
        coupleId: coupleId,
        senderId: senderId,
        itemId: uploaded.itemId,
        mediaUrl: uploaded.downloadUrl,
        caption: caption,
      );

      state = const PhotoUploadState(status: PhotoUploadStatus.done);
      return true;
    } on PhotoUploadFailure catch (failure) {
      state = PhotoUploadState(
        status: PhotoUploadStatus.failed,
        error: failure.message,
      );
      return false;
    } catch (_) {
      // The item write failed after the object landed: the orphan case. It is
      // deliberately not surfaced as anything other than "did not send" —
      // there is nothing the person can do about a stranded object, and the
      // couple's prefix is erased wholesale by P2-36's sweep.
      state = const PhotoUploadState(
        status: PhotoUploadStatus.failed,
        error: 'That photo did not send. Try again.',
      );
      return false;
    }
  }

  /// Clears a finished or failed upload once its banner has been seen.
  void reset() =>
      state = const PhotoUploadState(status: PhotoUploadStatus.idle);
}

final photoSendControllerProvider =
    NotifierProvider<PhotoSendController, PhotoUploadState>(
      PhotoSendController.new,
    );
