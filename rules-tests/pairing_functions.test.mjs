// Functions tests for the pairing callables (P2-08, P2-09, P2-09c, P2-27).
// Run: cd rules-tests && npm run test:functions   (emulator suite must be up,
// with build:watch keeping functions/lib/ fresh).

import { createRequire } from "node:module";
import { randomUUID } from "node:crypto";
import { after, before, beforeEach, describe, test } from "node:test";
import assert from "node:assert/strict";

import { initializeTestEnvironment } from "@firebase/rules-unit-testing";
import { deleteApp, initializeApp } from "firebase/app";
import {
  connectAuthEmulator,
  createUserWithEmailAndPassword,
  getAuth,
} from "firebase/auth";
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
} from "firebase/functions";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
} from "firebase/firestore";

import { assertPairingInvariant } from "./pairing_invariant.mjs";

// The compiled functions module, imported directly so the pure pieces
// (alphabet, generator, claim-with-retry) are testable without HTTP.
// Point the admin SDK it initialises at the emulator first.
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ??= "qalb-coupleapp-dev";
// Resolve from functions/ — firebase-admin is its dependency, not ours.
const requireFromFunctions = createRequire(
  new URL("../functions/package.json", import.meta.url),
);
const pairing = requireFromFunctions("./lib/pairing.js");
const { getFirestore } = requireFromFunctions("firebase-admin/firestore");
const profile = requireFromFunctions("./lib/profile.js");
const unpairModule = requireFromFunctions("./lib/unpair.js");
const adminDb = () => getFirestore();

const PROJECT = "qalb-coupleapp-dev";

let testEnv;
const apps = [];

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { host: "127.0.0.1", port: 8080 },
  });
});

after(async () => {
  await Promise.all(apps.map((app) => deleteApp(app)));
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

/** Fresh signed-in client app: auth user + functions handle wired in. */
async function newUser() {
  const app = initializeApp(
    { apiKey: "fake-api-key", projectId: PROJECT },
    `app-${randomUUID()}`,
  );
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
  const cred = await createUserWithEmailAndPassword(
    auth,
    `${randomUUID()}@onceling.test`,
    "hunter22",
  );
  const functions = getFunctions(app);
  connectFunctionsEmulator(functions, "127.0.0.1", 5001);
  return {
    uid: cred.user.uid,
    call: (name, data) => httpsCallable(functions, name)(data),
  };
}

/** Unauthenticated functions handle. */
function anonCaller() {
  const app = initializeApp(
    { apiKey: "fake-api-key", projectId: PROJECT },
    `anon-${randomUUID()}`,
  );
  apps.push(app);
  const functions = getFunctions(app);
  connectFunctionsEmulator(functions, "127.0.0.1", 5001);
  return (name, data) => httpsCallable(functions, name)(data);
}

/** Seeds a minimal users/{uid} document past the rules. */
async function seedProfile(uid, extra = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users", uid), {
      displayName: "Test",
      avatarUrl: null,
      coupleId: null,
      favoriteEmojis: [],
      accentColor: null,
      createdAt: new Date(),
      ...extra,
    });
  });
}

/** Runs `fn(db)` with rules disabled — ground truth, not the client's view. */
async function admin(fn) {
  let out;
  await testEnv.withSecurityRulesDisabled(async (context) => {
    out = await fn(context.firestore());
  });
  return out;
}

async function readDoc(path) {
  let data;
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const snap = await getDoc(doc(context.firestore(), path));
    data = snap.exists() ? snap.data() : undefined;
  });
  return data;
}

async function writeDoc(path, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
  });
}

async function expectCallableError(promise, code, reason) {
  try {
    await promise;
    assert.fail(`expected ${code} (${reason}), call succeeded`);
  } catch (error) {
    assert.equal(error.code, code, `code for ${reason}: ${error.message}`);
    if (reason != null) {
      assert.equal(error.details?.reason, reason, "details.reason");
    }
  }
}

describe("code generation (pure)", () => {
  test("the alphabet has no ambiguous characters", () => {
    for (const banned of ["0", "O", "1", "I", "L"]) {
      assert.ok(
        !pairing.CODE_ALPHABET.includes(banned),
        `alphabet must not contain ${banned}`,
      );
    }
  });

  test("generated codes stay inside the alphabet, at length 6", () => {
    for (let i = 0; i < 10_000; i++) {
      const code = pairing.generateCode();
      assert.equal(code.length, pairing.CODE_LENGTH);
      for (const char of code) {
        assert.ok(pairing.CODE_ALPHABET.includes(char), `bad char ${char}`);
      }
    }
  });
});

describe("ensurePairingCode", () => {
  test("repeated calls return the same code", async () => {
    const user = await newUser();
    await seedProfile(user.uid);

    const first = (await user.call("ensurePairingCode")).data.code;
    const second = (await user.call("ensurePairingCode")).data.code;

    assert.equal(first, second);
    assert.equal(first.length, 6);
    const profile = await readDoc(`users/${user.uid}`);
    assert.equal(profile.pairingCode, first);
    const claim = await readDoc(`pairingCodes/${first}`);
    assert.equal(claim.ownerId, user.uid);
  });

  test("collision retries onto a fresh code without disturbing the owner", async () => {
    const victim = await newUser();
    await seedProfile(victim.uid);
    await writeDoc("pairingCodes/AAAAAA", {
      ownerId: "someone-else",
      createdAt: new Date(),
    });

    // Force the generator to collide first, then produce a free code.
    const sequence = ["AAAAAA", "BBBBBB"];
    const code = await pairing.claimPairingCode(
      getFirestore(),
      victim.uid,
      () => sequence.shift() ?? "CCCCCC",
    );

    assert.equal(code, "BBBBBB");
    const original = await readDoc("pairingCodes/AAAAAA");
    assert.equal(
      original.ownerId,
      "someone-else",
      "collision must not overwrite",
    );
  });

  test("gives up with resource-exhausted after the attempt cap", async () => {
    const user = await newUser();
    await seedProfile(user.uid);
    await writeDoc("pairingCodes/DDDDDD", {
      ownerId: "someone-else",
      createdAt: new Date(),
    });

    await assert.rejects(
      pairing.claimPairingCode(getFirestore(), user.uid, () => "DDDDDD"),
      (error) => error.code === "resource-exhausted",
    );
  });

  test("refuses a paired caller", async () => {
    const user = await newUser();
    await seedProfile(user.uid, { coupleId: "couple-1" });
    await expectCallableError(
      user.call("ensurePairingCode"),
      "functions/failed-precondition",
      "caller-already-paired",
    );
  });
});

describe("requestPairing — the six rejections", () => {
  test("unauthenticated", async () => {
    const call = anonCaller();
    await expectCallableError(
      call("requestPairing", { code: "ABC234" }),
      "functions/unauthenticated",
      null,
    );
  });

  test("caller already paired", async () => {
    const user = await newUser();
    await seedProfile(user.uid, { coupleId: "couple-1" });
    await expectCallableError(
      user.call("requestPairing", { code: "ABC234" }),
      "functions/failed-precondition",
      "caller-already-paired",
    );
  });

  test("code does not exist", async () => {
    const user = await newUser();
    await seedProfile(user.uid);
    await expectCallableError(
      user.call("requestPairing", { code: "ZZZ999" }),
      "functions/not-found",
      "code-not-found",
    );
  });

  test("self-pairing", async () => {
    const user = await newUser();
    await seedProfile(user.uid);
    const code = (await user.call("ensurePairingCode")).data.code;
    await expectCallableError(
      user.call("requestPairing", { code }),
      "functions/invalid-argument",
      "self-pairing",
    );
  });

  test("owner already paired", async () => {
    const owner = await newUser();
    await seedProfile(owner.uid);
    const code = (await owner.call("ensurePairingCode")).data.code;
    // Pair the owner behind the scenes, leaving the code dangling.
    await seedProfile(owner.uid, { coupleId: "couple-1", pairingCode: code });

    const requester = await newUser();
    await seedProfile(requester.uid);
    await expectCallableError(
      requester.call("requestPairing", { code }),
      "functions/failed-precondition",
      "owner-already-paired",
    );
  });

  test("duplicate pending request to the same owner", async () => {
    const owner = await newUser();
    await seedProfile(owner.uid);
    const code = (await owner.call("ensurePairingCode")).data.code;

    const requester = await newUser();
    await seedProfile(requester.uid);
    await requester.call("requestPairing", { code });
    await expectCallableError(
      requester.call("requestPairing", { code }),
      "functions/already-exists",
      "request-already-pending",
    );
  });
});

describe("requestPairing — happy path", () => {
  test("creates exactly one pending document and returns only its id", async () => {
    const owner = await newUser();
    await seedProfile(owner.uid);
    const code = (await owner.call("ensurePairingCode")).data.code;

    const requester = await newUser();
    await seedProfile(requester.uid);
    const result = await requester.call("requestPairing", { code });

    assert.deepEqual(
      Object.keys(result.data),
      ["requestId"],
      "nothing but the id",
    );
    const request = await readDoc(`pairingRequests/${result.data.requestId}`);
    assert.equal(request.fromUid, requester.uid);
    assert.equal(request.toUid, owner.uid);
    assert.equal(request.status, "pending");
  });
});

describe("requestPairing — rate limit (P2-27)", () => {
  test("the cap triggers, and a VALID code gets the same error as an invalid one", async () => {
    const owner = await newUser();
    await seedProfile(owner.uid);
    const validCode = (await owner.call("ensurePairingCode")).data.code;

    const prober = await newUser();
    await seedProfile(prober.uid);

    // Spend the whole budget on garbage codes — failed probes are not free.
    for (let i = 0; i < 5; i++) {
      await expectCallableError(
        prober.call("requestPairing", { code: "ZZZ999" }),
        "functions/not-found",
        "code-not-found",
      );
    }

    // Over the cap: identical error whether the code is real or not.
    await expectCallableError(
      prober.call("requestPairing", { code: "ZZZ999" }),
      "functions/resource-exhausted",
      "rate-limited",
    );
    await expectCallableError(
      prober.call("requestPairing", { code: validCode }),
      "functions/resource-exhausted",
      "rate-limited",
    );
  });

  test("the budget resets once the window has passed", async () => {
    const user = await newUser();
    await seedProfile(user.uid);

    // A spent budget whose window started two hours ago.
    await writeDoc(`rateLimits/${user.uid}`, {
      windowStart: new Date(Date.now() - 2 * 60 * 60 * 1000),
      count: 5,
    });

    // Back under the cap: the stale window is discarded and the call gets
    // through to validation (not-found, because the code is garbage).
    await expectCallableError(
      user.call("requestPairing", { code: "ZZZ999" }),
      "functions/not-found",
      "code-not-found",
    );
  });
});

describe("ensureUserProfile (P2-30, P2-35)", () => {
  /** Every collection, as [{id, ...data}] — what the invariant check needs. */
  const readAll = (name) =>
    admin(async (db) => {
      const snap = await getDocs(collection(db, name));
      return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    });

  test("no couple: recreated unpaired, as before", async () => {
    const user = await newUser();
    const { data } = await user.call("ensureUserProfile", {});

    assert.equal(data.created, true);
    assert.equal(data.coupleId, null);
    assert.equal((await readDoc(`users/${user.uid}`)).coupleId, null);
    await assertPairingInvariant(readAll, "recovery, unpaired");
  });

  test("in a couple: coupleId is restored, not nulled", async () => {
    const user = await newUser();
    const partner = await newUser();
    await seedProfile(partner.uid, { coupleId: "C1" });
    await writeDoc("couples/C1", {
      memberIds: [user.uid, partner.uid],
      streakCount: 0,
      createdAt: new Date(),
    });

    // The profile is absent — the P2-35 state exactly.
    const { data } = await user.call("ensureUserProfile", {});

    assert.equal(data.coupleId, "C1");
    assert.equal((await readDoc(`users/${user.uid}`)).coupleId, "C1");
    // The whole point: recovery must not orphan them.
    await assertPairingInvariant(readAll, "recovery, paired");
  });

  test("in two couples: fails loudly and picks neither", async () => {
    const user = await newUser();
    const a = await newUser();
    const b = await newUser();
    await seedProfile(a.uid, { coupleId: "C1" });
    await seedProfile(b.uid, { coupleId: "C2" });
    await writeDoc("couples/C1", {
      memberIds: [user.uid, a.uid],
      streakCount: 0,
      createdAt: new Date(),
    });
    await writeDoc("couples/C2", {
      memberIds: [user.uid, b.uid],
      streakCount: 0,
      createdAt: new Date(),
    });

    await expectCallableError(
      user.call("ensureUserProfile", {}),
      "functions/failed-precondition",
      "multiple-couples",
    );
    // No profile written at all — better a missing document than a wrong one.
    assert.equal(await readDoc(`users/${user.uid}`), undefined);
  });

  test("an existing profile is returned untouched, and costs no couples read", async () => {
    const user = await newUser();
    await seedProfile(user.uid, { displayName: "Original", coupleId: null });
    // Two couples list them. If the early return did NOT skip the query, this
    // call would throw multiple-couples — so a clean return proves the read is
    // not spent on the existing-profile path.
    await writeDoc("couples/C1", {
      memberIds: [user.uid, "x"],
      streakCount: 0,
      createdAt: new Date(),
    });
    await writeDoc("couples/C2", {
      memberIds: [user.uid, "y"],
      streakCount: 0,
      createdAt: new Date(),
    });

    const { data } = await user.call("ensureUserProfile", {});

    assert.equal(data.created, false);
    assert.equal((await readDoc(`users/${user.uid}`)).displayName, "Original");
  });

  test("repeat calls do not clobber", async () => {
    const user = await newUser();
    await user.call("ensureUserProfile", { displayName: "First" });
    await user.call("ensureUserProfile", { displayName: "Second" });

    assert.equal((await readDoc(`users/${user.uid}`)).displayName, "First");
  });
});

// P2-35 closed `allow create`, so isWellFormedProfile no longer guards this
// path — the Admin SDK bypasses rules and this function is the only writer.
// Every check that rule made must hold here.
describe("ensureUserProfile — the checks the create rule used to make", () => {
  test("writes exactly the field set the rule required", async () => {
    const user = await newUser();
    await user.call("ensureUserProfile", {});
    const written = await readDoc(`users/${user.uid}`);

    assert.deepEqual(Object.keys(written).sort(), [
      "accentColor",
      "avatarUrl",
      "coupleId",
      "createdAt",
      "displayName",
      "favoriteEmojis",
    ]);
    // pairingCode is claimed later, never at create time.
    assert.equal("pairingCode" in written, false);
  });

  test("bounds an over-long displayName to the rule's limit", async () => {
    const user = await newUser();
    await user.call("ensureUserProfile", { displayName: "x".repeat(500) });

    const written = await readDoc(`users/${user.uid}`);
    assert.equal(written.displayName.length, profile.MAX_DISPLAY_NAME);
  });

  test("never writes an empty displayName", async () => {
    const user = await newUser();
    await user.call("ensureUserProfile", { displayName: "   " });

    const written = await readDoc(`users/${user.uid}`);
    assert.ok(written.displayName.length > 0);
  });

  test("ignores a non-string displayName rather than writing it", async () => {
    const user = await newUser();
    await user.call("ensureUserProfile", { displayName: 42 });

    const written = await readDoc(`users/${user.uid}`);
    assert.equal(typeof written.displayName, "string");
    assert.ok(written.displayName.length > 0);
  });

  test("writes the eight defaults, and the list is bounded", async () => {
    const user = await newUser();
    await user.call("ensureUserProfile", {});

    const written = await readDoc(`users/${user.uid}`);
    assert.equal(written.favoriteEmojis.length, 8);
  });

  test("createdAt is server-set and cannot be back-dated by the caller", async () => {
    const user = await newUser();
    const before = Date.now();
    await user.call("ensureUserProfile", {
      createdAt: new Date("2020-01-01T00:00:00Z").toISOString(),
    });

    const written = await readDoc(`users/${user.uid}`);
    assert.ok(written.createdAt.toMillis() >= before - 60_000);
  });

  test("a client-supplied coupleId is ignored, not honoured", async () => {
    const user = await newUser();
    await user.call("ensureUserProfile", { coupleId: "forged-couple" });

    assert.equal((await readDoc(`users/${user.uid}`)).coupleId, null);
  });

  test("an unauthenticated caller gets nothing", async () => {
    const anon = anonCaller();
    await expectCallableError(
      anon("ensureUserProfile", {}),
      "functions/unauthenticated",
    );
  });

  test("an extra field in the payload is not copied onto the document", async () => {
    const user = await newUser();
    await user.call("ensureUserProfile", { isAdmin: true, role: "owner" });

    const written = await readDoc(`users/${user.uid}`);
    assert.equal("isAdmin" in written, false);
    assert.equal("role" in written, false);
  });
});

describe("requestPairing — denormalised sender (P2-25)", () => {
  test("copies the sender name and avatar onto the request", async () => {
    const owner = await newUser();
    const sender = await newUser();
    await seedProfile(owner.uid);
    await seedProfile(sender.uid, {
      displayName: "Maya",
      avatarUrl: "https://example.test/a.png",
    });
    const { code } = (await owner.call("ensurePairingCode")).data;

    const { requestId } = (await sender.call("requestPairing", { code })).data;
    const request = await readDoc(`pairingRequests/${requestId}`);

    assert.equal(request.fromDisplayName, "Maya");
    assert.equal(request.fromAvatarUrl, "https://example.test/a.png");
  });

  test("bounds an over-long name — untrusted input crossing to another user", async () => {
    const owner = await newUser();
    const sender = await newUser();
    await seedProfile(owner.uid);
    // Longer than the users rules permit, so it could only arrive via a
    // corrupted document — bound it here rather than trusting the rules were
    // the only writer.
    await seedProfile(sender.uid, { displayName: "M".repeat(500) });
    const { code } = (await owner.call("ensurePairingCode")).data;

    const { requestId } = (await sender.call("requestPairing", { code })).data;
    const request = await readDoc(`pairingRequests/${requestId}`);

    assert.equal(request.fromDisplayName.length, pairing.MAX_DENORMALISED_NAME);
  });

  test("an empty name falls back rather than rendering blank", async () => {
    const owner = await newUser();
    const sender = await newUser();
    await seedProfile(owner.uid);
    await seedProfile(sender.uid, { displayName: "   " });
    const { code } = (await owner.call("ensurePairingCode")).data;

    const { requestId } = (await sender.call("requestPairing", { code })).data;
    const request = await readDoc(`pairingRequests/${requestId}`);

    assert.equal(request.fromDisplayName, pairing.FALLBACK_SENDER_NAME);
  });

  test("a non-string avatar is dropped, not passed through", async () => {
    const owner = await newUser();
    const sender = await newUser();
    await seedProfile(owner.uid);
    await seedProfile(sender.uid, { displayName: "Sam", avatarUrl: 42 });
    const { code } = (await owner.call("ensurePairingCode")).data;

    const { requestId } = (await sender.call("requestPairing", { code })).data;
    const request = await readDoc(`pairingRequests/${requestId}`);

    assert.equal(request.fromAvatarUrl, null);
  });
});

describe("respondToPairing — denormalised member names (M-02)", () => {
  /** Two users with the given display names, paired for real. */
  async function pairWithNames(nameA, nameB) {
    const a = await newUser();
    const b = await newUser();
    await seedProfile(a.uid, { displayName: nameA });
    await seedProfile(b.uid, { displayName: nameB });
    const { code } = (await b.call("ensurePairingCode")).data;
    const { requestId } = (await a.call("requestPairing", { code })).data;
    const { coupleId } = (
      await b.call("respondToPairing", { requestId, accept: true })
    ).data;
    return { a, b, coupleId };
  }

  test("writes both names, keyed by uid, in both directions", async () => {
    const { a, b, coupleId } = await pairWithNames("Maya", "Sam");
    const couple = await readDoc(`couples/${coupleId}`);

    assert.equal(couple.memberNames[a.uid], "Maya");
    assert.equal(couple.memberNames[b.uid], "Sam");
    // Every member has a name — the client must never render a blank.
    for (const uid of couple.memberIds) {
      assert.ok(couple.memberNames[uid], `no name for member ${uid}`);
    }
  });

  test("the sender's name is written even though they did not accept", async () => {
    // The recipient's transaction writes both, so the person who asked gets
    // rendered on the other's screen without ever acting again.
    const { a, coupleId } = await pairWithNames("Devon", "Alex");
    assert.equal(
      (await readDoc(`couples/${coupleId}`)).memberNames[a.uid],
      "Devon",
    );
  });

  test("an over-long name is truncated before it reaches the couple", async () => {
    // User-controlled text crossing to the other person's screen, bounded on
    // the same terms as P2-25's fromDisplayName.
    const { a, coupleId } = await pairWithNames("M".repeat(500), "Sam");
    const couple = await readDoc(`couples/${coupleId}`);

    assert.equal(
      couple.memberNames[a.uid].length,
      pairing.MAX_DENORMALISED_NAME,
    );
  });

  test("an empty name falls back rather than writing a blank", async () => {
    const { a, coupleId } = await pairWithNames("   ", "Sam");
    const couple = await readDoc(`couples/${coupleId}`);

    assert.equal(couple.memberNames[a.uid], pairing.FALLBACK_SENDER_NAME);
    assert.ok(couple.memberNames[a.uid].length > 0);
  });

  test("costs no extra read — the names come from documents already loaded", async () => {
    // Not directly observable, so assert the invariant it depends on: the
    // couple carries names for exactly its members and nobody else.
    const { a, b, coupleId } = await pairWithNames("Maya", "Sam");
    const couple = await readDoc(`couples/${coupleId}`);

    assert.deepEqual(
      Object.keys(couple.memberNames).sort(),
      [a.uid, b.uid].sort(),
    );
  });
});

describe("unpair — phase 1, separation (P2-36)", () => {
  const readAll = (name) =>
    admin(async (db) => {
      const snap = await getDocs(collection(db, name));
      return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    });

  /** Two seeded users, really paired through the callables. */
  async function pairedCouple() {
    const a = await newUser();
    const b = await newUser();
    await seedProfile(a.uid);
    await seedProfile(b.uid);
    const { code } = (await b.call("ensurePairingCode")).data;
    const { requestId } = (await a.call("requestPairing", { code })).data;
    const { coupleId } = (
      await b.call("respondToPairing", { requestId, accept: true })
    ).data;
    return { a, b, coupleId };
  }

  test("clears coupleId on BOTH users and marks the couple unpaired", async () => {
    const { a, b, coupleId } = await pairedCouple();

    const { data } = await a.call("unpair", {});
    assert.equal(data.coupleId, coupleId);

    assert.equal((await readDoc(`users/${a.uid}`)).coupleId, null);
    // The partner is separated without acting — that is the guarantee.
    assert.equal((await readDoc(`users/${b.uid}`)).coupleId, null);

    const couple = await readDoc(`couples/${coupleId}`);
    // The sweep may already have removed it; if not, it is marked.
    if (couple !== undefined) {
      assert.equal(couple.status, "unpaired");
      assert.equal(couple.unpairedBy, a.uid);
      assert.ok(couple.unpairedAt != null);
    }
    await assertPairingInvariant(readAll, "after unpair");
  });

  test("is idempotent — calling twice succeeds", async () => {
    const { a } = await pairedCouple();

    await a.call("unpair", {});
    const second = await a.call("unpair", {});

    assert.equal(second.data.alreadyUnpaired, true);
    assert.equal(second.data.coupleId, null);
    await assertPairingInvariant(readAll, "double unpair");
  });

  test("the partner calling second also succeeds", async () => {
    const { a, b } = await pairedCouple();

    await a.call("unpair", {});
    const partner = await b.call("unpair", {});

    assert.equal(partner.data.alreadyUnpaired, true);
    await assertPairingInvariant(readAll, "both called");
  });

  test("an unpaired caller is not an error", async () => {
    const lonely = await newUser();
    await seedProfile(lonely.uid);

    const { data } = await lonely.call("unpair", {});
    assert.equal(data.alreadyUnpaired, true);
  });

  test("a non-member cannot unpair a couple they do not belong to", async () => {
    const { coupleId } = await pairedCouple();
    const outsider = await newUser();
    // Forge the outsider's coupleId to point at someone else's couple.
    await seedProfile(outsider.uid, { coupleId });

    await expectCallableError(
      outsider.call("unpair", {}),
      "functions/permission-denied",
      "not-a-member",
    );
  });

  test("unauthenticated is rejected", async () => {
    await expectCallableError(
      anonCaller()("unpair", {}),
      "functions/unauthenticated",
    );
  });

  test("a coupleId pointing at nothing is refused, not silently cleared", async () => {
    const user = await newUser();
    await seedProfile(user.uid, { coupleId: "ghost-couple" });

    await expectCallableError(
      user.call("unpair", {}),
      "functions/failed-precondition",
      "couple-missing",
    );
  });

  test("concurrent unpair by both partners: one couple, no error", async () => {
    for (let round = 0; round < 5; round++) {
      const { a, b } = await pairedCouple();

      const results = await Promise.allSettled([
        a.call("unpair", {}),
        b.call("unpair", {}),
      ]);

      const failed = results.filter((r) => r.status === "rejected");
      assert.equal(failed.length, 0, `round ${round}: both calls must succeed`);
      assert.equal((await readDoc(`users/${a.uid}`)).coupleId, null);
      assert.equal((await readDoc(`users/${b.uid}`)).coupleId, null);
      await assertPairingInvariant(readAll, `concurrent unpair round ${round}`);
    }
  });

  test("after unpair both can claim fresh codes and pair again", async () => {
    const { a, b } = await pairedCouple();
    await a.call("unpair", {});

    const codeA = (await a.call("ensurePairingCode")).data.code;
    const codeB = (await b.call("ensurePairingCode")).data.code;
    assert.ok(codeA && codeB && codeA !== codeB);

    const { requestId } = (await a.call("requestPairing", { code: codeB }))
      .data;
    const again = (
      await b.call("respondToPairing", { requestId, accept: true })
    ).data;

    assert.ok(again.coupleId);
    assert.equal((await readDoc(`users/${a.uid}`)).coupleId, again.coupleId);
    assert.equal((await readDoc(`users/${b.uid}`)).coupleId, again.coupleId);
    await assertPairingInvariant(readAll, "re-paired");
  });
});

describe("unpair — phase 2, the sweep (P2-36)", () => {
  const readAll = (name) =>
    admin(async (db) => {
      const snap = await getDocs(collection(db, name));
      return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    });

  /** Items plus their secret bodies, seeded straight in. */
  async function seedHistory(coupleId, count) {
    for (let i = 0; i < count; i++) {
      await writeDoc(`items/${coupleId}-item-${i}`, {
        coupleId,
        senderId: "someone",
        type: i % 2 === 0 ? "text" : "secret",
        createdAt: new Date(),
      });
      // coupleId on the body is what lets the sweep reach an orphan whose
      // item has already been deleted. P2-12 must write this.
      await writeDoc(`secretBodies/${coupleId}-item-${i}`, {
        coupleId,
        body: `b${i}`,
      });
    }
  }

  test("deletes items and secret bodies, and the couple document last", async () => {
    await writeDoc("couples/SWEEP1", {
      memberIds: ["x", "y"],
      streakCount: 0,
      createdAt: new Date(),
    });
    await seedHistory("SWEEP1", 5);
    // An unrelated couple's history must survive untouched.
    await writeDoc("couples/OTHER", {
      memberIds: ["p", "q"],
      streakCount: 0,
      createdAt: new Date(),
    });
    await seedHistory("OTHER", 3);

    await unpairModule.sweepCouple(adminDb(), "SWEEP1");

    const items = await readAll("items");
    const bodies = await readAll("secretBodies");
    assert.equal(items.filter((i) => i.coupleId === "SWEEP1").length, 0);
    assert.equal(bodies.filter((b) => b.id.startsWith("SWEEP1")).length, 0);
    assert.equal(await readDoc("couples/SWEEP1"), undefined);

    // The neighbour is intact.
    assert.equal(items.filter((i) => i.coupleId === "OTHER").length, 3);
    assert.equal((await readDoc("couples/OTHER")) !== undefined, true);
  });

  test("an interrupted sweep is completed by a re-run", async () => {
    await writeDoc("couples/SWEEP2", {
      memberIds: ["x", "y"],
      streakCount: 0,
      createdAt: new Date(),
    });
    await seedHistory("SWEEP2", 6);

    // Simulate dying partway: delete some items and one body by hand, leaving
    // the couple document in place — which is exactly why it goes last.
    await admin(async (db) => {
      await deleteDoc(doc(db, "items", "SWEEP2-item-0"));
      await deleteDoc(doc(db, "items", "SWEEP2-item-1"));
      await deleteDoc(doc(db, "secretBodies", "SWEEP2-item-0"));
    });

    await unpairModule.sweepCouple(adminDb(), "SWEEP2");

    const items = await readAll("items");
    const bodies = await readAll("secretBodies");
    assert.equal(items.filter((i) => i.coupleId === "SWEEP2").length, 0);
    assert.equal(bodies.filter((b) => b.id.startsWith("SWEEP2")).length, 0);
    assert.equal(await readDoc("couples/SWEEP2"), undefined);
  });

  test("sweeping twice is not an error", async () => {
    await writeDoc("couples/SWEEP3", {
      memberIds: ["x", "y"],
      streakCount: 0,
      createdAt: new Date(),
    });
    await seedHistory("SWEEP3", 2);

    await unpairModule.sweepCouple(adminDb(), "SWEEP3");
    await unpairModule.sweepCouple(adminDb(), "SWEEP3");

    assert.equal(await readDoc("couples/SWEEP3"), undefined);
  });

  test("a couple with no history sweeps cleanly", async () => {
    await writeDoc("couples/SWEEP4", {
      memberIds: ["x", "y"],
      streakCount: 0,
      createdAt: new Date(),
    });

    const result = await unpairModule.sweepCouple(adminDb(), "SWEEP4");
    assert.equal(result.items, 0);
    assert.equal(await readDoc("couples/SWEEP4"), undefined);
  });
});

describe("cancelPairingRequest", () => {
  async function pendingRequest() {
    const owner = await newUser();
    await seedProfile(owner.uid);
    const code = (await owner.call("ensurePairingCode")).data.code;
    const sender = await newUser();
    await seedProfile(sender.uid);
    const { data } = await sender.call("requestPairing", { code });
    return { sender, owner, requestId: data.requestId };
  }

  test("the sender can cancel a pending request", async () => {
    const { sender, requestId } = await pendingRequest();
    await sender.call("cancelPairingRequest", { requestId });
    const request = await readDoc(`pairingRequests/${requestId}`);
    assert.equal(request.status, "cancelled");
  });

  test("the recipient cannot cancel it", async () => {
    const { owner, requestId } = await pendingRequest();
    await expectCallableError(
      owner.call("cancelPairingRequest", { requestId }),
      "functions/permission-denied",
      "not-sender",
    );
  });

  test("a settled request cannot be cancelled again", async () => {
    const { sender, requestId } = await pendingRequest();
    await sender.call("cancelPairingRequest", { requestId });
    await expectCallableError(
      sender.call("cancelPairingRequest", { requestId }),
      "functions/failed-precondition",
      "request-not-pending",
    );
  });

  test("an unknown request is not-found", async () => {
    const user = await newUser();
    await seedProfile(user.uid);
    await expectCallableError(
      user.call("cancelPairingRequest", { requestId: "nope" }),
      "functions/not-found",
      "request-not-found",
    );
  });
});

describe("setMood (P2-12 / M-07)", () => {
  const readAll = (name) =>
    admin(async (db) => {
      const snap = await getDocs(collection(db, name));
      return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    });

  /** Two seeded users, really paired through the callables. */
  async function pairedCouple() {
    const a = await newUser();
    const b = await newUser();
    await seedProfile(a.uid);
    await seedProfile(b.uid);
    const { code } = (await b.call("ensurePairingCode")).data;
    const { requestId } = (await a.call("requestPairing", { code })).data;
    const { coupleId } = (
      await b.call("respondToPairing", { requestId, accept: true })
    ).data;
    return { a, b, coupleId };
  }

  test("writes the ambient value AND the scrollback item", async () => {
    const { a, coupleId } = await pairedCouple();

    await a.call("setMood", { emoji: "☕", note: "running on one coffee" });

    // The couple half — the live value, on a document no client may write.
    const couple = await readDoc(`couples/${coupleId}`);
    assert.equal(couple.moodEmoji, "☕");
    assert.equal(couple.moodText, "running on one coffee");
    assert.equal(couple.moodBy, a.uid);
    assert.ok(couple.moodUpdatedAt, "moodUpdatedAt was stamped");

    // The items half — the scrollback record.
    const items = await readAll("items");
    assert.equal(items.length, 1);
    assert.equal(items[0].type, "status");
    assert.equal(items[0].coupleId, coupleId);
    assert.equal(items[0].senderId, a.uid);
    assert.equal(items[0].body, "running on one coffee");
    assert.equal(items[0].emoji, "☕");
    assert.deepEqual(items[0].reactions, {});
  });

  test("a second mood appends to scrollback and replaces the ambient value", async () => {
    const { a, b, coupleId } = await pairedCouple();

    await a.call("setMood", { emoji: "☕", note: "one coffee" });
    await b.call("setMood", { emoji: "🎧", note: "heads down" });

    // Scrollback accumulates: a mood is a moment, not a mutable field.
    assert.equal((await readAll("items")).length, 2);

    // The ambient value is whoever set one last.
    const couple = await readDoc(`couples/${coupleId}`);
    assert.equal(couple.moodEmoji, "🎧");
    assert.equal(couple.moodBy, b.uid);
  });

  test("an emoji with no note is fine — a mood need not have words", async () => {
    const { a, coupleId } = await pairedCouple();

    await a.call("setMood", { emoji: "🫠", note: "" });

    assert.equal((await readDoc(`couples/${coupleId}`)).moodText, "");
    assert.equal((await readAll("items"))[0].body, "");
  });

  test("an unpaired user cannot set one", async () => {
    const solo = await newUser();
    await seedProfile(solo.uid);

    await assert.rejects(
      () => solo.call("setMood", { emoji: "☕", note: "hello" }),
      /not paired|failed-precondition/i,
    );
    assert.equal((await readAll("items")).length, 0);
  });

  test("a profile pointing at a couple that does not list you is refused", async () => {
    // The incoherent state P2-18 exists to prevent. Membership is checked
    // against the couple, never inferred from the caller's own profile.
    const { coupleId } = await pairedCouple();
    const outsider = await newUser();
    await seedProfile(outsider.uid, { coupleId });

    await assert.rejects(
      () => outsider.call("setMood", { emoji: "☕", note: "not mine" }),
      /permission-denied|not yours/i,
    );
  });

  test("anonymous callers are rejected", async () => {
    const call = anonCaller();
    await assert.rejects(
      () => call("setMood", { emoji: "☕", note: "hello" }),
      /Sign in first/i,
    );
  });

  test("a missing or non-string emoji is rejected", async () => {
    const { a } = await pairedCouple();

    await assert.rejects(
      () => a.call("setMood", { note: "no emoji" }),
      /Pick a mood/i,
    );
    await assert.rejects(
      () => a.call("setMood", { emoji: 42, note: "not a string" }),
      /Pick a mood/i,
    );
    assert.equal((await readAll("items")).length, 0);
  });

  test("an over-long note is rejected rather than truncated", async () => {
    // Truncating would silently publish a different sentence to the other
    // person than the one that was written.
    const { a } = await pairedCouple();
    const { MAX_MOOD_NOTE } = requireFromFunctions("./lib/mood.js");

    await assert.rejects(
      () => a.call("setMood", { emoji: "☕", note: "x".repeat(MAX_MOOD_NOTE + 1) }),
      /note is too long/i,
    );
    assert.equal((await readAll("items")).length, 0);
  });

  test("the note is trimmed, so whitespace cannot pad past the bound", async () => {
    const { a } = await pairedCouple();

    await a.call("setMood", { emoji: "  ☕  ", note: "   spaced out   " });

    assert.equal((await readAll("items"))[0].body, "spaced out");
    assert.equal((await readAll("items"))[0].emoji, "☕");
  });
});
