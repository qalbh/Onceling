/// The two people in a pair. The feed renders relative to whichever one is
/// currently viewing, so the same thread produces both the sender and the
/// recipient layouts.
enum Person {
  maya('Maya', 'M'),
  devon('Devon', 'D');

  const Person(this.name, this.initial);

  final String name;
  final String initial;

  Person get other => this == maya ? devon : maya;
}

/// How long the recipient gets with a secret once they open it.
enum SecretDuration {
  tenSeconds('10 seconds', Duration(seconds: 10)),
  thirtySeconds('30 seconds', Duration(seconds: 30)),
  untilClosed('until they close it', null);

  const SecretDuration(this.label, this.window);

  final String label;
  final Duration? window;

  /// Short form used on the sent-secret bubble, e.g. "they get 30s with it".
  String get shortLabel => switch (this) {
    tenSeconds => 'they get 10s with it',
    thirtySeconds => 'they get 30s with it',
    untilClosed => 'until they close it',
  };
}

sealed class FeedItem {
  const FeedItem();
}

/// A plain written message.
class TextMessage extends FeedItem {
  const TextMessage({
    required this.sender,
    required this.text,
    required this.time,
    this.reaction,
    this.delivered = false,
  });

  final Person sender;
  final String text;
  final String time;
  final String? reaction;
  final bool delivered;
}

/// A photo with an optional caption underneath.
class PhotoMessage extends FeedItem {
  const PhotoMessage({
    required this.sender,
    required this.placeholder,
    required this.time,
    this.caption,
    this.reaction,
  });

  final Person sender;

  /// Label shown in the photo well until real image loading exists.
  final String placeholder;
  final String time;
  final String? caption;
  final String? reaction;
}

/// A single emoji sent large, optionally tapped repeatedly ("x14").
class EmojiMessage extends FeedItem {
  const EmojiMessage({
    required this.sender,
    required this.emoji,
    required this.time,
    this.count = 1,
  });

  final Person sender;
  final String emoji;
  final String time;
  final int count;
}

/// Ambient centred line, e.g. "is heads down till four".
class StatusNote extends FeedItem {
  const StatusNote({required this.text, this.icon});

  final String text;
  final String? icon;
}

/// A sealed message. The recipient sees a locked card they press and hold to
/// open; the sender sees a confirmation bubble instead.
class SecretMessage extends FeedItem {
  const SecretMessage({
    required this.sender,
    required this.time,
    required this.duration,
    this.body = '',
    this.delivered = true,
    this.openedAt,
    this.heldFullCountdown = false,
  });

  final Person sender;
  final String time;
  final SecretDuration duration;
  final String body;
  final bool delivered;

  /// Set once the recipient has opened it. From that point the body is gone
  /// for both people and only the "Opened" marker remains.
  final String? openedAt;

  /// Whether they stayed with it until the countdown emptied.
  final bool heldFullCountdown;

  bool get isOpened => openedAt != null;

  SecretMessage markOpened(String at, {required bool heldFull}) =>
      SecretMessage(
        sender: sender,
        time: time,
        duration: duration,
        // The body is deliberately dropped — it does not survive opening.
        delivered: delivered,
        openedAt: at,
        heldFullCountdown: heldFull,
      );
}
