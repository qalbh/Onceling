import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, Firestore, getFirestore } from "firebase-admin/firestore";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

if (getApps().length === 0) initializeApp();

/** Marks a couple as separated but not yet swept. */
export const STATUS_UNPAIRED = "unpaired";

/** Documents deleted per batch by the sweep. Well under the 500 write cap,
 *  since each item costs two writes (the item and its secret body). */
export const SWEEP_BATCH = 150;

/**
 * **P2-36 phase 1** — separation, atomically.
 *
 * Split from the deletion (phase 2) on purpose. Separation must be atomic:
 * a half-applied unpair leaves one partner free and the other still bound,
 * which is the incoherent state `assertPairingInvariant` exists to catch.
 * Deletion only has to be *reliable*, and doing both here would risk a
 * timeout on a couple with real history and leave orphaned data behind.
 *
 * When this returns, both users are separated. That is the guarantee. The
 * data goes away afterwards, driven by the status written here.
 *
 * Codes are deliberately not reissued: both users land on the pairing screen
 * and `ensurePairingCode` claims a fresh one, which is already idempotent.
 */
export const unpair = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (uid == null) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }

  const db = getFirestore();

  return await db.runTransaction(async (t) => {
    const userRef = db.doc(`users/${uid}`);
    const userSnap = await t.get(userRef);
    if (!userSnap.exists) {
      throw new HttpsError("failed-precondition", "No profile document.", {
        reason: "profile-missing",
      });
    }

    const coupleId = userSnap.data()?.coupleId as string | null | undefined;

    // Idempotent: nothing to separate. A second tap, or a partner who was
    // already cleared by the other side's call, lands here.
    if (coupleId == null) {
      return { coupleId: null, alreadyUnpaired: true };
    }

    const coupleRef = db.doc(`couples/${coupleId}`);
    const coupleSnap = await t.get(coupleRef);
    if (!coupleSnap.exists) {
      // Their coupleId points at nothing. Refuse rather than clear it blindly:
      // this is already broken, and silently "fixing" it would destroy the
      // evidence that something upstream went wrong.
      throw new HttpsError("failed-precondition", "That couple is missing.", {
        reason: "couple-missing",
      });
    }

    const members = (coupleSnap.data()?.memberIds ?? []) as string[];
    if (!members.includes(uid)) {
      throw new HttpsError(
        "permission-denied",
        "You are not part of that couple.",
        { reason: "not-a-member" },
      );
    }

    // Clear BOTH sides in the same transaction. Clearing only the caller is
    // exactly the orphan CLAUDE.md warns about: an unrestricted clear is as
    // dangerous as an unrestricted set.
    const partnerRefs = members
      .filter((member) => member !== uid)
      .map((member) => db.doc(`users/${member}`));

    // All reads before any write.
    const partnerSnaps = await Promise.all(
      partnerRefs.map((ref) => t.get(ref)),
    );

    t.update(userRef, { coupleId: null });
    for (let i = 0; i < partnerRefs.length; i++) {
      // A partner whose profile has vanished is not a reason to strand the
      // caller — separation still succeeds, and P2-35 restores that profile
      // with a coupleId query that will now find nothing.
      if (partnerSnaps[i].exists) {
        t.update(partnerRefs[i], { coupleId: null });
      }
    }

    // Already-unpaired couples are re-stamped rather than rejected: this is
    // the resume path when a previous call cleared the couple but not every
    // profile, and re-writing the same status is harmless.
    t.update(coupleRef, {
      status: STATUS_UNPAIRED,
      unpairedAt: FieldValue.serverTimestamp(),
      unpairedBy: uid,
    });

    return { coupleId, alreadyUnpaired: false };
  });
});

/**
 * **P2-36 phase 2** — destroy the couple's data. Q5: destroy, no export.
 *
 * Deletes in an order that is safe if interrupted:
 *   1. each item together with its secret body, in batches
 *   2. the couple document last
 *
 * **Why the couple document goes last.** It is the only handle on the data:
 * `items` are found by `coupleId`, so deleting the couple first would leave
 * orphans nothing points at. Leaving it until the end means an interrupted
 * sweep is discoverable — anything still `status: 'unpaired'` has unfinished
 * work — and re-runnable.
 *
 * **Why bodies and items go together rather than all-bodies-then-all-items.**
 * `secretBodies` are keyed by item id, so an item is the only way to find its
 * body. Deleting them in the same batch removes the window where an item is
 * gone and its body is unreachable; the phased order would open exactly that
 * window if it died between phases. Strictly stronger than "bodies first".
 *
 * Idempotent throughout: deleting an absent document is a no-op, so a retry
 * after partial completion finishes the job instead of failing.
 */
export async function sweepCouple(
  db: Firestore,
  coupleId: string,
): Promise<{ items: number }> {
  let deleted = 0;

  for (;;) {
    const items = await db
      .collection("items")
      .where("coupleId", "==", coupleId)
      .limit(SWEEP_BATCH)
      .get();
    if (items.empty) break;

    const batch = db.batch();
    for (const item of items.docs) {
      batch.delete(db.doc(`secretBodies/${item.id}`));
      batch.delete(item.ref);
    }
    await batch.commit();
    deleted += items.size;

    // A short page means the collection is drained; avoids one extra query.
    if (items.size < SWEEP_BATCH) break;
  }

  // Second pass: any secret body the item pass could not reach.
  //
  // Bodies are keyed by item id, so an item is normally the handle on its
  // body — but a body whose item is already gone is unreachable that way and
  // would survive erasure forever. That is not hypothetical: **P3-01** hard-
  // deletes bodies while keeping their items, and anything that ever deletes
  // an item without its body strands one.
  //
  // So `secretBodies` MUST carry `coupleId`, and **P2-12** must write it. This
  // pass is what makes "destroy, no export" actually true rather than
  // true-for-the-bodies-we-happen-to-find.
  for (;;) {
    const orphans = await db
      .collection("secretBodies")
      .where("coupleId", "==", coupleId)
      .limit(SWEEP_BATCH)
      .get();
    if (orphans.empty) break;

    const batch = db.batch();
    for (const body of orphans.docs) batch.delete(body.ref);
    await batch.commit();

    if (orphans.size < SWEEP_BATCH) break;
  }

  // Last, so an interrupted sweep stays discoverable and resumable.
  await db.doc(`couples/${coupleId}`).delete();
  return { items: deleted };
}

/**
 * Fires phase 2 when a couple reaches `status: 'unpaired'`.
 *
 * **A Firestore trigger rather than a schedule**, because the work is caused
 * by exactly one state change and should start immediately — a paired user who
 * has just asked for erasure should not wait for the next cron tick. The couple
 * document doubles as the work queue: `status: 'unpaired'` means unfinished,
 * and its deletion is the completion marker.
 *
 * `retry: true` so a transient failure re-runs; the sweep is idempotent, so a
 * retry resumes rather than duplicating work.
 *
 * The gap this leaves: a couple whose sweep fails past its retries stays
 * `'unpaired'` forever with nobody looking. A scheduled backstop that sweeps
 * any couple still in that state — sharing **P2-28**'s schedule — is the
 * natural companion, and is recorded as debt rather than built here.
 */
export const sweepUnpairedCouple = onDocumentUpdated(
  { document: "couples/{coupleId}", retry: true },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    // Only the transition into 'unpaired'. Re-stamping an already-unpaired
    // couple (the phase-1 resume path) must not start a second sweep.
    if (after?.status !== STATUS_UNPAIRED) return;
    if (before?.status === STATUS_UNPAIRED) return;

    const coupleId = event.params.coupleId;
    const result = await sweepCouple(getFirestore(), coupleId);
    console.log(
      `[P2-36] swept couple ${coupleId}: ${result.items} item(s) and their ` +
        `secret bodies deleted, couple document removed.`,
    );
  },
);
