import 'feed_item.dart';

/// The thread shown in the mocks, used until a backend exists.
List<FeedItem> sampleThread() => [
  const TextMessage(
    sender: Person.maya,
    text: 'thought of you immediately.',
    time: '8:12 AM',
    reaction: '😂',
  ),
  const TextMessage(
    sender: Person.devon,
    text:
        'gooseee. I am in a room with nine people and I just laughed out loud, '
        'thank you',
    time: '8:15 AM',
  ),
  const PhotoMessage(
    sender: Person.maya,
    placeholder: 'photo — the goose machine',
    caption: 'Exhibit A.',
    time: '8:16 AM',
    reaction: '🥹',
  ),
  const EmojiMessage(
    sender: Person.devon,
    emoji: '🫶',
    count: 14,
    time: '8:17 AM',
  ),
  const StatusNote(text: 'is heads down till four', icon: '🎧'),
  const SecretMessage(
    sender: Person.maya,
    time: '9:26 AM',
    duration: SecretDuration.thirtySeconds,
    body: 'I already booked the thing for your birthday. Act surprised.',
  ),
];

/// Quick-reaction emoji in the bottom tray. Each person keeps their own set.
const mayaTrayEmoji = ['❤️', '😂', '🥹', '🔥', '🫶', '🌙', '🧋', '🐈'];
const devonTrayEmoji = ['❤️', '😂', '🥹', '🔥', '🫶', '🎈', '🍜', '💤'];

/// Emoji offered in the "Say it back" reaction sheet.
const reactionEmoji = ['❤️', '😂', '🥹', '🔥', '😮', '🙏', '😭', '💌', '🫶'];
