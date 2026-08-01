import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

if (getApps().length === 0) initializeApp();

/** Longest mood note accepted. The sheet caps input at 30; this is the
 *  server's own bound, generous enough to survive a copy change and still far
 *  inside the rules' 2000-character body limit. */
export const MAX_MOOD_NOTE = 200;

/** Longest mood emoji accepted. Matches the rules' 16-character cap on
 *  `emoji`, which is enough for a multi-codepoint sequence. */
export const MAX_MOOD_EMOJI = 16;

function bounded(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > max) return null;
  return trimmed;
}

/**
 * **P2-12 / M-07** — set the caller's mood.
 *
 * Two writes, as **P2-06** decided: the ambient value onto `couples/{id}`, and
 * a `status` item into the scrollback.
 *
 * **Why a callable rather than a client write.** `couples` denies every client
 * write in every direction, so the ambient half is unreachable from a device
 * by design — the collection that decides who may read a thread is not
 * something an untrusted client edits.
 *
 * **Why both writes are here rather than one here and one on the client.**
 * They go in one batch. Split across a callable and a client write they could
 * half-apply: an ambient mood with no scrollback record, or a scrollback entry
 * the header contradicts. Neither is recoverable without a reconciliation pass
 * nobody would write.
 *
 * The item bypasses Security Rules, as every Admin SDK write does. That is
 * safe for the same reason `ensureUserProfile` is: the payload is a fixed
 * literal built here, so no caller-supplied key reaches the document — only
 * the two bounded values below, and they are validated before use.
 */
export const setMood = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (uid == null) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }

  const emoji = bounded(request.data?.emoji, MAX_MOOD_EMOJI);
  if (emoji == null) {
    throw new HttpsError("invalid-argument", "Pick a mood.", {
      reason: "emoji-invalid",
    });
  }

  // The note is optional — a mood can be an emoji alone. An empty one is not
  // an error, it just carries no line.
  const rawNote = request.data?.note;
  const note =
    rawNote == null || rawNote === "" ? "" : bounded(rawNote, MAX_MOOD_NOTE);
  if (note == null) {
    throw new HttpsError("invalid-argument", "That note is too long.", {
      reason: "note-invalid",
    });
  }

  const db = getFirestore();
  const userSnap = await db.doc(`users/${uid}`).get();
  const coupleId = userSnap.data()?.coupleId as string | null | undefined;
  if (coupleId == null) {
    throw new HttpsError("failed-precondition", "You are not paired.", {
      reason: "not-paired",
    });
  }

  const coupleRef = db.doc(`couples/${coupleId}`);
  const coupleSnap = await coupleRef.get();
  // Membership is checked against the couple, not inferred from the profile.
  // A profile pointing at a couple that does not list you is the incoherent
  // state P2-18 exists to prevent; refuse rather than write into it.
  const members = (coupleSnap.data()?.memberIds ?? []) as string[];
  if (!coupleSnap.exists || !members.includes(uid)) {
    throw new HttpsError("permission-denied", "That couple is not yours.", {
      reason: "not-a-member",
    });
  }

  const itemRef = db.collection("items").doc();

  await db
    .batch()
    .update(coupleRef, {
      moodEmoji: emoji,
      moodText: note,
      moodBy: uid,
      moodUpdatedAt: FieldValue.serverTimestamp(),
    })
    .create(itemRef, {
      coupleId,
      senderId: uid,
      type: "status",
      body: note,
      emoji,
      reactions: {},
      createdAt: FieldValue.serverTimestamp(),
    })
    .commit();

  return { itemId: itemRef.id };
});
