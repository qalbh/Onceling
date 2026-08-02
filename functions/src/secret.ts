import { getApps, initializeApp } from "firebase-admin/app";
import {
  FieldValue,
  Firestore,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

if (getApps().length === 0) initializeApp();

/**
 * The longest any reveal session may last, in seconds.
 *
 * Mirrors the `revealDurationSeconds <= 3600` cap in `firestore.rules`, so the
 * invariant is uniform: **no reveal session outlasts an hour**, whatever
 * duration was chosen.
 *
 * This is what bounds `untilClosed`. Those secrets carry no
 * `revealDurationSeconds` at all, so there is no per-item clock to expire them
 * — without a ceiling, a reader who never closes the screen leaves a readable
 * body on the server indefinitely, which is precisely the retention brief §10
 * promises against. The ceiling is enforced twice: here, and in the rule, so
 * the body stops being readable at the hour mark rather than whenever the
 * sweep next happens to run.
 */
export const MAX_REVEAL_SESSION_SECONDS = 3600;

/**
 * Extra time past a window's true end before the sweep will touch it.
 *
 * The sweep must never race a live reveal. A recipient whose countdown is
 * still running has a body the rule still permits them to read, and completing
 * it underneath them would delete the text mid-sentence. Five minutes is far
 * beyond any clock skew between a device and the server, and the cost of
 * waiting is only that an abandoned secret lingers a few minutes longer while
 * already being unreadable.
 */
export const SWEEP_GRACE_SECONDS = 300;

/** Items examined per sweep pass. Each costs at most two writes. */
export const SWEEP_BATCH = 200;

type SecretState = "sealed" | "opening" | "opened";

interface ItemData {
  coupleId?: string;
  senderId?: string;
  type?: string;
  secretState?: SecretState;
  openingStartedAt?: Timestamp | null;
  revealDurationSeconds?: number | null;
}

/** The caller's couple, or null if they have no profile or are unpaired. */
async function coupleOf(
  db: Firestore,
  uid: string,
): Promise<string | null> {
  const snap = await db.doc(`users/${uid}`).get();
  return (snap.data()?.coupleId as string | null | undefined) ?? null;
}

/**
 * Shared preconditions for both transitions.
 *
 * Membership is checked against the item's `coupleId` rather than inferred, and
 * the sender is refused outright: a secret is for the recipient, once. Reading
 * your own back is the one thing `secretBodies` denies in the rules too, and
 * the two must agree or the callable becomes the way around the rule.
 */
function assertRecipient(item: ItemData, uid: string, coupleId: string | null) {
  if (item.type !== "secret") {
    throw new HttpsError("failed-precondition", "That is not a secret.", {
      reason: "not-a-secret",
    });
  }
  if (coupleId == null || item.coupleId !== coupleId) {
    throw new HttpsError("permission-denied", "Not your couple.", {
      reason: "not-a-member",
    });
  }
  if (item.senderId === uid) {
    throw new HttpsError(
      "permission-denied",
      "You cannot open your own secret.",
      { reason: "sender" },
    );
  }
}

/** Milliseconds a secret's window runs for, ceiling included. */
function windowMillis(item: ItemData): number {
  const seconds = item.revealDurationSeconds;
  if (typeof seconds === "number" && Number.isFinite(seconds)) {
    return Math.min(seconds, MAX_REVEAL_SESSION_SECONDS) * 1000;
  }
  // untilClosed — no per-item clock, so the ceiling is the whole bound.
  return MAX_REVEAL_SESSION_SECONDS * 1000;
}

/** True when the reveal window has already run out at [nowMs]. */
function isExpired(item: ItemData, nowMs: number): boolean {
  const startedAt = item.openingStartedAt;
  // An `opening` item with no start time cannot be reasoned about. The rule
  // fails it closed, and so does this: treat it as expired so the sweep
  // collects it rather than leaving it stranded forever.
  if (startedAt == null) return true;
  return nowMs >= startedAt.toMillis() + windowMillis(item);
}

/**
 * **P3-01, transition one** — `sealed -> opening`.
 *
 * Starts the read window. Nothing on a device can do this: item `update` is
 * restricted to the caller's own reaction key, so `secretState` is
 * server-only by construction.
 *
 * **Idempotent, and the shape of the idempotency matters.** Called again on a
 * secret already `opening` whose window is still running, it returns the
 * EXISTING `openingStartedAt` rather than stamping a new one. Restarting the
 * clock would extend the window, which is the one thing this must never do —
 * a recipient could hold a secret open indefinitely by re-calling it. The
 * client does re-call it, on a retry after a failed body read.
 */
export const beginReveal = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (uid == null) throw new HttpsError("unauthenticated", "Sign in first.");

  const itemId = request.data?.itemId;
  if (typeof itemId !== "string" || itemId === "") {
    throw new HttpsError("invalid-argument", "Which secret?", {
      reason: "item-id-missing",
    });
  }

  const db = getFirestore();
  const coupleId = await coupleOf(db, uid);
  const itemRef = db.doc(`items/${itemId}`);

  const outcome = await db.runTransaction(async (t) => {
    const snap = await t.get(itemRef);
    if (!snap.exists) {
      throw new HttpsError("not-found", "No such secret.", {
        reason: "item-not-found",
      });
    }
    const item = (snap.data() ?? {}) as ItemData;
    assertRecipient(item, uid, coupleId);

    if (item.secretState === "opened") {
      throw new HttpsError("failed-precondition", "Already opened.", {
        reason: "already-opened",
      });
    }

    if (item.secretState === "opening") {
      // The idempotent path. Expired is NOT idempotent-success: the body is
      // gone or about to be, and pretending otherwise would show the reader a
      // countdown for something they can no longer read.
      if (isExpired(item, Date.now())) {
        throw new HttpsError("failed-precondition", "That window closed.", {
          reason: "window-expired",
        });
      }
      return { restarted: false };
    }

    if (item.secretState !== "sealed") {
      throw new HttpsError("failed-precondition", "Not a sealed secret.", {
        reason: "not-sealed",
      });
    }

    t.update(itemRef, {
      secretState: "opening",
      openingStartedAt: FieldValue.serverTimestamp(),
    });
    return { restarted: true };
  });

  // Re-read so the caller gets the resolved server timestamp rather than a
  // sentinel. The client drives its countdown from this, so it must be the
  // server's value — the same clock the Security Rule compares against.
  const after = (await itemRef.get()).data() as ItemData;
  const startedAt = after.openingStartedAt;

  return {
    openingStartedAt: startedAt?.toMillis() ?? null,
    windowSeconds: Math.floor(windowMillis(after) / 1000),
    alreadyOpening: !outcome.restarted,
  };
});

/**
 * The `opening -> opened` transition, as one transaction.
 *
 * The body deletion and the state change are inseparable: a body deleted
 * without the state change leaves an item claiming to be openable with nothing
 * behind it, and a state change without the deletion leaves the text on the
 * server after the app has said it is gone. Q1 is hard delete — no retention,
 * no recoverable copy — so this is the only place the text ceases to exist.
 *
 * Shared by the callable and the sweep, which is what makes the transition
 * reachable without a client at all.
 *
 * Returns whether it did the work, so callers can tell a real completion from
 * an idempotent no-op.
 */
export async function completeRevealTransaction(
  db: Firestore,
  itemId: string,
  options: { uid?: string; coupleId?: string | null } = {},
): Promise<{ completed: boolean; alreadyOpened: boolean }> {
  const itemRef = db.doc(`items/${itemId}`);
  const bodyRef = db.doc(`secretBodies/${itemId}`);

  return await db.runTransaction(async (t) => {
    const snap = await t.get(itemRef);
    if (!snap.exists) {
      throw new HttpsError("not-found", "No such secret.", {
        reason: "item-not-found",
      });
    }
    const item = (snap.data() ?? {}) as ItemData;

    // Only when a caller is named. The sweep runs as nobody and must be able
    // to finish a reveal the recipient abandoned.
    if (options.uid != null) {
      assertRecipient(item, options.uid, options.coupleId ?? null);
    }

    if (item.secretState === "opened") {
      // Idempotent. The client calls this after the countdown and may call it
      // twice on a flaky connection; the sweep may reach one the client just
      // finished. Neither is an error.
      return { completed: false, alreadyOpened: true };
    }

    if (item.secretState !== "opening") {
      throw new HttpsError("failed-precondition", "That is not open.", {
        reason: "not-opening",
      });
    }

    // Derived here, never taken from the caller. The client knows whether the
    // ring emptied, but this is what the SENDER is told, and an app about
    // honesty should not let one side author the other side's notification.
    const startedAt = item.openingStartedAt;
    const heldFullCountdown =
      typeof item.revealDurationSeconds === "number" &&
      startedAt != null &&
      Date.now() - startedAt.toMillis() >=
        item.revealDurationSeconds * 1000;

    t.delete(bodyRef);
    t.update(itemRef, {
      secretState: "opened",
      openedAt: FieldValue.serverTimestamp(),
      heldFullCountdown,
    });
    return { completed: true, alreadyOpened: false };
  });
}

/**
 * **P3-01, transition two** — `opening -> opened`, recipient-driven.
 */
export const completeReveal = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (uid == null) throw new HttpsError("unauthenticated", "Sign in first.");

  const itemId = request.data?.itemId;
  if (typeof itemId !== "string" || itemId === "") {
    throw new HttpsError("invalid-argument", "Which secret?", {
      reason: "item-id-missing",
    });
  }

  const db = getFirestore();
  const coupleId = await coupleOf(db, uid);
  return await completeRevealTransaction(db, itemId, { uid, coupleId });
});

/**
 * **P3-01, the state nobody owns** — a secret left `opening` because the
 * recipient's phone died mid-reveal. Stored, unreadable by anyone once the
 * window passes, and undeleted, because neither transition fires when nobody
 * is there to fire it.
 *
 * **A schedule rather than folding it into an existing sweep.** There is no
 * existing schedule to fold into: **P2-28**'s request sweep is deferred and
 * unbuilt, and **P2-36**'s `sweepUnpairedCouple` is a document trigger, not a
 * timer — it fires on a couple reaching `status: 'unpaired'` and would never
 * see an abandoned reveal in a couple that is still together. Attaching this
 * to a trigger that has no reason to fire would mean the collection happens
 * only by luck.
 *
 * **It cannot race a live reveal.** Every item is checked against its own
 * deadline — `openingStartedAt` plus its own window plus
 * [SWEEP_GRACE_SECONDS] — rather than against one global cutoff, so a 10s
 * secret and a 30s secret are each judged on their own terms and neither is
 * touched while its countdown could still be running.
 *
 * **`untilClosed` is the sharp end, and it is handled here rather than
 * ignored.** Those secrets have no `revealDurationSeconds`, so a purely
 * time-based rule has nothing to expire them with. They are bounded by
 * [MAX_REVEAL_SESSION_SECONDS] instead — see that constant for why an
 * unbounded one breaks brief §10's promise outright.
 *
 * When P2-28 is built it can share this schedule; the two are both "collect
 * things nobody finished".
 */
export async function sweepExpiredReveals(
  db: Firestore,
  nowMs: number = Date.now(),
): Promise<{ examined: number; completed: number }> {
  const open = await db
    .collection("items")
    .where("secretState", "==", "opening")
    .limit(SWEEP_BATCH)
    .get();

  let completed = 0;
  for (const doc of open.docs) {
    const item = doc.data() as ItemData;
    const startedAt = item.openingStartedAt;
    const deadline =
      (startedAt?.toMillis() ?? 0) +
      windowMillis(item) +
      SWEEP_GRACE_SECONDS * 1000;
    // A missing start time has no deadline to compute; isExpired() already
    // treats it as expired, and the grace period above cannot rescue it.
    if (startedAt != null && nowMs < deadline) continue;

    try {
      const result = await completeRevealTransaction(db, doc.id);
      if (result.completed) completed++;
    } catch (err) {
      // One stuck item must not stop the pass. The likeliest cause is the
      // recipient completing it a moment earlier, which is a no-op anyway.
      console.warn(`[P3-01] sweep could not complete ${doc.id}: ${err}`);
    }
  }

  return { examined: open.size, completed };
}

/**
 * Every 10 minutes. Frequent enough that an abandoned body does not sit for
 * long, infrequent enough to be nearly free — and irrelevant to correctness,
 * because the Security Rule stops the body being readable at the window's end
 * whether or not the sweep has run yet. The sweep reclaims storage; the rule
 * is what enforces the promise.
 */
export const sweepExpiredRevealsScheduled = onSchedule(
  { schedule: "every 10 minutes", retryCount: 3 },
  async () => {
    const result = await sweepExpiredReveals(getFirestore());
    if (result.completed > 0) {
      console.log(
        `[P3-01] swept ${result.completed} abandoned reveal(s) of ` +
          `${result.examined} examined.`,
      );
    }
  },
);
