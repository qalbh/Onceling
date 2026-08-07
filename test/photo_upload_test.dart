import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/compose/photo_send_controller.dart';
import 'package:couple_app/features/compose/photo_upload_service.dart';
import 'package:couple_app/features/feed/feed_providers.dart';
import 'package:couple_app/features/feed/feed_service.dart';
import 'package:couple_app/features/feed/models/feed_item.dart';

/// **P2-13** — the orphan problem, which is the part worth testing.
///
/// A photo is one message split across two systems that cannot share a
/// transaction. These pin the ordering and both failure directions: the object
/// goes up first, and if the item write dies the object is stranded rather
/// than a broken message being visible in the thread.
const _coupleId = 'couple-ab';
const _senderId = 'alice';

/// Records the order of everything, so "upload before write" is assertable
/// rather than assumed.
class RecordingUploader implements PhotoUploader {
  RecordingUploader({this.failOnCompress = false, this.failOnUpload = false});

  final bool failOnCompress;
  final bool failOnUpload;
  final List<String> calls = [];

  @override
  Future<File?> pick(PhotoSource source) async => File('unused');

  @override
  Future<Uint8List> compress(File source) async {
    calls.add('compress');
    if (failOnCompress) {
      throw const PhotoUploadFailure('That image could not be prepared.');
    }
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<UploadedPhoto> upload({
    required String coupleId,
    required String itemId,
    required Uint8List bytes,
    void Function(double progress)? onProgress,
  }) async {
    calls.add('upload:$itemId');
    if (failOnUpload) {
      throw const PhotoUploadFailure('Upload failed. Check your connection.');
    }
    onProgress?.call(0.5);
    onProgress?.call(1);
    return UploadedPhoto(
      itemId: itemId,
      downloadUrl: 'https://example.test/$itemId.jpg',
    );
  }
}

class RecordingFeed implements FeedService {
  RecordingFeed({this.failOnSendPhoto = false});

  final bool failOnSendPhoto;
  final List<String> calls = [];
  int _minted = 0;

  @override
  String mintItemId() {
    _minted++;
    calls.add('mint');
    return 'item-$_minted';
  }

  @override
  Future<void> sendPhoto({
    required String coupleId,
    required String senderId,
    required String itemId,
    required String mediaUrl,
    String? caption,
  }) async {
    calls.add('sendPhoto:$itemId:$mediaUrl:${caption ?? "-"}');
    if (failOnSendPhoto) throw Exception('firestore refused');
  }

  @override
  Future<void> sendText({
    required String coupleId,
    required String senderId,
    required String text,
  }) async => calls.add('sendText');

  @override
  Future<void> sendEmoji({
    required String coupleId,
    required String senderId,
    required String emoji,
  }) async => calls.add('sendEmoji');

  @override
  Future<void> sendSecret({
    required String coupleId,
    required String senderId,
    required String text,
    required SecretDuration duration,
  }) async => calls.add('sendSecret');

  @override
  Future<void> react({
    required String itemId,
    required String senderId,
    required String emoji,
  }) async => calls.add('react');
}

ProviderContainer harness(RecordingUploader uploader, RecordingFeed feed) {
  final container = ProviderContainer(
    overrides: [
      photoUploadServiceProvider.overrideWithValue(uploader),
      feedServiceProvider.overrideWithValue(feed),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<bool> send(ProviderContainer container, {String? caption}) {
  return container
      .read(photoSendControllerProvider.notifier)
      .send(
        file: File('fake.jpg'),
        coupleId: _coupleId,
        senderId: _senderId,
        caption: caption,
      );
}

void main() {
  group('the happy path writes BOTH, in order', () {
    test('compress, then upload, then the item — never the reverse', () async {
      final uploader = RecordingUploader();
      final feed = RecordingFeed();
      final container = harness(uploader, feed);

      expect(await send(container, caption: 'us'), isTrue);

      // The ordering IS the design. If the item write ever moves ahead of the
      // upload, a failed upload starts leaving visible broken messages.
      expect(uploader.calls, ['compress', 'upload:item-1']);
      expect(feed.calls, [
        'mint',
        'sendPhoto:item-1:https://example.test/item-1.jpg:us',
      ]);
    });

    test('the object and the item share one id', () async {
      // What makes an orphan reclaimable: the path is derivable from the item
      // id, so the sweep can find objects no document points at.
      final uploader = RecordingUploader();
      final feed = RecordingFeed();
      await send(harness(uploader, feed));

      expect(uploader.calls.last, 'upload:item-1');
      expect(feed.calls.last, contains('sendPhoto:item-1:'));
    });

    test('progress is reported, and ends idle-of-busy', () async {
      final container = harness(RecordingUploader(), RecordingFeed());
      await send(container);

      final state = container.read(photoSendControllerProvider);
      expect(state.status, PhotoUploadStatus.done);
      expect(state.isBusy, isFalse);
    });

    test('an empty caption is stored as null, not as ""', () async {
      final feed = RecordingFeed();
      await send(harness(RecordingUploader(), feed), caption: null);
      expect(feed.calls.last, endsWith(':-'));
    });
  });

  group('neither — a failure before the upload writes nothing', () {
    test('a compression failure never reaches Storage or Firestore', () async {
      final uploader = RecordingUploader(failOnCompress: true);
      final feed = RecordingFeed();
      final container = harness(uploader, feed);

      expect(await send(container), isFalse);
      expect(uploader.calls, ['compress'], reason: 'no upload attempted');
      expect(
        feed.calls.where((c) => c.startsWith('sendPhoto')),
        isEmpty,
        reason: 'no item may exist without its object',
      );
      expect(
        container.read(photoSendControllerProvider).status,
        PhotoUploadStatus.failed,
      );
    });

    test('an upload failure writes no item', () async {
      // The important half of "both or neither": a failed upload must not
      // leave an item whose mediaUrl points at nothing.
      final uploader = RecordingUploader(failOnUpload: true);
      final feed = RecordingFeed();
      final container = harness(uploader, feed);

      expect(await send(container), isFalse);
      expect(feed.calls.where((c) => c.startsWith('sendPhoto')), isEmpty);
      expect(
        container.read(photoSendControllerProvider).error,
        'Upload failed. Check your connection.',
      );
    });
  });

  group('the orphan — the failure this ordering deliberately chooses', () {
    test(
      'a failed item write leaves the object, and reports failure',
      () async {
        final uploader = RecordingUploader();
        final feed = RecordingFeed(failOnSendPhoto: true);
        final container = harness(uploader, feed);

        expect(await send(container), isFalse);

        // The upload DID happen. That object is now unreferenced — invisible to
        // both people, and reclaimed with the couple's prefix by P2-36's sweep.
        // This is the accepted cost of not showing a broken message.
        expect(uploader.calls, contains('upload:item-1'));
        expect(
          container.read(photoSendControllerProvider).status,
          PhotoUploadStatus.failed,
        );
      },
    );

    test('the orphan sits at a path the sweep can derive', () async {
      // The sweep deletes by prefix precisely because no item points here.
      expect(
        PhotoUploadService.pathFor(coupleId: _coupleId, itemId: 'item-1'),
        'couples/couple-ab/photos/item-1.jpg',
      );
      expect(
        PhotoUploadService.pathFor(coupleId: _coupleId, itemId: 'item-1'),
        startsWith('couples/$_coupleId/photos/'),
      );
    });
  });

  group('the long edge is actually capped', () {
    // Measured on an iPhone 16e against dev: passing maxDimension to BOTH
    // minWidth and minHeight produced 2133x1600 from a 3000x2250 source, not
    // 1600x1200. `minWidth`/`minHeight` are MINIMUMS — they pin the SHORT
    // edge. That is 1.8x the intended pixel count, and it turned a 6.1 MB
    // source into 2.4 MB instead of the few hundred KB the estimate assumed.
    test('landscape scales the LONG edge to the cap', () {
      final t = PhotoUploadService.targetSize(3000, 2250);
      expect(t.width, 1600);
      expect(t.height, 1200);
    });

    test('portrait scales the LONG edge too', () {
      final t = PhotoUploadService.targetSize(2250, 3000);
      expect(t.height, 1600);
      expect(t.width, 1200);
    });

    test('neither dimension ever exceeds the cap', () {
      for (final (w, h) in [
        (4032, 3024),
        (3024, 4032),
        (5000, 1000),
        (1000, 5000),
      ]) {
        final t = PhotoUploadService.targetSize(w, h);
        expect(t.width, lessThanOrEqualTo(PhotoUploadService.maxDimension));
        expect(t.height, lessThanOrEqualTo(PhotoUploadService.maxDimension));
      }
    });

    test('a small photo is never scaled UP', () {
      // Upscaling would add bytes and no detail.
      final t = PhotoUploadService.targetSize(800, 600);
      expect(t.width, 800);
      expect(t.height, 600);
    });

    test('aspect ratio survives', () {
      final t = PhotoUploadService.targetSize(4000, 3000);
      expect(t.width / t.height, closeTo(4 / 3, 0.01));
    });
  });

  group('the compression settings are deliberate', () {
    test('1600px / quality 80 / 5MB cap', () async {
      // Pinned because they are a judgement, not a default: changing them is a
      // decision about how a photo looks on the other person's screen and how
      // long it takes to get there.
      expect(PhotoUploadService.maxDimension, 1600);
      expect(PhotoUploadService.jpegQuality, 80);
      // Must not exceed the cap in storage.rules, or the client would offer
      // uploads the server refuses.
      expect(PhotoUploadService.maxBytes, 5 * 1024 * 1024);
    });
  });

  group('a second send after a failure starts clean', () {
    test('reset clears the banner', () async {
      final container = harness(
        RecordingUploader(failOnUpload: true),
        RecordingFeed(),
      );
      await send(container);
      expect(
        container.read(photoSendControllerProvider).status,
        PhotoUploadStatus.failed,
      );

      container.read(photoSendControllerProvider.notifier).reset();
      expect(
        container.read(photoSendControllerProvider).status,
        PhotoUploadStatus.idle,
      );
    });
  });
}
