import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/feed/models/feed_item.dart';
import 'package:couple_app/features/feed/models/feed_item_mapper.dart';

/// Stands in for a Firestore `Timestamp`, which the mapper reads by duck-typing
/// `toDate()` until `cloud_firestore` is a dependency.
class _FakeTimestamp {
  const _FakeTimestamp(this._value);
  final DateTime _value;
  DateTime toDate() => _value;
}

/// toFirestore → fromFirestore → assert the item survived intact.
void expectRoundTrip(FeedItem item) {
  final data = toFirestore(item);
  expect(
    fromFirestore(item.id, data),
    equals(item),
    reason: 'round trip lost data for ${item.runtimeType}',
  );
}

void main() {
  final createdAt = DateTime(2026, 7, 30, 8, 12);
  const sender = 'uid-maya';
  const reader = 'uid-devon';

  group('round trip', () {
    test('TextMessage', () {
      expectRoundTrip(
        TextMessage(
          id: 'i1',
          senderId: sender,
          createdAt: createdAt,
          text: 'thought of you immediately.',
          reactions: const {reader: '😂'},
        ),
      );
    });

    test('PhotoMessage with url and caption', () {
      expectRoundTrip(
        PhotoMessage(
          id: 'i2',
          senderId: sender,
          createdAt: createdAt,
          mediaUrl: 'https://example.test/goose.jpg',
          caption: 'Exhibit A.',
          reactions: const {reader: '🥹'},
        ),
      );
    });

    test('PhotoMessage with null mediaUrl and null caption', () {
      expectRoundTrip(
        PhotoMessage(id: 'i3', senderId: sender, createdAt: createdAt),
      );
    });

    test('EmojiMessage with count > 1', () {
      expectRoundTrip(
        EmojiMessage(
          id: 'i4',
          senderId: sender,
          createdAt: createdAt,
          emoji: '🫶',
          count: 14,
        ),
      );
    });

    test('EmojiMessage with the default count', () {
      expectRoundTrip(
        EmojiMessage(
          id: 'i5',
          senderId: sender,
          createdAt: createdAt,
          emoji: '❤️',
        ),
      );
    });

    test('StatusNote', () {
      expectRoundTrip(
        StatusNote(
          id: 'i6',
          senderId: sender,
          createdAt: createdAt,
          text: 'is heads down till four',
          icon: '🎧',
        ),
      );
    });

    test('StatusNote with no icon', () {
      expectRoundTrip(
        StatusNote(
          id: 'i7',
          senderId: sender,
          createdAt: createdAt,
          text: 'set a mood',
        ),
      );
    });

    test('sealed SecretMessage', () {
      expectRoundTrip(
        SecretMessage(
          id: 'i8',
          senderId: sender,
          createdAt: createdAt,
          duration: SecretDuration.thirtySeconds,
        ),
      );
    });

    test('opening SecretMessage carries its window start', () {
      expectRoundTrip(
        SecretMessage(
          id: 'i9b',
          senderId: sender,
          createdAt: createdAt,
          duration: SecretDuration.thirtySeconds,
          secretState: SecretState.opening,
          openingStartedAt: DateTime(2026, 7, 30, 9, 30, 15),
          reactions: const {},
        ),
      );
    });

    test('opened SecretMessage', () {
      expectRoundTrip(
        SecretMessage(
          id: 'i9',
          senderId: sender,
          createdAt: createdAt,
          duration: SecretDuration.tenSeconds,
          secretState: SecretState.opened,
          openedAt: DateTime(2026, 7, 30, 9, 31),
          heldFullCountdown: true,
          reactions: const {reader: '🥹'},
        ),
      );
    });

    test('SecretMessage with no reveal window (until closed)', () {
      expectRoundTrip(
        SecretMessage(
          id: 'i10',
          senderId: sender,
          createdAt: createdAt,
          duration: SecretDuration.untilClosed,
        ),
      );
    });

    test('empty reactions map', () {
      final item = TextMessage(
        id: 'i11',
        senderId: sender,
        createdAt: createdAt,
        text: 'no reactions here',
      );
      expect(item.reactions, isEmpty);
      expectRoundTrip(item);
    });

    test('reactions from several people', () {
      expectRoundTrip(
        TextMessage(
          id: 'i12',
          senderId: sender,
          createdAt: createdAt,
          text: 'plural on every type, per brief §9',
          reactions: const {sender: '🔥', reader: '😭'},
        ),
      );
    });
  });

  group('round trip — milestone (P3-03)', () {
    test('MilestoneMessage', () {
      expectRoundTrip(
        MilestoneMessage(
          id: 'm1',
          createdAt: createdAt,
          day: 100,
          reactions: const {reader: '🥰'},
        ),
      );
    });

    test('a milestone has no author, structurally', () {
      // senderId is the class's no-author sentinel; nothing may pass one in,
      // which the constructor enforces by not having the parameter at all.
      final item = MilestoneMessage(id: 'm2', createdAt: createdAt, day: 365);
      expect(item.senderId, '');
    });

    test('the server document — no senderId at all — still maps', () {
      // The real document is authored in TypeScript without a senderId key.
      final item = fromFirestore('m3', {
        'type': 'milestone',
        'day': 1000,
        'reactions': <String, String>{},
        'createdAt': createdAt,
      });
      expect(item, isA<MilestoneMessage>());
      expect((item as MilestoneMessage).day, 1000);
      expect(item.senderId, '');
    });
  });

  group('document shape', () {
    test('untilClosed writes a null revealDurationSeconds', () {
      final data = toFirestore(
        SecretMessage(
          id: 'i13',
          senderId: sender,
          createdAt: createdAt,
          duration: SecretDuration.untilClosed,
        ),
      );
      expect(data['revealDurationSeconds'], isNull);
      expect(data['secretState'], 'sealed');
    });

    test('an unknown secretState throws rather than guessing', () {
      // The state decides whether a body is readable. Reading an unrecognised
      // one as `sealed` would treat an expired reveal as a fresh one, so this
      // deliberately does NOT degrade the way an unknown duration does.
      expect(
        () => fromFirestore('i-bad', {
          'senderId': sender,
          'type': 'secret',
          'createdAt': createdAt,
          'reactions': const <String, String>{},
          'secretState': 'shredded',
          'revealDurationSeconds': 30,
        }),
        throwsA(isA<UnknownSecretStateException>()),
      );
    });

    test('a missing secretState throws too — it is not optional', () {
      expect(
        () => fromFirestore('i-none', {
          'senderId': sender,
          'type': 'secret',
          'createdAt': createdAt,
          'reactions': const <String, String>{},
          'revealDurationSeconds': 30,
        }),
        throwsA(isA<UnknownSecretStateException>()),
      );
    });

    test('each state round-trips through its wire value', () {
      for (final (state, wire) in [
        (SecretState.sealed, 'sealed'),
        (SecretState.opening, 'opening'),
        (SecretState.opened, 'opened'),
      ]) {
        final data = toFirestore(
          SecretMessage(
            id: 'i-state',
            senderId: sender,
            createdAt: createdAt,
            duration: SecretDuration.thirtySeconds,
            secretState: state,
          ),
        );
        expect(data['secretState'], wire);
        expect(
          (fromFirestore('i-state', data) as SecretMessage).secretState,
          state,
        );
      }
    });

    test('id and coupleId are not written as fields', () {
      final data = toFirestore(
        TextMessage(
          id: 'i14',
          senderId: sender,
          createdAt: createdAt,
          text: 'hello',
        ),
      );
      expect(data.containsKey('id'), isFalse);
      expect(data.containsKey('coupleId'), isFalse);
    });

    test('no isSecret field — type carries that fact alone', () {
      final data = toFirestore(
        SecretMessage(
          id: 'i15',
          senderId: sender,
          createdAt: createdAt,
          duration: SecretDuration.tenSeconds,
        ),
      );
      expect(data.containsKey('isSecret'), isFalse);
      expect(data['type'], 'secret');
    });

    test('each subtype writes its own type', () {
      expect(
        toFirestore(
          TextMessage(
            id: 'a',
            senderId: sender,
            createdAt: createdAt,
            text: 'x',
          ),
        )['type'],
        'text',
      );
      expect(
        toFirestore(
          PhotoMessage(id: 'b', senderId: sender, createdAt: createdAt),
        )['type'],
        'photo',
      );
      expect(
        toFirestore(
          EmojiMessage(
            id: 'c',
            senderId: sender,
            createdAt: createdAt,
            emoji: '🔥',
          ),
        )['type'],
        'emoji',
      );
      expect(
        toFirestore(
          StatusNote(
            id: 'd',
            senderId: sender,
            createdAt: createdAt,
            text: 'x',
          ),
        )['type'],
        'status',
      );
      expect(
        toFirestore(
          SecretMessage(
            id: 'e',
            senderId: sender,
            createdAt: createdAt,
            duration: SecretDuration.tenSeconds,
          ),
        )['type'],
        'secret',
      );
    });
  });

  group('reading', () {
    test('accepts a Timestamp-shaped createdAt', () {
      final item = fromFirestore('i16', {
        'type': 'text',
        'senderId': sender,
        'createdAt': _FakeTimestamp(createdAt),
        'body': 'from a real Firestore read',
        'reactions': const <String, String>{},
      });
      expect(item.createdAt, createdAt);
    });

    test('a missing reactions field reads as empty, not null', () {
      final item = fromFirestore('i17', {
        'type': 'text',
        'senderId': sender,
        'createdAt': createdAt,
        'body': 'older document',
      });
      expect(item.reactions, isEmpty);
    });
  });

  group('rejects bad data', () {
    test('unknown type throws', () {
      expect(
        () => fromFirestore('i18', {
          'type': 'voice-note',
          'senderId': sender,
          'createdAt': createdAt,
        }),
        throwsA(isA<UnknownFeedItemTypeException>()),
      );
    });

    test('missing type throws', () {
      expect(
        () =>
            fromFirestore('i19', {'senderId': sender, 'createdAt': createdAt}),
        throwsA(isA<UnknownFeedItemTypeException>()),
      );
    });
  });

  group('unrecognised reveal duration falls back, never throws', () {
    SecretDuration readDuration(Object? seconds) {
      final item = fromFirestore('i20', {
        'type': 'secret',
        'senderId': sender,
        'createdAt': createdAt,
        'revealDurationSeconds': seconds,
        'secretState': 'sealed',
      });
      return (item as SecretMessage).duration;
    }

    test('rounds to the nearest known window', () {
      expect(readDuration(45), SecretDuration.thirtySeconds);
      expect(readDuration(60), SecretDuration.thirtySeconds);
      expect(readDuration(5), SecretDuration.tenSeconds);
      expect(readDuration(0), SecretDuration.tenSeconds);
    });

    test('a tie resolves to the shorter window', () {
      // 20 is equidistant from 10 and 30. Over-exposing a secret is the worse
      // failure, so the shorter window wins.
      expect(readDuration(20), SecretDuration.tenSeconds);
    });

    test('a non-numeric value falls back to untilClosed', () {
      expect(readDuration('soon'), SecretDuration.untilClosed);
    });

    test('known values still map exactly', () {
      expect(readDuration(10), SecretDuration.tenSeconds);
      expect(readDuration(30), SecretDuration.thirtySeconds);
      expect(readDuration(null), SecretDuration.untilClosed);
    });

    test('a future window degrades instead of crashing an old client', () {
      // The whole point: a newer client writing 60s must not break this build.
      expect(
        () => fromFirestore('i21', {
          'type': 'secret',
          'senderId': sender,
          'createdAt': createdAt,
          'revealDurationSeconds': 60,
          'secretState': 'sealed',
        }),
        returnsNormally,
      );
    });
  });
}
