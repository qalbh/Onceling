// Emoji sets the feed offers. Not mock data — these are real defaults, which
// is why they outlived `sample_thread.dart` rather than being deleted with it.

/// Fallback quick-reaction tray.
///
/// Used only in the instant before a profile resolves. A real tray is the
/// reader's own `favoriteEmojis`, which `ensureUserProfile` writes with these
/// same eight values, so the fallback and the real thing agree.
const defaultTrayEmoji = ['❤️', '😂', '🥹', '🔥', '🫶', '🌙', '🧋', '🐈'];

/// Emoji offered in the "Say it back" reaction sheet.
const reactionEmoji = ['❤️', '😂', '🥹', '🔥', '😮', '🙏', '😭', '💌', '🫶'];
