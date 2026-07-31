import * as crypto from "node:crypto";

import { getApps, initializeApp } from "firebase-admin/app";
import {
  FieldValue,
  Firestore,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

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

    t.create(requestRef, {
      fromUid: uid,
      toUid: ownerId,
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
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
