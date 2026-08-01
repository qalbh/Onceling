/// The pairing-code alphabet, mirrored from the generator.
///
/// **Source of truth is `CODE_ALPHABET` in `functions/src/pairing.ts`.** The
/// server mints codes; this copy exists only so the entry field can accept
/// exactly what the server can produce. Dart and TypeScript cannot share a
/// constant, so if one changes the other must — a rules test would not catch
/// the drift, because it is a client-side input filter.
///
/// Uppercase letters and digits with the ambiguous pairs removed — no `0`/`O`,
/// no `1`/`I`/`L` — because these codes get read aloud and typed by hand.
/// Those five characters can never appear in a real code, so the field rejects
/// them rather than letting someone type a code that cannot exist.
const pairingCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// Length of a pairing code. Mirrors `CODE_LENGTH` in `functions/src/pairing.ts`.
const pairingCodeLength = 6;
