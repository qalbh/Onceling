import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

/// Where a photo came from.
enum PhotoSource { camera, gallery }

/// A photo upload in flight, or finished.
///
/// `progress` is 0..1 and only meaningful while [PhotoUploadStatus.uploading].
class PhotoUploadState {
  const PhotoUploadState({required this.status, this.progress = 0, this.error});

  final PhotoUploadStatus status;
  final double progress;
  final String? error;

  bool get isBusy =>
      status == PhotoUploadStatus.compressing ||
      status == PhotoUploadStatus.uploading;
}

enum PhotoUploadStatus { idle, compressing, uploading, done, failed }

/// The result of a successful upload: everything the item write needs.
class UploadedPhoto {
  const UploadedPhoto({required this.itemId, required this.downloadUrl});

  /// Minted before the upload, so the object and its document share a key.
  final String itemId;
  final String downloadUrl;
}

/// Human-readable failure. The UI shows [message]; nothing shows a raw code.
class PhotoUploadFailure implements Exception {
  const PhotoUploadFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Picks, compresses and uploads one photo.
///
/// An interface for the same reason `FeedService` is one: the orphan-ordering
/// tests have to assert *what happened in which order* when one half fails,
/// and neither a camera nor a bucket is available under `flutter test`.
abstract interface class PhotoUploader {
  Future<File?> pick(PhotoSource source);
  Future<Uint8List> compress(File source);
  Future<UploadedPhoto> upload({
    required String coupleId,
    required String itemId,
    required Uint8List bytes,
    void Function(double progress)? onProgress,
  });
}

/// Picks, compresses and uploads one photo (**P2-13**).
///
/// ## Compression: 1600px long edge, quality 80
///
/// A phone camera produces 3-8 MB. The feed renders a photo at roughly 84% of
/// the bubble width — about 300dp, so ~900px on a 3x screen — and a full-screen
/// view is at most the device's own resolution. 1600px covers both with room
/// for a future zoom or a tablet, and is far below what any of them need.
/// Quality 80 is the knee of the JPEG curve: the point past which bytes climb
/// faster than anything visible improves.
///
/// **Measured on an SM-A325F, camera capture, not an estimate:** a 4.5 MB
/// 2400x3200 frame came out 1200x1600 at **132 KB** — under the 200-500 KB this
/// originally claimed. A gallery PNG at 1080x2400 came out **53 KB**. Both were
/// low-detail scenes; a busy one lands higher, and the 5 MB cap in
/// `storage.rules` is roughly 40x the observed size rather than the 10x
/// originally assumed. The one number to distrust here is any number that has
/// not been measured on a real photograph.
///
/// Re-encoding also normalises the format. An iPhone shoots HEIC, which is not
/// universally decodable; everything leaves here as JPEG, which is why
/// `storage.rules` can check for exactly one content type.
///
/// ## Why the upload happens BEFORE the item is written
///
/// A photo message is two writes to two systems — a Storage object and an
/// `items` document — and either can fail. Both orders leave a mess; they are
/// not the same mess.
///
/// **Item first, then upload:** a failed upload leaves an item in the feed
/// whose `mediaUrl` points at nothing. Both people see a broken message. It is
/// visible, it is permanent (there is no delete-a-message feature), and the
/// person who sent it cannot fix it.
///
/// **Upload first, then item:** a failed item write leaves an object in the
/// bucket that nothing references. Nobody sees it. It costs a little storage
/// until it is reclaimed, and it is reclaimable *because the path is
/// derivable* — the id is minted here, before either write, so the object
/// lives at `couples/{coupleId}/photos/{itemId}` whether or not the document
/// ever arrives.
///
/// So: **upload, then write.** The failure mode is invisible and recoverable
/// rather than visible and permanent. This is the same reasoning that made
/// `sendSecret` a batch — the difference is that Storage and Firestore cannot
/// share a transaction, so the orphan cannot be designed away, only pointed in
/// the less harmful direction.
///
/// **Reclaiming the orphan.** P2-36's sweep deletes the couple's entire
/// `couples/{coupleId}/photos/` prefix rather than walking items and deleting
/// each `mediaUrl`. That is deliberate: a prefix delete removes linked objects
/// and orphans alike, so an upload that never got its document is still erased
/// when the couple is. An item-driven deletion would miss exactly the objects
/// no item points at — which is the entire orphan set.
class PhotoUploadService implements PhotoUploader {
  PhotoUploadService(this._storage, {ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final FirebaseStorage _storage;
  final ImagePicker _picker;

  /// Long edge cap, in pixels. Enforced by [targetSize], not by the plugin.
  static const maxDimension = 1600;

  /// JPEG quality. See the class note.
  static const jpegQuality = 80;

  /// Mirrors the cap in `storage.rules`. Checked here too so an oversized file
  /// fails immediately with a sentence a person can act on, rather than as a
  /// permission error after uploading five megabytes.
  static const maxBytes = 5 * 1024 * 1024;

  /// The object path for an item. **One definition, used by the client and
  /// mirrored by the sweep** — if these drift, orphans stop being reclaimable.
  static String pathFor({required String coupleId, required String itemId}) =>
      'couples/$coupleId/photos/$itemId.jpg';

  /// Opens the camera or the gallery.
  ///
  /// Returns null when the person backs out. Backing out is a decision, not a
  /// fault, and must not surface an error — the same rule the cancelled Google
  /// sign-in follows.
  ///
  /// Permissions are handled by `image_picker` on both platforms: it triggers
  /// the OS prompt and reports a refusal as a `PlatformException`, which is
  /// translated here rather than thrown at the UI. The platform manifests carry
  /// the usage strings — `NSCameraUsageDescription` and
  /// `NSPhotoLibraryUsageDescription` on iOS, `CAMERA` on Android — and without
  /// them iOS terminates the app rather than showing a prompt.
  @override
  Future<File?> pick(PhotoSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source == PhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        // A first pass in the picker itself. Compression still runs after —
        // this only avoids decoding a 48MP frame into memory to begin with.
        maxWidth: maxDimension.toDouble() * 2,
        maxHeight: maxDimension.toDouble() * 2,
      );
      return picked == null ? null : File(picked.path);
    } on Exception catch (error) {
      final text = error.toString();
      if (text.contains('camera_access_denied') ||
          text.contains('photo_access_denied')) {
        throw const PhotoUploadFailure(
          'Onceling needs permission to use your camera and photos. '
          'You can turn it on in Settings.',
        );
      }
      throw const PhotoUploadFailure('Could not open that. Try again.');
    }
  }

  /// Compresses to JPEG at [maxDimension] / [jpegQuality].
  ///
  /// Returns the bytes rather than a file so the caller never has to clean up
  /// a temporary, and so the size check below is on what will actually be sent.
  /// The output size for a source of [width] x [height].
  ///
  /// **`minWidth`/`minHeight` are MINIMUMS, not a bounding box.** The plugin
  /// scales so both dimensions are at least what it is given, which pins the
  /// SHORT edge — passing 1600/1600 for a 3000x2250 photo yields 2133x1600, not
  /// 1600x1200. Measured on device: 1.8x the intended pixel count, and a 6.1 MB
  /// source came out at 2.4 MB rather than the few hundred KB intended.
  ///
  /// So the scale is computed here and handed over exactly.
  static ({int width, int height}) targetSize(int width, int height) {
    final longest = width > height ? width : height;
    if (longest <= maxDimension) return (width: width, height: height);
    final scale = maxDimension / longest;
    return (
      width: (width * scale).round().clamp(1, maxDimension),
      height: (height * scale).round().clamp(1, maxDimension),
    );
  }

  @override
  Future<Uint8List> compress(File source) async {
    // Dimensions first, because the target depends on them.
    final descriptor = await ui.ImageDescriptor.encoded(
      await ui.ImmutableBuffer.fromUint8List(await source.readAsBytes()),
    );
    final target = targetSize(descriptor.width, descriptor.height);
    descriptor.dispose();

    final result = await FlutterImageCompress.compressWithFile(
      source.absolute.path,
      minWidth: target.width,
      minHeight: target.height,
      quality: jpegQuality,
      format: CompressFormat.jpeg,
      // Cameras record orientation in EXIF rather than rotating pixels. Without
      // this a portrait photo arrives sideways, and the metadata that would
      // have explained it is stripped by the re-encode.
      autoCorrectionAngle: true,
    );

    if (result == null) {
      throw const PhotoUploadFailure('That image could not be prepared.');
    }
    if (result.length >= maxBytes) {
      throw const PhotoUploadFailure('That photo is too large to send.');
    }
    return result;
  }

  /// Uploads to the couple-scoped path and returns the download URL.
  ///
  /// [onProgress] receives 0..1. A 2 MB upload on a slow connection is several
  /// seconds of somebody wondering whether the tap registered, so the caller
  /// needs something better than a spinner with no end in sight.
  /// [itemId] is minted by the caller — `FeedService` uses an unwritten
  /// Firestore document id, exactly as `sendSecret` does. Passing it in rather
  /// than generating one here is what lets the object and the document share a
  /// key across two systems that cannot share a transaction.
  @override
  Future<UploadedPhoto> upload({
    required String coupleId,
    required String itemId,
    required Uint8List bytes,
    void Function(double progress)? onProgress,
  }) async {
    final ref = _storage.ref(pathFor(coupleId: coupleId, itemId: itemId));

    try {
      final task = ref.putData(
        bytes,
        // Must match `storage.rules`' content-type check. Set explicitly
        // rather than inferred: the rule rejects anything else, and an
        // inferred `application/octet-stream` would be rejected by our own
        // rules with a permission error that looks like a membership problem.
        SettableMetadata(contentType: 'image/jpeg'),
      );

      task.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes > 0) {
          onProgress?.call(snapshot.bytesTransferred / snapshot.totalBytes);
        }
      });

      await task;
      return UploadedPhoto(
        itemId: itemId,
        downloadUrl: await ref.getDownloadURL(),
      );
    } on FirebaseException catch (error) {
      if (error.code == 'unauthorized') {
        throw const PhotoUploadFailure(
          'That photo could not be sent to your space.',
        );
      }
      throw const PhotoUploadFailure('Upload failed. Check your connection.');
    }
  }
}
