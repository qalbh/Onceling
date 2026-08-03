import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

if (getApps().length === 0) initializeApp();

/** The eight quick-reaction emoji a new account starts with (**P2-30**). */
export const DEFAULT_FAVORITE_EMOJIS = [
  "❤️",
  "😂",
  "🥹",
  "🔥",
  "🫶",
  "🌙",
  "🧋",
  "🐈",
];

/** Matches the bound the users rules enforce on `displayName`. */
export const MAX_DISPLAY_NAME = 40;

/** Never empty — Security Rules reject a blank display name. */
export const FALLBACK_DISPLAY_NAME = "Someone";

/**
 * Sign-up input, else the token's name, else the email's local part.
 *
 * Resolved from the *token* rather than trusting a client-supplied identity:
 * the only thing the caller gets to choose is the name they typed.
 */
function resolveDisplayName(
  provided: unknown,
  token: { name?: string; email?: string } | undefined,
): string {
  const candidates = [
    typeof provided === "string" ? provided : undefined,
    token?.name,
    token?.email?.split("@")[0],
  ];
  for (const candidate of candidates) {
    const trimmed = candidate?.trim() ?? "";
    if (trimmed !== "") return trimmed.slice(0, MAX_DISPLAY_NAME);
  }
  return FALLBACK_DISPLAY_NAME;
}

/**
 * **P2-30 / P2-35** — creates `users/{uid}` if it is missing, and returns it
 * either way.
 *
 * Server-side because of P2-35: a recreated profile must carry the caller's
 * *real* `coupleId`, and a client can neither discover it (the `couples` list
 * rule is false) nor write it (the users rules reject any client write to
 * `coupleId` in either direction, which is the point of that rule).
 *
 * Writing `coupleId: null` for someone a couple still lists produces the exact
 * state `assertPairingInvariant` exists to catch — and it is worse than a dead
 * end, because it looks recoverable: the gate sends them to pairing,
 * `ensurePairingCode` succeeds because their profile now reads unpaired, and
 * they can join a second couple. Every precondition passes, because each one
 * reads the profile that is lying.
 */
export const ensureUserProfile = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (uid == null) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }

  const db = getFirestore();
  const userRef = db.doc(`users/${uid}`);

  const existing = await userRef.get();
  if (existing.exists) {
    // Idempotent, and deliberately before the couples query: an existing
    // profile is returned untouched, and the extra read is not spent. Only
    // the create path pays for it.
    const data = existing.data() ?? {};
    return {
      created: false,
      coupleId: data.coupleId ?? null,
      pairingCode: data.pairingCode ?? null,
      displayName: data.displayName ?? null,
    };
  }

  // limit(2) rather than limit(1): the point is to *detect* more than one, and
  // a limit(1) would silently return the arbitrary first.
  const couples = await db
    .collection("couples")
    .where("memberIds", "array-contains", uid)
    .limit(2)
    .get();

  if (couples.size > 1) {
    // Already broken before we got here. Picking one would turn a detectable
    // inconsistency into a permanent, invisible wrong answer.
    console.error(
      `[P2-35] ${uid} is a member of ${couples.size} couples: ` +
        `${couples.docs.map((d) => d.id).join(", ")}. ` +
        "Refusing to recreate their profile — this needs a human.",
    );
    throw new HttpsError(
      "failed-precondition",
      "Your account needs attention. Please contact support.",
      { reason: "multiple-couples" },
    );
  }

  const coupleId = couples.empty ? null : couples.docs[0].id;
  const displayName = resolveDisplayName(
    request.data?.displayName,
    request.auth?.token as { name?: string; email?: string } | undefined,
  );

  // Since P2-35 closed `allow create`, this is the ONLY writer of a profile
  // document, and the Admin SDK bypasses rules — so isWellFormedProfile no
  // longer guards this path at all. Every check that rule made has to hold
  // here, and each holds *by construction* rather than by validation:
  //
  //   field set       — a fixed literal; no client keys are spread in, so
  //                     hasOnly/hasAll cannot be violated
  //   displayName     — resolveDisplayName: non-strings dropped, trimmed,
  //                     sliced to MAX_DISPLAY_NAME, never empty
  //   avatarUrl       — literal null
  //   coupleId        — from the couples query above, never from the caller
  //   favoriteEmojis  — the fixed eight
  //   accentColor     — literal null
  //   createdAt       — serverTimestamp, so it cannot be back-dated
  //   pairingCode     — absent; claimed later by ensurePairingCode
  //
  // Constructing rather than validating is the stronger position: there is no
  // path by which a caller supplies a field at all.
  try {
    await userRef.create({
      displayName,
      avatarUrl: null,
      coupleId,
      favoriteEmojis: DEFAULT_FAVORITE_EMOJIS,
      accentColor: null,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    // create() rather than set(): set would clobber a document written between
    // our read and our write. The cost is that the loser of that race throws
    // ALREADY_EXISTS, so absorb it and report the winner's document — the
    // contract is idempotency, and two concurrent sign-ins are ordinary.
    if ((error as { code?: number | string }).code !== 6) throw error;
    const settled = (await userRef.get()).data() ?? {};
    return {
      created: false,
      coupleId: settled.coupleId ?? null,
      pairingCode: settled.pairingCode ?? null,
      displayName: settled.displayName ?? null,
    };
  }

  return { created: true, coupleId, pairingCode: null, displayName };
});

/**
 * **PI-02** — records that the §10 honesty disclosure was shown.
 *
 * **Server-written, not a client write to the profile.** The rules do permit a
 * client to update its own `users/{uid}` for `displayName`, so this could have
 * been a field-level write plus a rules change. It is a callable instead
 * because of what this field *is*: the record that a required disclosure was
 * made. Brief §10 calls overclaiming here a regulatory risk as well as a trust
 * risk, and evidence the client can author is weaker evidence. The timestamp is
 * the server's.
 *
 * Idempotent, and deliberately **set-once**: an existing value is returned
 * untouched rather than refreshed, so the stamp keeps meaning "when they first
 * saw it" rather than "when they last happened to open the app".
 */
export const markOnboardingSeen = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (uid == null) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }

  const db = getFirestore();
  const userRef = db.doc(`users/${uid}`);

  return await db.runTransaction(async (t) => {
    const snap = await t.get(userRef);
    if (!snap.exists) {
      throw new HttpsError("failed-precondition", "No profile document.", {
        reason: "profile-missing",
      });
    }

    const existing = snap.data()?.onboardingSeenAt;
    if (existing != null) {
      return { alreadySeen: true };
    }

    t.update(userRef, { onboardingSeenAt: FieldValue.serverTimestamp() });
    return { alreadySeen: false };
  });
});
