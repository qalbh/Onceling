import 'feed_item.dart';

/// Stand-in uids until real accounts land (**M-02**). Firestore stores a uid on
/// every item; these are what the mock thread uses in place of one.
const mayaUid = 'uid-maya';
const devonUid = 'uid-devon';

/// Display names for the two mock uids, used only while the thread itself is
/// mock data. Resolution now lives in `memberNameResolverProvider`, which
/// consults the couple's real `memberNames` first and only falls back here.
///
/// **Delete this with the mock thread at P2-12.** It exists so the sample feed
/// stays readable, not because mock identity is wanted on real screens.
const mockMembers = <String, ({String name, String initial})>{
  mayaUid: (name: 'Maya', initial: 'M'),
  devonUid: (name: 'Devon', initial: 'D'),
};

/// The other of the two mock uids, for the viewer-swap affordance on the mock
/// thread. Real partner resolution is `Couple.partnerOf`. **Delete at P2-12.**
String mockPartnerOf(String uid) => uid == mayaUid ? devonUid : mayaUid;

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
