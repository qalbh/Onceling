// The pairing invariant, shared by P2-18's concurrency suite and P2-35's
// profile-recovery tests.
//
// One definition on purpose: this is the assertion the whole pairing model
// rests on, and two drifting copies would be worse than none.

import assert from 'node:assert/strict';

/**
 * Both directions, because a half-applied change breaks exactly one of them:
 *   - no user's coupleId points at a couple whose memberIds omit them;
 *   - no couple lists a member whose coupleId points somewhere else.
 *
 * `readAll` takes a collection name and returns [{id, ...data}].
 */
export async function assertPairingInvariant(readAll, label) {
  const [users, couples] = await Promise.all([
    readAll('users'),
    readAll('couples'),
  ]);
  const byId = new Map(couples.map((c) => [c.id, c]));

  for (const user of users) {
    if (user.coupleId == null) continue;
    const couple = byId.get(user.coupleId);
    assert.ok(
      couple != null,
      `${label}: user ${user.id} has coupleId ${user.coupleId} but no such couple exists`,
    );
    assert.ok(
      Array.isArray(couple.memberIds) && couple.memberIds.includes(user.id),
      `${label}: user ${user.id} points at couple ${couple.id} whose memberIds are ${JSON.stringify(couple.memberIds)}`,
    );
  }

  for (const couple of couples) {
    // A couple in `status: 'unpaired'` is P2-36 phase 1 complete and phase 2
    // not yet run: separation is atomic, deletion is a trigger that fires a
    // moment later. In that window the document legitimately lists two members
    // who no longer point back at it, which is not a broken invariant — it is
    // the two-phase design working.
    //
    // **This is D-14.** The intermittent one-off failure in this suite was a
    // race against `sweepUnpairedCouple`: if the sweep won, the couple was
    // gone and the check passed; if the test won, the check saw the
    // transitional state and failed. Same code, different outcome, which is
    // exactly how it presented. The transitional state still gets asserted —
    // skipping it outright would trade a flake for a blind spot.
    if (couple.status === 'unpaired') {
      for (const member of couple.memberIds ?? []) {
        const user = users.find((u) => u.id === member);
        // The point of unpair is that BOTH sides are freed together. One
        // cleared and one still bound is the orphan the transaction exists to
        // prevent, and it must fail here even mid-sweep.
        if (user != null) {
          assert.equal(
            user.coupleId,
            null,
            `${label}: couple ${couple.id} is unpaired but ${member} still has coupleId ${user.coupleId}`,
          );
        }
      }
      continue;
    }

    assert.ok(
      Array.isArray(couple.memberIds) && couple.memberIds.length === 2,
      `${label}: couple ${couple.id} has memberIds ${JSON.stringify(couple.memberIds)} — a couple is exactly two people`,
    );
    assert.equal(
      new Set(couple.memberIds).size,
      2,
      `${label}: couple ${couple.id} lists the same uid twice`,
    );
    for (const member of couple.memberIds) {
      const user = users.find((u) => u.id === member);
      assert.ok(
        user != null,
        `${label}: couple ${couple.id} lists unknown user ${member}`,
      );
      assert.equal(
        user.coupleId,
        couple.id,
        `${label}: couple ${couple.id} lists ${member}, whose coupleId is ${user.coupleId}`,
      );
    }
  }
}
