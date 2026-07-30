import 'feed_item.dart';

/// Stand-in uids until real accounts land (**M-02**). Firestore stores a uid on
/// every item; these are what the mock thread uses in place of one.
const mayaUid = 'uid-maya';
const devonUid = 'uid-devon';

/// Display identity for the mock pair. Replaced by real profile documents at
/// **M-02** — until then the view layer resolves a uid through here rather than
/// the model carrying names it should never have owned.
const mockMembers = <String, ({String name, String initial})>{
  mayaUid: (name: 'Maya', initial: 'M'),
  devonUid: (name: 'Devon', initial: 'D'),
};

String memberName(String uid) => mockMembers[uid]?.name ?? 'Them';

String memberInitial(String uid) => mockMembers[uid]?.initial ?? '?';

/// The other half of the pair. Real pairing resolves this from the couple
/// document; the mock has exactly two members.
String partnerOf(String uid) => uid == mayaUid ? devonUid : mayaUid;

/// Fixed clock times so the mock thread reads the way the designs do.
DateTime _at(int hour, int minute) => DateTime(2026, 7, 30, hour, minute);

/// The thread shown in the mocks, used until a backend exists.
List<FeedItem> sampleThread() => [
  TextMessage(
    id: 'sample-1',
    senderId: mayaUid,
    createdAt: _at(8, 12),
    text: 'thought of you immediately.',
    reactions: const {devonUid: '😂'},
  ),
  TextMessage(
    id: 'sample-2',
    senderId: devonUid,
    createdAt: _at(8, 15),
    text:
        'gooseee. I am in a room with nine people and I just laughed out loud, '
        'thank you',
  ),
  PhotoMessage(
    id: 'sample-3',
    senderId: mayaUid,
    createdAt: _at(8, 16),
    caption: 'Exhibit A.',
    reactions: const {devonUid: '🥹'},
  ),
  EmojiMessage(
    id: 'sample-4',
    senderId: devonUid,
    createdAt: _at(8, 17),
    emoji: '🫶',
    count: 14,
  ),
  StatusNote(
    id: 'sample-5',
    senderId: devonUid,
    createdAt: _at(9, 0),
    text: 'is heads down till four',
    icon: '🎧',
  ),
  SecretMessage(
    id: 'sample-6',
    senderId: mayaUid,
    createdAt: _at(9, 26),
    duration: SecretDuration.thirtySeconds,
  ),
];

/// Body for the mock secret. Real bodies live in `secretBodies/{itemId}` and are
/// fetched only at reveal time; this stands in until **P3-01**.
const sampleSecretBodies = <String, String>{
  'sample-6': 'I already booked the thing for your birthday. Act surprised.',
};

/// Quick-reaction emoji in the bottom tray. Each person keeps their own set.
const mayaTrayEmoji = ['❤️', '😂', '🥹', '🔥', '🫶', '🌙', '🧋', '🐈'];
const devonTrayEmoji = ['❤️', '😂', '🥹', '🔥', '🫶', '🎈', '🍜', '💤'];

/// Emoji offered in the "Say it back" reaction sheet.
const reactionEmoji = ['❤️', '😂', '🥹', '🔥', '😮', '🙏', '😭', '💌', '🫶'];
