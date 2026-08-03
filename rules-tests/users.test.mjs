// Firestore Security Rules tests for users/{uid} — part of P2-11.
//
// Requires the Firestore emulator on 8080 (`firebase emulators:start`).
// Run: cd rules-tests && npm test

import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, test } from "node:test";
import assert from "node:assert/strict";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  doc,
  getDoc,
  setDoc,
  deleteDoc,
  serverTimestamp,
  updateDoc,
} from "firebase/firestore";

const ALICE = "uid-alice";
const BOB = "uid-bob";

/** A well-formed profile, exactly the six keys the rules require. */
function profile(overrides = {}) {
  return {
    displayName: "Alice",
    avatarUrl: null,
    coupleId: null,
    favoriteEmojis: ["❤️", "😂"],
    accentColor: null,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    // Own namespace: node --test runs files in parallel, and a shared
    // project would let one file's clearFirestore() wipe another's seed.
    projectId: "onceling-rules-users",
    firestore: {
      host: "127.0.0.1",
      port: 8080,
      rules: readFileSync("../firestore.rules", "utf8"),
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

/** Seeds a document straight past the rules, so tests start from a real row. */
async function seedProfile(uid, data = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users", uid), {
      displayName: "Alice",
      avatarUrl: null,
      coupleId: null,
      favoriteEmojis: ["❤️"],
      accentColor: null,
      createdAt: new Date("2026-07-01T10:00:00Z"),
      ...data,
    });
  });
}

function unauthed() {
  return testEnv.unauthenticatedContext().firestore();
}

function db(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

describe("users/{uid} — read", () => {
  test("the owner can read their own document", async () => {
    await seedProfile(ALICE);
    await assertSucceeds(getDoc(doc(db(ALICE), "users", ALICE)));
  });

  test("another signed-in user cannot read it", async () => {
    await seedProfile(ALICE);
    await assertFails(getDoc(doc(db(BOB), "users", ALICE)));
  });

  test("a signed-out client cannot read it", async () => {
    await seedProfile(ALICE);
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, "users", ALICE)));
  });
});

describe("users/{uid} — create is closed (P2-35)", () => {
  // These are not vacuous: the closure IS the assertion. Field-shape checks
  // that used to live here would be — everything is denied now, so they would
  // pass with isWellFormedProfile deleted. They moved to the update block,
  // which still runs that validator, or were dropped where update has no
  // analogue.
  //
  // The profile is written only by the ensureUserProfile callable, which runs
  // with admin privileges. A client cannot compute the right coupleId for
  // someone a couple still lists — it can neither query couples nor write the
  // field — so it does not get to create the document at all.
  test("a perfectly valid profile is still rejected", async () => {
    await assertFails(setDoc(doc(db(ALICE), "users", ALICE), profile()));
  });

  test("not for someone else either", async () => {
    await assertFails(setDoc(doc(db(BOB), "users", ALICE), profile()));
  });

  test("and not by an unauthenticated caller", async () => {
    await assertFails(setDoc(doc(unauthed(), "users", ALICE), profile()));
  });
});

describe("users/{uid} — the coupleId invariant", () => {
  test("a user setting their own coupleId is REJECTED", async () => {
    await seedProfile(ALICE);
    await assertFails(
      updateDoc(doc(db(ALICE), "users", ALICE), { coupleId: "couple-1" }),
    );
  });

  test("a user CLEARING their coupleId is REJECTED", async () => {
    // An unrestricted clear orphans a couple: one partner paired to nobody,
    // the other paired to a ghost.
    await seedProfile(ALICE, { coupleId: "couple-1" });
    await assertFails(
      updateDoc(doc(db(ALICE), "users", ALICE), { coupleId: null }),
    );
  });

  test("a user changing coupleId to another couple is rejected", async () => {
    await seedProfile(ALICE, { coupleId: "couple-1" });
    await assertFails(
      updateDoc(doc(db(ALICE), "users", ALICE), { coupleId: "couple-2" }),
    );
  });

  test("editing displayName while coupleId is present and unchanged SUCCEEDS", async () => {
    // The passing case that stops an over-strict rule from silently breaking
    // profile edits.
    await seedProfile(ALICE, { coupleId: "couple-1" });
    await assertSucceeds(
      updateDoc(doc(db(ALICE), "users", ALICE), { displayName: "Alice B" }),
    );
  });

  test("editing displayName while unpaired succeeds", async () => {
    await seedProfile(ALICE);
    await assertSucceeds(
      updateDoc(doc(db(ALICE), "users", ALICE), { displayName: "Alice B" }),
    );
  });

  test("editing favourites succeeds", async () => {
    await seedProfile(ALICE);
    await assertSucceeds(
      updateDoc(doc(db(ALICE), "users", ALICE), {
        favoriteEmojis: ["🔥", "🫶"],
      }),
    );
  });
});

describe("users/{uid} — update guards", () => {
  test("another user cannot edit the document", async () => {
    await seedProfile(ALICE);
    await assertFails(
      updateDoc(doc(db(BOB), "users", ALICE), { displayName: "Owned" }),
    );
  });

  test("cannot rewrite createdAt", async () => {
    await seedProfile(ALICE);
    await assertFails(
      updateDoc(doc(db(ALICE), "users", ALICE), {
        createdAt: new Date("2020-01-01T00:00:00Z"),
      }),
    );
  });

  test("cannot add an unknown field on update", async () => {
    await seedProfile(ALICE);
    await assertFails(
      updateDoc(doc(db(ALICE), "users", ALICE), { isAdmin: true }),
    );
  });

  test("cannot break displayName type on update", async () => {
    await seedProfile(ALICE);
    await assertFails(
      updateDoc(doc(db(ALICE), "users", ALICE), { displayName: 42 }),
    );
  });

  // The three below moved from the create block when P2-35 closed it. They
  // exercise isWellFormedProfile, which still guards update — the only path a
  // client has into this document.
  test("cannot set an over-long displayName", async () => {
    await seedProfile(ALICE);
    await assertFails(
      updateDoc(doc(db(ALICE), "users", ALICE), {
        displayName: "x".repeat(41),
      }),
    );
  });

  test("cannot empty the displayName", async () => {
    await seedProfile(ALICE);
    await assertFails(
      updateDoc(doc(db(ALICE), "users", ALICE), { displayName: "" }),
    );
  });

  test("cannot exceed eight favourites", async () => {
    await seedProfile(ALICE);
    await assertFails(
      updateDoc(doc(db(ALICE), "users", ALICE), {
        favoriteEmojis: Array(9).fill("❤️"),
      }),
    );
  });
});

describe("users/{uid} — delete", () => {
  test("nobody can delete a profile, not even the owner", async () => {
    await seedProfile(ALICE);
    await assertFails(deleteDoc(doc(db(ALICE), "users", ALICE)));
  });
});

describe("collections with no rules yet", () => {
  test("are closed by the catch-all deny", async () => {
    await assertFails(getDoc(doc(db(ALICE), "couples", "couple-1")));
    await assertFails(
      setDoc(doc(db(ALICE), "pairingCodes", "ABC123"), { uid: ALICE }),
    );
    await assertFails(setDoc(doc(db(ALICE), "items", "i1"), { body: "hi" }));
  });
});

describe("sanity", () => {
  test("the rules file compiled", () => {
    assert.ok(testEnv, "test environment initialised, so the rules parsed");
  });
});

describe("PI-02 — onboardingSeenAt is server-owned", () => {
  test("a client cannot set it", async () => {
    await seedProfile(ALICE);
    await assertFails(
      updateDoc(doc(db(ALICE), "users", ALICE), {
        onboardingSeenAt: new Date(),
      }),
    );
  });

  test("a client cannot clear or move it once the server has stamped it", async () => {
    await seedProfile(ALICE);
    await testEnv.withSecurityRulesDisabled((c) =>
      updateDoc(doc(c.firestore(), "users", ALICE), {
        onboardingSeenAt: new Date("2026-08-01T00:00:00Z"),
      }),
    );

    await assertFails(
      updateDoc(doc(db(ALICE), "users", ALICE), { onboardingSeenAt: null }),
    );
    await assertFails(
      updateDoc(doc(db(ALICE), "users", ALICE), {
        onboardingSeenAt: new Date("2026-09-01T00:00:00Z"),
      }),
    );
  });

  test("a stamped profile can still be edited — the field rides along", async () => {
    // The half that would have broken silently. isWellFormedProfile runs on
    // UPDATE, so a server-written key missing from hasOnly would reject every
    // legitimate displayName edit for every user who has completed onboarding
    // — which, once PI-02 ships, is everyone.
    await seedProfile(ALICE);
    await testEnv.withSecurityRulesDisabled((c) =>
      updateDoc(doc(c.firestore(), "users", ALICE), {
        onboardingSeenAt: new Date("2026-08-01T00:00:00Z"),
      }),
    );

    await assertSucceeds(
      updateDoc(doc(db(ALICE), "users", ALICE), { displayName: "Alice B" }),
    );
  });
});

describe("P3-04 — pushToken is client-owned", () => {
  test("the owner can set it", async () => {
    await seedProfile(ALICE);
    await assertSucceeds(
      updateDoc(doc(db(ALICE), "users", ALICE), {
        pushToken: "fcm-token-abc",
        pushTokenUpdatedAt: serverTimestamp(),
      }),
    );
  });

  test("the owner can CLEAR it — this is sign-out", async () => {
    // The case that matters: a stale token keeps delivering a couple's
    // notifications to a handset somebody else may now be holding.
    await seedProfile(ALICE, { pushToken: "fcm-token-abc" });
    await assertSucceeds(
      updateDoc(doc(db(ALICE), "users", ALICE), { pushToken: null }),
    );
  });

  test("the owner can REPLACE it — this is rotation", async () => {
    await seedProfile(ALICE, { pushToken: "old" });
    await assertSucceeds(
      updateDoc(doc(db(ALICE), "users", ALICE), { pushToken: "new" }),
    );
  });

  test("nobody can write another person's token", async () => {
    await seedProfile(ALICE);
    await assertFails(
      updateDoc(doc(db(BOB), "users", ALICE), { pushToken: "hijack" }),
    );
  });

  test("an absurd token is rejected", async () => {
    await seedProfile(ALICE);
    await assertFails(
      updateDoc(doc(db(ALICE), "users", ALICE), {
        pushToken: "x".repeat(5000),
      }),
    );
    await assertFails(
      updateDoc(doc(db(ALICE), "users", ALICE), { pushToken: 42 }),
    );
  });

  test("a profile carrying a token can still be edited", async () => {
    // Same trap as onboardingSeenAt: isWellFormedProfile runs on UPDATE, so a
    // field missing from hasOnly breaks every unrelated edit.
    await seedProfile(ALICE, { pushToken: "fcm-token-abc" });
    await assertSucceeds(
      updateDoc(doc(db(ALICE), "users", ALICE), { displayName: "Alice B" }),
    );
  });
});
