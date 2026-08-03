import * as crypto from "node:crypto";

import { getApps, initializeApp } from "firebase-admin/app";
import {
  FieldValue,
  Firestore,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { normaliseTimezone } from "./timezone.js";

if (getApps().length === 0) initializeApp();

/**
 * Code alphabet: uppercase letters and digits with the ambiguous ones removed —
 * no 0/O, no 1/I/L. These codes get read aloud over dinner and typed by hand
 * on a phone keyboard; a code that can be mis-heard or mis-copied is a support
 * conversation between two people who are trying to be romantic.
 */
export const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

export const CODE_LENGTH = 6;

/**
 * Rate limit on requestPairing, per caller uid.
 *
 * Reasoning: the legitimate ceiling is one person typing their partner's code
 * with a typo or three — five attempts an hour covers every honest evening.
 * For an enumerator it is hopeless: the code space is 31^6 ≈ 887M, so at five
 * probes an hour a guesser expects centuries per hit. Failed attempts consume
 * budget too, otherwise probing is free.
 */
export const RATE_LIMIT_MAX_REQUESTS = 5;
export const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // one hour

/** How many fresh codes to try before giving up on a pathological run. */
export const MAX_CODE_ATTEMPTS = 10;

/**
 * Cap on the denormalised display name copied onto a pairing request.
 *
 * Matches the bound the users rules enforce on `displayName`. The value is
 * user-controlled and this document is read by *the other person*, so it is
 * untrusted content crossing a trust boundary — bound it here rather than
 * trusting that the rules were the only way it could have been written.
 */
export const MAX_DENORMALISED_NAME = 40;

/** Cap on the denormalised avatar URL, matching the users rules. */
export const MAX_DENORMALISED_AVATAR = 512;

/**
 * Shown when a sender has no usable display name. Rules require a non-empty
 * one, so this is the corrupted-or-legacy path; render something rather than
 * an empty bubble where a person's name should be.
 */
export const FALLBACK_SENDER_NAME = "Someone";

/** Clamps an untrusted string field, or returns null if it is unusable. */
export function boundedString(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed === "") return null;
  return trimmed.length > max ? trimmed.slice(0, max) : trimmed;
}

/** Thrown internally when a generated code already exists; triggers a retry. */
class CodeCollision extends Error {}

/** One random code. RNG injectable so tests can force collisions. */
export function generateCode(
  randomInt: (max: number) => number = (max) => crypto.randomInt(max),
): string {
  let code = "";
  for (let i = 0; i < CODE_LENGTH; i++) {
    code += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  }
  return code;
}

/**
 * Claims a unique code for `uid` and writes it to their profile. Idempotent:
 * if the profile already carries a code, that code is returned untouched.
 *
 * The claim uses create semantics inside a transaction — a collision fails the
 * attempt rather than overwriting the existing owner, and a fresh code is
 * tried, capped at MAX_CODE_ATTEMPTS.
 */
export async function claimPairingCode(
  db: Firestore,
  uid: string,
  generate: () => string = generateCode,
): Promise<string> {
  const userRef = db.doc(`users/${uid}`);

  for (let attempt = 0; attempt < MAX_CODE_ATTEMPTS; attempt++) {
    const code = generate();
    try {
      return await db.runTransaction(async (t) => {
        const userSnap = await t.get(userRef);
        if (!userSnap.exists) {
          throw new HttpsError(
            "failed-precondition",
            "No profile document. Sign in on a device first.",
            { reason: "profile-missing" },
          );
        }
        const user = userSnap.data() ?? {};
        if (user.coupleId != null) {
          throw new HttpsError(
            "failed-precondition",
            "Already paired — a paired account has no code.",
            { reason: "caller-already-paired" },
          );
        }
        // Idempotency, checked inside the transaction so a concurrent call
        // cannot leave one user holding two codes.
        if (typeof user.pairingCode === "string" && user.pairingCode !== "") {
          return user.pairingCode;
        }

        const codeRef = db.doc(`pairingCodes/${code}`);
        const codeSnap = await t.get(codeRef);
        if (codeSnap.exists) throw new CodeCollision();

        t.create(codeRef, {
          ownerId: uid,
          createdAt: FieldValue.serverTimestamp(),
        });
        t.update(userRef, { pairingCode: code });
        return code;
      });
    } catch (error) {
      if (error instanceof CodeCollision) continue;
      throw error;
    }
  }

  throw new HttpsError(
    "resource-exhausted",
    "Could not find a free code. Try again.",
    { reason: "code-space-contention" },
  );
}

/** P2-08 — returns the caller's pairing code, creating one if needed. */
export const ensurePairingCode = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (uid == null) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  const code = await claimPairingCode(getFirestore(), uid);
  return { code };
});

/**
 * Consumes one unit of the caller's request budget, or rejects.
 *
 * Runs in its own transaction *before* any validation, deliberately:
 * - failed probes are not free — invalid codes still spend budget;
 * - once the budget is gone, the caller sees the same resource-exhausted
 *   error whether the code they sent exists or not, so a rate-limited
 *   enumerator gets no oracle at all.
 *
 * A fixed window, not sliding: simpler to reason about, and the cap is small
 * enough that the burst-at-window-edge weakness is irrelevant here.
 */
async function spendRequestBudget(db: Firestore, uid: string): Promise<void> {
  const ref = db.doc(`rateLimits/${uid}`);
  await db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    const now = Timestamp.now();

    let count = 0;
    let windowStart = now;
    if (snap.exists) {
      const data = snap.data() ?? {};
      const startedAt = data.windowStart as Timestamp | undefined;
      const inWindow =
        startedAt != null &&
        now.toMillis() - startedAt.toMillis() < RATE_LIMIT_WINDOW_MS;
      if (inWindow) {
        count = (data.count as number) ?? 0;
        windowStart = startedAt;
      }
    }

    if (count >= RATE_LIMIT_MAX_REQUESTS) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many attempts. Try again later.",
        { reason: "rate-limited" },
      );
    }

    t.set(ref, { windowStart, count: count + 1 });
  });
}

/**
 * P2-09 — creates a pending pairing request.
 *
 * Success returns { requestId } and nothing else: per P2-23, the sender learns
 * nothing about the code's owner until the owner accepts.
 *
 * Every rejection carries a distinct machine-readable `details.reason`; the
 * gRPC code space is too small to give all six cases unique codes.
 */
export const requestPairing = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (uid == null) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }

  const rawCode = request.data?.code;
  if (typeof rawCode !== "string") {
    throw new HttpsError("invalid-argument", "Send a code.", {
      reason: "code-malformed",
    });
  }
  const code = rawCode.trim().toUpperCase();
  if (code.length !== CODE_LENGTH) {
    throw new HttpsError("invalid-argument", "Codes are six characters.", {
      reason: "code-malformed",
    });
  }

  const db = getFirestore();

  // Budget first — see spendRequestBudget for why.
  await spendRequestBudget(db, uid);

  const requestRef = db.collection("pairingRequests").doc();
  await db.runTransaction(async (t) => {
    const callerSnap = await t.get(db.doc(`users/${uid}`));
    if (callerSnap.exists && callerSnap.data()?.coupleId != null) {
      throw new HttpsError("failed-precondition", "You are already paired.", {
        reason: "caller-already-paired",
      });
    }

    const codeSnap = await t.get(db.doc(`pairingCodes/${code}`));
    if (!codeSnap.exists) {
      throw new HttpsError("not-found", "That code does not match anyone.", {
        reason: "code-not-found",
      });
    }
    const ownerId = codeSnap.data()?.ownerId as string;

    if (ownerId === uid) {
      throw new HttpsError(
        "invalid-argument",
        "That is your own code. Share it with your person instead.",
        { reason: "self-pairing" },
      );
    }

    // Defensive: P2-09b deletes both codes atomically on accept, so a paired
    // owner with a live code should not exist. Belt and braces.
    const ownerSnap = await t.get(db.doc(`users/${ownerId}`));
    if (ownerSnap.exists && ownerSnap.data()?.coupleId != null) {
      throw new HttpsError(
        "failed-precondition",
        "That code does not match anyone.",
        { reason: "owner-already-paired" },
      );
    }

    const duplicate = await t.get(
      db
        .collection("pairingRequests")
        .where("fromUid", "==", uid)
        .where("toUid", "==", ownerId)
        .where("status", "==", "pending")
        .limit(1),
    );
    if (!duplicate.empty) {
      throw new HttpsError(
        "already-exists",
        "You already asked. They will see it.",
        { reason: "request-already-pending" },
      );
    }

    // Denormalised so the recipient can render who is asking (P2-25) without
    // a rule that lets anyone read anyone's profile. `callerSnap` was already
    // read above for the already-paired check, so this costs no extra read.
    //
    // SNAPSHOT SEMANTICS, INTENDED: this is the name the sender had at the
    // moment they asked. If they rename themselves afterwards the recipient
    // still sees the old name. That is the honest thing to show — it is what
    // the request was sent under — so do not "fix" it by resolving live.
    const caller = callerSnap.data() ?? {};

    t.create(requestRef, {
      fromUid: uid,
      toUid: ownerId,
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
      fromDisplayName:
        boundedString(caller.displayName, MAX_DENORMALISED_NAME) ??
        FALLBACK_SENDER_NAME,
      fromAvatarUrl: boundedString(caller.avatarUrl, MAX_DENORMALISED_AVATAR),
    });
  });

  return { requestId: requestRef.id };
});

/** P2-09c — sender withdraws a pending request. Supports the P2-24 UI. */
export const cancelPairingRequest = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (uid == null) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }

  const requestId = request.data?.requestId;
  if (typeof requestId !== "string" || requestId === "") {
    throw new HttpsError("invalid-argument", "Send a requestId.", {
      reason: "request-id-malformed",
    });
  }

  const db = getFirestore();
  await db.runTransaction(async (t) => {
    const ref = db.doc(`pairingRequests/${requestId}`);
    const snap = await t.get(ref);
    if (!snap.exists) {
      throw new HttpsError("not-found", "No such request.", {
        reason: "request-not-found",
      });
    }
    const data = snap.data() ?? {};
    if (data.fromUid !== uid) {
      throw new HttpsError("permission-denied", "Not your request.", {
        reason: "not-sender",
      });
    }
    if (data.status !== "pending") {
      throw new HttpsError(
        "failed-precondition",
        "That request is already settled.",
        { reason: "request-not-pending" },
      );
    }
    t.update(ref, { status: "cancelled" });
  });

  return { cancelled: true };
});

/** Status written when a request dies without being accepted. */
const STATUS_EXPIRED = "expired";

/**
 * Every pending request touching `uid`, in either direction.
 *
 * Four queries rather than one `Filter.or`: each is a plain two-field equality
 * that the composite indexes already cover, and the union is computed here.
 */
function pendingRequestQueries(db: Firestore, uid: string) {
  const requests = db.collection("pairingRequests");
  return [
    requests.where("fromUid", "==", uid).where("status", "==", "pending"),
    requests.where("toUid", "==", uid).where("status", "==", "pending"),
  ];
}

/**
 * P2-09b — the accept transaction, and the decline that shares its guards.
 *
 * Everything the accept does is one transaction: create the couple, stamp
 * `coupleId` on both users, settle this request, expire every other pending
 * request either user is involved in, and destroy both pairing codes.
 */
export const respondToPairing = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (uid == null) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }

  const requestId = request.data?.requestId;
  if (typeof requestId !== "string" || requestId === "") {
    throw new HttpsError("invalid-argument", "Send a requestId.", {
      reason: "request-id-malformed",
    });
  }
  const accept = request.data?.accept;
  if (typeof accept !== "boolean") {
    throw new HttpsError("invalid-argument", "Send accept as a boolean.", {
      reason: "accept-malformed",
    });
  }

  // **P2-40 / Q3.** The couple's timezone, taken from the accepting partner's
  // device — one shared zone, because a streak is a couple-level fact and two
  // devices evaluating their own midnights would show the same relationship as
  // 47 and 46.
  //
  // Validated, never trusted: this feeds the day boundary P3-02 computes
  // against,
  // and `Intl` alone would accept a UTC offset like `+05:00`, which is the one
  // form Q3 rules out. An unrecognised or missing zone becomes null rather than
  // an error — see normaliseTimezone for why failing the accept would be the
  // wrong trade.
  const timezone = normaliseTimezone(request.data?.timezone);

  const db = getFirestore();
  const requestRef = db.doc(`pairingRequests/${requestId}`);

  if (!accept) {
    await db.runTransaction(async (t) => {
      const snap = await t.get(requestRef);
      if (!snap.exists) {
        throw new HttpsError("not-found", "No such request.", {
          reason: "request-not-found",
        });
      }
      const data = snap.data() ?? {};
      if (typeof data.fromUid !== "string" || data.fromUid === "") {
        throw new HttpsError("failed-precondition", "Malformed request.", {
          reason: "request-malformed",
        });
      }
      if (data.toUid !== uid) {
        throw new HttpsError("permission-denied", "Not your request.", {
          reason: "not-recipient",
        });
      }
      if (data.status !== "pending") {
        throw new HttpsError(
          "failed-precondition",
          "That request is already settled.",
          { reason: "request-not-pending" },
        );
      }
      // 'expired', never 'rejected' — the sender can read their own request,
      // and PI-05 forbids telling them a person refused. Never 'cancelled'
      // either: P2-09c owns that, so a sender who did not cancel would infer
      // a decline from it.
      //
      // No settledAt on this path, deliberately. A timestamp would be a
      // timing oracle: 'expired' seven days after createdAt is P2-28's sweep,
      // but 'expired' twenty minutes after is a person having decided —
      // exactly the fact PI-05 exists to withhold. A sender watching with a
      // live listener still sees the moment it changes; that much is
      // unavoidable. Persisting the moment for a sender who was not watching
      // is not, so we do not.
      t.update(requestRef, { status: STATUS_EXPIRED });
    });
    return { accepted: false };
  }

  const coupleRef = db.collection("couples").doc();

  return await db.runTransaction(async (t) => {
    // ---- reads, all of them, before any write ----
    const requestSnap = await t.get(requestRef);
    if (!requestSnap.exists) {
      throw new HttpsError("not-found", "No such request.", {
        reason: "request-not-found",
      });
    }
    const requestData = requestSnap.data() ?? {};
    const senderId = requestData.fromUid;

    if (typeof senderId !== "string" || senderId === "") {
      throw new HttpsError("failed-precondition", "Malformed request.", {
        reason: "request-malformed",
      });
    }

    if (requestData.toUid !== uid) {
      throw new HttpsError("permission-denied", "Not your request.", {
        reason: "not-recipient",
      });
    }

    // requestPairing already refuses to create one of these, so reaching here
    // means a forged or corrupted document. Guard anyway: without it the
    // transaction below would happily write a couple whose memberIds are the
    // same uid twice, and every downstream "the other member" lookup would
    // resolve to the reader.
    if (senderId === uid) {
      throw new HttpsError(
        "failed-precondition",
        "You cannot pair with yourself.",
        {
          reason: "self-pairing",
        },
      );
    }

    const recipientRef = db.doc(`users/${uid}`);
    const senderRef = db.doc(`users/${senderId}`);
    const [recipientSnap, senderSnap] = await Promise.all([
      t.get(recipientRef),
      t.get(senderRef),
    ]);
    const recipient = recipientSnap.data() ?? {};
    const sender = senderSnap.data() ?? {};

    if (requestData.status !== "pending") {
      // Double tap: the first call already paired these two. Report the same
      // couple rather than throwing, so the second tap is a no-op and never a
      // second couple.
      const settled = requestData.coupleId as string | undefined;
      if (
        requestData.status === "accepted" &&
        settled != null &&
        recipient.coupleId === settled &&
        sender.coupleId === settled
      ) {
        return { accepted: true, coupleId: settled };
      }
      throw new HttpsError(
        "failed-precondition",
        "That request is already settled.",
        { reason: "request-not-pending" },
      );
    }

    if (recipient.coupleId != null) {
      throw new HttpsError("failed-precondition", "You are already paired.", {
        reason: "caller-already-paired",
      });
    }
    // They paired with someone else while this request sat waiting.
    if (sender.coupleId != null) {
      throw new HttpsError(
        "failed-precondition",
        "They have already paired with someone.",
        { reason: "sender-already-paired" },
      );
    }

    // Every other pending request either person is party to. Read now, write
    // later — Firestore forbids a read after the first write in a transaction.
    //
    // WARNING: this sweep is load-bearing for correctness, not just cleanup.
    // Pulling these documents into the transaction's read set is what makes
    // concurrent accepts contend and abort the loser. Sabotage testing during
    // P2-18 confirmed it: with the already-paired preconditions removed but
    // this
    // sweep intact, races 1 and 2 still passed. With the sweep also removed,
    // race 1 produced two couples at round 0.
    // Do not move this to a post-transaction cleanup for efficiency without
    // replacing the contention it provides. See STATUS P2-18.
    const staleSnaps = await Promise.all(
      [
        ...pendingRequestQueries(db, uid),
        ...pendingRequestQueries(db, senderId),
      ].map((query) => t.get(query)),
    );

    // ---- writes ----
    // Denormalised so each partner can render the other's name (**M-02**)
    // without a rule that lets anyone read anyone's profile — the same trade
    // P2-25 made for `fromDisplayName`, and `couples` is already members-only.
    // Both documents are already loaded above for the already-paired checks,
    // so this costs no extra read.
    //
    // Untrusted content on the same terms: these strings are user-controlled
    // and cross to the other person's screen, so they are bounded and
    // defaulted here rather than trusted.
    //
    // SNAPSHOT SEMANTICS, as with fromDisplayName: a later rename does not
    // propagate. Accepted for now — see the debt entry; the fix belongs with
    // whatever task lets someone edit their display name, which does not
    // exist yet.
    const memberNames: Record<string, string> = {
      [senderId]:
        boundedString(sender.displayName, MAX_DENORMALISED_NAME) ??
        FALLBACK_SENDER_NAME,
      [uid]:
        boundedString(recipient.displayName, MAX_DENORMALISED_NAME) ??
        FALLBACK_SENDER_NAME,
    };

    t.create(coupleRef, {
      memberIds: [senderId, uid],
      memberNames,
      coupleName: null,
      // Owner decision, made: **default to the pairing date** (M-10).
      //
      // A couple joining today has a real anniversary the app cannot know, and
      // asking for it during pairing adds friction to the flow brief §11 calls
      // the single most important metric. So default now, edit later —
      // **P2-39** owns the settings path, which has to be a callable because
      // no client may write `couples`.
      //
      // Same sentinel as `createdAt`, not a copy of it: every
      // `serverTimestamp()` in one commit resolves to the same instant, so
      // these two are equal by construction rather than by a read-back. There
      // is a test asserting exactly that, because "by construction" is a claim
      // and not a proof.
      anniversaryDate: FieldValue.serverTimestamp(),
      streakCount: 0,
      lastStreakDate: null,
      // **Q3**, written by **P2-40**: one shared IANA zone from the accepting
      // partner's device. Null when the device could not name it or named
      // something invalid; P3-02 falls back rather than skipping the couple.
      timezone,
      createdAt: FieldValue.serverTimestamp(),
    });

    t.update(recipientRef, {
      coupleId: coupleRef.id,
      pairingCode: FieldValue.delete(),
    });
    t.update(senderRef, {
      coupleId: coupleRef.id,
      pairingCode: FieldValue.delete(),
    });

    t.update(requestRef, {
      status: "accepted",
      coupleId: coupleRef.id,
      settledAt: FieldValue.serverTimestamp(),
    });

    // Expire the rest, in both directions for both people. A request created
    // *during* this transaction will not appear in the reads above — Firestore
    // conflict detection covers documents read, not documents that appear
    // later. That is safe: a leftover 'pending' row pointing at a now-paired
    // user can never be accepted (both already-paired preconditions reject it)
    // and P2-28 sweeps it after 7 days. The invariant is upheld by the
    // preconditions, not by this cleanup.
    const settled = new Set<string>([requestRef.id]);
    for (const snapshot of staleSnaps) {
      for (const stale of snapshot.docs) {
        if (settled.has(stale.id)) continue;
        settled.add(stale.id);
        // Same reasoning as the decline path: no settledAt on an expiry.
        t.update(stale.ref, { status: STATUS_EXPIRED });
      }
    }

    // A paired person has no use for a code, and a live one is a stale invite
    // that can never be honoured.
    for (const code of [recipient.pairingCode, sender.pairingCode]) {
      if (typeof code === "string" && code !== "") {
        t.delete(db.doc(`pairingCodes/${code}`));
      }
    }

    return { accepted: true, coupleId: coupleRef.id };
  });
});
