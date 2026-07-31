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
