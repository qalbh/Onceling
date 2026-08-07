import { getApps, initializeApp } from "firebase-admin/app";
import {
  FieldValue,
  Firestore,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

if (getApps().length === 0) initializeApp();

/**
 * The couple's photo prefix in Cloud Storage (**P2-13**).
 *
 * **Mirrors `PhotoUploadService.pathFor` in the Dart client.** Dart and
 * TypeScript cannot share a constant, so this is a hand-kept mirror in the same
 * shape as the `pairingCodeAlphabet` and item-payload mirrors already recorded
 * as D-17. If they drift, photos survive erasure — which is the one failure
 * this whole path exists to prevent.
 *
 * @param {string} coupleId the couple
 * @return {string} the object prefix, with a trailing slash
 */
export function photoPrefix(coupleId: string): string {
  return `couples/${coupleId}/photos/`;
}

/**
 * Deletes every Storage object belonging to a couple.
 *
 * **By prefix, not by walking items and deleting each `mediaUrl`.** That
 * distinction is the entire point. An upload that succeeded while its item
 * write failed leaves an object no document references (see
 * `PhotoUploadService` for why that ordering is the safer one) — and an
 * item-driven deletion would visit exactly the objects that are NOT orphans,
 * missing the whole orphan set. A prefix delete removes linked and orphaned
 * objects alike.
 *
 * Failures are logged and swallowed rather than thrown. This runs inside the
 * sweep, and a Storage outage must not stop the Firestore erasure that is
 * already in progress; the couple document stays until the end, so a failed
 * pass is discoverable and the trigger's `retry: true` runs it again.
 *
 * @param {string} coupleId the couple whose photos to erase
 * @return {Promise<number>} how many objects were deleted
 */
export async function sweepCouplePhotos(coupleId: string): Promise<number> {
  try {
    const bucket = getStorage().bucket();
    const [files] = await bucket.getFiles({ prefix: photoPrefix(coupleId) });
    await Promise.all(files.map((file) => file.delete()));
    return files.length;
  } catch (err) {
    console.error(`[P2-13] photo sweep failed for ${coupleId}: ${err}`);
    return 0;
  }
}

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
): Promise<{ items: number; photos: number }> {
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

  // Photos, before the couple document and after the items.
  //
  // **Before the couple document** for the same reason everything else is:
  // that document is the completion marker, and deleting it while objects
  // remain would strand them with nothing to drive a retry. Brief §10 and Q5
  // promise erasure, not erasure-of-the-database — a bucket full of a couple's
  // photographs after they have asked to be forgotten is the same broken
  // promise as leaving the rows.
  const photos = await sweepCouplePhotos(coupleId);

  // Last, so an interrupted sweep stays discoverable and resumable.
  await db.doc(`couples/${coupleId}`).delete();
  return { items: deleted, photos };
}

/** How long a couple may sit `unpaired` before the backstop assumes the
 *  trigger's retries have failed (**P2-38**). One hour: a normal sweep
 *  completes in seconds (batches of 150 over a two-person thread), so an hour
 *  is two orders of magnitude past any live run — this cannot fire on a sweep
 *  still working. And if a pathological retry IS still limping along,
 *  `sweepCouple` is idempotent, so overlap wastes reads rather than
 *  corrupting anything: the threshold prevents pointless double work, not
 *  disaster. */
export const BACKSTOP_THRESHOLD_MS = 3_600_000;

/** Stuck couples examined per backstop pass. */
export const BACKSTOP_BATCH = 25;

/**
 * **P2-38** — the backstop for couples stuck at `status: 'unpaired'`.
 *
 * **P2-36**'s sweep is trigger-driven with retries; if they exhaust, the
 * couple sits marked unpaired with its data intact and nobody looking — Q5's
 * promise quietly failing. The couple document is the work queue (`unpaired`
 * means unfinished, deletion is the completion marker), so finding the stuck
 * ones is one query.
 *
 * **Calls [sweepCouple] — the same function the trigger calls, not a second
 * implementation.** Two deletion paths that must agree is how they stop
 * agreeing; this way there is exactly one definition of "everything", and the
 * backstop cannot drift from the primary because there is nothing to drift.
 *
 * **Every firing is logged loudly.** A backstop that runs silently tells you
 * nothing about how often the primary fails, and that frequency is the number
 * worth knowing: zero means the trigger is healthy, anything else is a bug
 * report with a couple id in it.
 *
 * @param {Firestore} db the admin handle
 * @param {Date} now the current instant
 * @return {Promise<{swept: number}>} how many stuck couples were finished
 */
export async function sweepStuckCouples(
  db: Firestore,
  now: Date = new Date(),
): Promise<{ swept: number }> {
  const cutoff = Timestamp.fromMillis(now.getTime() - BACKSTOP_THRESHOLD_MS);

  // INDEX: couples — status ASC + unpairedAt ASC. Declared in
  // firestore.indexes.json; the emulator does not enforce it (D-10), so it
  // must be verified against dev on the next deploy.
  const stuck = await db
    .collection("couples")
    .where("status", "==", "unpaired")
    .where("unpairedAt", "<=", cutoff)
    .limit(BACKSTOP_BATCH)
    .get();

  let swept = 0;
  for (const doc of stuck.docs) {
    try {
      const result = await sweepCouple(db, doc.id);
      swept++;
      console.warn(
        `[P2-38] BACKSTOP fired: couple ${doc.id} was stuck unpaired since ` +
          `${doc.data().unpairedAt?.toDate?.()?.toISOString?.() ?? "?"} — ` +
          `the trigger's retries failed. Swept ${result.items} item(s) and ` +
          `${result.photos} photo(s). If this fires often, the primary sweep ` +
          "is broken, not busy.",
      );
    } catch (err) {
      // The next hourly pass retries; the couple document is still there to
      // find, which is exactly why sweepCouple deletes it last.
      console.error(`[P2-38] backstop failed for ${doc.id}: ${err}`);
    }
  }

  return { swept };
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
        `secret bodies deleted, ${result.photos} photo(s) removed from ` +
        "Storage, couple document removed.",
    );
  },
);
