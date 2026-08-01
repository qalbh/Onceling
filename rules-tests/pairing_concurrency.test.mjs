// P2-18 — concurrency tests for the accept transaction (P2-09b).
//
// This is the highest-value test file in the project. Everything downstream
// assumes coupleId is unforgeable and that a person belongs to exactly one
// couple, forever, until unpair. "Atomic" is not established by reading the
// code; it is established by firing simultaneous operations in a loop and
// asserting exactly one wins.
//
// Run: cd rules-tests && npm run test:functions   (emulator suite must be up,
// with build:watch keeping functions/lib/ fresh).
//
// Shares the qalb-coupleapp-dev namespace with pairing_functions.test.mjs
// because the Functions emulator runs under that project — so the two files
// must not run concurrently. `npm run test:functions` passes
// --test-concurrency=1 for exactly that reason.

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
import { collection, doc, getDoc, getDocs, setDoc } from "firebase/firestore";

import { assertPairingInvariant as checkPairingInvariant } from "./pairing_invariant.mjs";

const PROJECT = "qalb-coupleapp-dev";

/** Loop count for every race. Fewer than this and a race hides. */
const ROUNDS = 20;

let testEnv;
const apps = [];

/**
 * Auth users are created once and reused across iterations. Only the uid
 * matters, and the freshness that counts is Firestore state — which
 * clearFirestore() wipes before every iteration. Creating 160 accounts
 * instead would test the auth emulator, not the transaction.
 */
let pool;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { host: "127.0.0.1", port: 8080 },
  });
  pool = await Promise.all([newUser(), newUser(), newUser(), newUser()]);
});

after(async () => {
  await Promise.all(apps.map((app) => deleteApp(app)));
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

async function newUser() {
  const app = initializeApp(
    { apiKey: "fake-api-key", projectId: PROJECT },
    `conc-${randomUUID()}`,
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
    respond: (requestId, accept) =>
      httpsCallable(functions, "respondToPairing")({ requestId, accept }),
  };
}

// ---------------------------------------------------------------------------
// Admin-side helpers. All go through withSecurityRulesDisabled: these assert
// on ground truth, deliberately bypassing the rules under test elsewhere.
// ---------------------------------------------------------------------------

async function admin(fn) {
  let out;
  await testEnv.withSecurityRulesDisabled(async (context) => {
    out = await fn(context.firestore());
  });
  return out;
}

const readDoc = (path) =>
  admin(async (db) => {
    const snap = await getDoc(doc(db, path));
    return snap.exists() ? snap.data() : undefined;
  });

const writeDoc = (path, data) => admin((db) => setDoc(doc(db, path), data));

const readAll = (name) =>
  admin(async (db) => {
    const snap = await getDocs(collection(db, name));
    return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  });

/** Seeds users/{uid}, plus its pairingCodes entry when a code is given. */
async function seedProfile(uid, { coupleId = null, pairingCode = null } = {}) {
  await writeDoc(`users/${uid}`, {
    displayName: "Test",
    avatarUrl: null,
    coupleId,
    favoriteEmojis: [],
    accentColor: null,
    createdAt: new Date(),
    ...(pairingCode == null ? {} : { pairingCode }),
  });
  if (pairingCode != null) {
    await writeDoc(`pairingCodes/${pairingCode}`, {
      ownerId: uid,
      createdAt: new Date(),
    });
  }
}

/**
 * Seeds a pending request directly rather than calling requestPairing.
 *
 * Deliberate: P2-18 is about the accept transaction, and going through the
 * callable would drag P2-27's rate limit (five an hour) into a twenty-round
 * loop for no gain.
 */
async function seedRequest(fromUid, toUid, id = randomUUID()) {
  await writeDoc(`pairingRequests/${id}`, {
    fromUid,
    toUid,
    status: "pending",
    createdAt: new Date(),
  });
  return id;
}

/** One code per uid, stable within an iteration and unique across them. */
const codeFor = (uid, salt) => `${salt}${uid}`.replace(/-/g, "").slice(0, 6);

// ---------------------------------------------------------------------------
// THE INVARIANT
// ---------------------------------------------------------------------------

/**
 * The assertion that matters most. Called at the end of every test.
 *
 * Definition lives in pairing_invariant.mjs so P2-35's recovery tests assert
 * the identical thing — see the note there.
 *
 * If this ever fails the transaction is wrong regardless of what else passed.
 */
const assertPairingInvariant = (label) => checkPairingInvariant(readAll, label);

/** Splits allSettled output into successes and rejections. */
function settle(results) {
  return {
    ok: results
      .filter((r) => r.status === "fulfilled")
      .map((r) => r.value.data),
    failed: results.filter((r) => r.status === "rejected").map((r) => r.reason),
  };
}

// ---------------------------------------------------------------------------
// The four races
// ---------------------------------------------------------------------------

describe("P2-18 — concurrent accepts", () => {
  test("mutual requests, both accepted simultaneously, make one couple", async () => {
    const [a, b] = pool;
    for (let round = 0; round < ROUNDS; round++) {
      await testEnv.clearFirestore();
      await seedProfile(a.uid, { pairingCode: codeFor(a.uid, "A") });
      await seedProfile(b.uid, { pairingCode: codeFor(b.uid, "B") });
      const aToB = await seedRequest(a.uid, b.uid);
      const bToA = await seedRequest(b.uid, a.uid);

      // A accepts B's request while B accepts A's. Both transactions read
      // both user documents, so they contend; one must lose.
      const { ok, failed } = settle(
        await Promise.allSettled([
          a.respond(bToA, true),
          b.respond(aToB, true),
        ]),
      );

      const couples = await readAll("couples");
      assert.equal(
        couples.length,
        1,
        `round ${round}: expected one couple, got ${couples.length}`,
      );
      assert.equal(
        ok.length,
        1,
        `round ${round}: expected one success, got ${ok.length}`,
      );
      assert.equal(failed.length, 1, `round ${round}: expected one failure`);
      assert.equal(failed[0].code, "functions/failed-precondition");

      const [ua, ub] = await Promise.all([
        readDoc(`users/${a.uid}`),
        readDoc(`users/${b.uid}`),
      ]);
      assert.equal(ua.coupleId, couples[0].id);
      assert.equal(ub.coupleId, couples[0].id);
      assert.equal(ok[0].coupleId, couples[0].id);

      await assertPairingInvariant(`mutual round ${round}`);
    }
  });

  test("two senders, one recipient, both accepted simultaneously", async () => {
    const [r, s1, s2] = pool;
    for (let round = 0; round < ROUNDS; round++) {
      await testEnv.clearFirestore();
      await seedProfile(r.uid, { pairingCode: codeFor(r.uid, "R") });
      await seedProfile(s1.uid, { pairingCode: codeFor(s1.uid, "S") });
      await seedProfile(s2.uid, { pairingCode: codeFor(s2.uid, "T") });
      const first = await seedRequest(s1.uid, r.uid);
      const second = await seedRequest(s2.uid, r.uid);

      const { ok, failed } = settle(
        await Promise.allSettled([
          r.respond(first, true),
          r.respond(second, true),
        ]),
      );

      const couples = await readAll("couples");
      assert.equal(couples.length, 1, `round ${round}: expected one couple`);
      assert.equal(ok.length, 1, `round ${round}: expected one success`);
      assert.equal(failed.length, 1);

      const couple = couples[0];
      const winner = couple.memberIds.find((id) => id !== r.uid);
      const loser = winner === s1.uid ? s2.uid : s1.uid;

      const loserDoc = await readDoc(`users/${loser}`);
      assert.equal(
        loserDoc.coupleId,
        null,
        `round ${round}: losing sender ${loser} must still be unpaired`,
      );

      // The losing sender's request must be settled, never left pending
      // against a recipient who can no longer accept it.
      const requests = await readAll("pairingRequests");
      const loserRequest = requests.find((q) => q.fromUid === loser);
      assert.equal(
        loserRequest.status,
        "expired",
        `round ${round}: loser's request`,
      );

      await assertPairingInvariant(`two-senders round ${round}`);
    }
  });

  test("sender paired elsewhere between request and accept", async () => {
    const [r, s, other] = pool;
    for (let round = 0; round < ROUNDS; round++) {
      await testEnv.clearFirestore();
      const existing = `existing-couple-${round}`;
      await writeDoc(`couples/${existing}`, {
        memberIds: [s.uid, other.uid],
        coupleName: null,
        // Null on purpose, and still correct after M-10: this hand-written
        // fixture models a couple that already existed, i.e. one paired before
        // the anniversary default landed. There is no migration by design, so
        // legacy couples really do look like this.
        anniversaryDate: null,
        streakCount: 7,
        lastStreakDate: null,
        timezone: null,
        createdAt: new Date(),
      });
      await seedProfile(s.uid, { coupleId: existing });
      await seedProfile(other.uid, { coupleId: existing });
      await seedProfile(r.uid, { pairingCode: codeFor(r.uid, "R") });
      const stale = await seedRequest(s.uid, r.uid);

      await assert.rejects(
        r.respond(stale, true),
        (error) => {
          assert.equal(error.code, "functions/failed-precondition");
          assert.equal(error.details?.reason, "sender-already-paired");
          return true;
        },
        `round ${round}`,
      );

      const couples = await readAll("couples");
      assert.equal(couples.length, 1, `round ${round}: no second couple`);
      assert.equal(
        couples[0].streakCount,
        7,
        `round ${round}: existing couple untouched`,
      );
      assert.deepEqual(couples[0].memberIds, [s.uid, other.uid]);
      assert.equal((await readDoc(`users/${r.uid}`)).coupleId, null);

      await assertPairingInvariant(`sender-paired round ${round}`);
    }
  });

  test("the same request accepted twice concurrently", async () => {
    const [a, b] = pool;
    for (let round = 0; round < ROUNDS; round++) {
      await testEnv.clearFirestore();
      await seedProfile(a.uid, { pairingCode: codeFor(a.uid, "A") });
      await seedProfile(b.uid, { pairingCode: codeFor(b.uid, "B") });
      const requestId = await seedRequest(a.uid, b.uid);

      // The double tap. Either both report the same couple (the second call
      // took the idempotent path) or one fails cleanly. Never two couples.
      const { ok, failed } = settle(
        await Promise.allSettled([
          b.respond(requestId, true),
          b.respond(requestId, true),
        ]),
      );

      const couples = await readAll("couples");
      assert.equal(
        couples.length,
        1,
        `round ${round}: expected one couple, got ${couples.length}`,
      );
      assert.ok(
        ok.length >= 1,
        `round ${round}: at least one call must succeed`,
      );
      for (const value of ok) {
        assert.equal(
          value.coupleId,
          couples[0].id,
          `round ${round}: disagreeing coupleIds`,
        );
      }
      for (const error of failed) {
        assert.equal(
          error.code,
          "functions/failed-precondition",
          `round ${round}`,
        );
        assert.equal(error.details?.reason, "request-not-pending");
      }

      await assertPairingInvariant(`double-tap round ${round}`);
    }
  });
});

// ---------------------------------------------------------------------------
// Non-concurrent behaviour
// ---------------------------------------------------------------------------

describe("P2-09b — accept", () => {
  test("creates the couple, stamps both users, destroys both codes", async () => {
    const [a, b] = pool;
    await seedProfile(a.uid, { pairingCode: "AAA111" });
    await seedProfile(b.uid, { pairingCode: "BBB222" });
    const requestId = await seedRequest(a.uid, b.uid);

    const result = await b.respond(requestId, true);
    assert.equal(result.data.accepted, true);
    const coupleId = result.data.coupleId;

    const couple = await readDoc(`couples/${coupleId}`);
    assert.deepEqual([...couple.memberIds].sort(), [a.uid, b.uid].sort());
    assert.equal(couple.streakCount, 0);
    assert.equal(couple.lastStreakDate, null);
    assert.equal(couple.coupleName, null);
    // timezone is still null on purpose — Q3 is open, see pairing.ts.
    assert.equal(couple.timezone, null);
    assert.ok(couple.createdAt != null);
    // anniversaryDate stopped being null at M-10: the owner decided it
    // defaults to the pairing date. Asserted here as "the same instant as
    // createdAt" rather than merely non-null, so this test still pins the
    // shape of the accept rather than going vague about it.
    assert.equal(
      couple.anniversaryDate.toMillis(),
      couple.createdAt.toMillis(),
    );

    for (const uid of [a.uid, b.uid]) {
      const user = await readDoc(`users/${uid}`);
      assert.equal(user.coupleId, coupleId, `coupleId on ${uid}`);
      assert.equal(
        user.pairingCode,
        undefined,
        `pairingCode cleared on ${uid}`,
      );
    }
    assert.equal(await readDoc("pairingCodes/AAA111"), undefined);
    assert.equal(await readDoc("pairingCodes/BBB222"), undefined);

    assert.equal(
      (await readDoc(`pairingRequests/${requestId}`)).status,
      "accepted",
    );
    await assertPairingInvariant("accept");
  });

  test("expires every other pending request for both users, both directions", async () => {
    const [a, b, c, d] = pool;
    await seedProfile(a.uid, { pairingCode: "AAA111" });
    await seedProfile(b.uid, { pairingCode: "BBB222" });
    await seedProfile(c.uid, { pairingCode: "CCC333" });
    await seedProfile(d.uid, { pairingCode: "DDD444" });

    const accepted = await seedRequest(a.uid, b.uid);
    const others = {
      senderOutbound: await seedRequest(a.uid, c.uid), // a → someone else
      senderInbound: await seedRequest(c.uid, a.uid), // someone else → a
      recipientOutbound: await seedRequest(b.uid, d.uid), // b → someone else
      recipientInbound: await seedRequest(d.uid, b.uid), // someone else → b
    };
    // An unrelated pair's request must survive untouched.
    const unrelated = await seedRequest(c.uid, d.uid);

    await b.respond(accepted, true);

    for (const [label, id] of Object.entries(others)) {
      const request = await readDoc(`pairingRequests/${id}`);
      assert.equal(request.status, "expired", `${label} must be expired`);
    }
    assert.equal(
      (await readDoc(`pairingRequests/${unrelated}`)).status,
      "pending",
    );
    await assertPairingInvariant("sweep");
  });

  test("a second accept of the same request is idempotent, not a second couple", async () => {
    const [a, b] = pool;
    await seedProfile(a.uid, { pairingCode: "AAA111" });
    await seedProfile(b.uid, { pairingCode: "BBB222" });
    const requestId = await seedRequest(a.uid, b.uid);

    const first = await b.respond(requestId, true);
    const second = await b.respond(requestId, true);

    assert.equal(second.data.coupleId, first.data.coupleId);
    assert.equal((await readAll("couples")).length, 1);
    await assertPairingInvariant("idempotent accept");
  });

  test("an already-paired recipient cannot accept", async () => {
    const [a, b, other] = pool;
    await writeDoc("couples/taken", {
      memberIds: [b.uid, other.uid],
      streakCount: 0,
      createdAt: new Date(),
    });
    await seedProfile(b.uid, { coupleId: "taken" });
    await seedProfile(other.uid, { coupleId: "taken" });
    await seedProfile(a.uid, { pairingCode: "AAA111" });
    const requestId = await seedRequest(a.uid, b.uid);

    await assert.rejects(b.respond(requestId, true), (error) => {
      assert.equal(error.code, "functions/failed-precondition");
      assert.equal(error.details?.reason, "caller-already-paired");
      return true;
    });
    assert.equal((await readAll("couples")).length, 1);
    await assertPairingInvariant("already-paired recipient");
  });

  test("a self-addressed request cannot be accepted", async () => {
    const [a] = pool;
    await seedProfile(a.uid, { pairingCode: "AAA111" });
    // requestPairing refuses to create this; a forged document could carry it.
    const requestId = await seedRequest(a.uid, a.uid);

    await assert.rejects(a.respond(requestId, true), (error) => {
      assert.equal(error.code, "functions/failed-precondition");
      assert.equal(error.details?.reason, "self-pairing");
      return true;
    });
    assert.equal((await readAll("couples")).length, 0);
    assert.equal((await readDoc(`users/${a.uid}`)).coupleId, null);
    await assertPairingInvariant("self-pair");
  });

  test("only the recipient may accept", async () => {
    const [a, b, c] = pool;
    await seedProfile(a.uid);
    await seedProfile(b.uid);
    await seedProfile(c.uid);
    const requestId = await seedRequest(a.uid, b.uid);

    // The sender cannot accept their own request.
    await assert.rejects(a.respond(requestId, true), (error) => {
      assert.equal(error.details?.reason, "not-recipient");
      return true;
    });
    // Nor can a bystander who guessed the id.
    await assert.rejects(c.respond(requestId, true), (error) => {
      assert.equal(error.details?.reason, "not-recipient");
      return true;
    });
    assert.equal((await readAll("couples")).length, 0);
    await assertPairingInvariant("not-recipient");
  });

  test("rejects unauthenticated, malformed and unknown requests", async () => {
    const [a, b] = pool;
    await seedProfile(a.uid);
    await seedProfile(b.uid);
    const requestId = await seedRequest(a.uid, b.uid);

    await assert.rejects(
      b.call("respondToPairing", { accept: true }),
      (error) => {
        assert.equal(error.details?.reason, "request-id-malformed");
        return true;
      },
    );
    await assert.rejects(
      b.call("respondToPairing", { requestId, accept: "yes" }),
      (error) => {
        assert.equal(error.details?.reason, "accept-malformed");
        return true;
      },
    );
    await assert.rejects(b.respond("no-such-request", true), (error) => {
      assert.equal(error.code, "functions/not-found");
      assert.equal(error.details?.reason, "request-not-found");
      return true;
    });
    await assertPairingInvariant("malformed input");
  });
});

describe("P2-09b — decline (PI-05)", () => {
  test("writes 'expired', never 'rejected' or 'cancelled'", async () => {
    const [a, b] = pool;
    await seedProfile(a.uid, { pairingCode: "AAA111" });
    await seedProfile(b.uid, { pairingCode: "BBB222" });
    const requestId = await seedRequest(a.uid, b.uid);

    const result = await b.respond(requestId, false);
    assert.equal(result.data.accepted, false);

    const request = await readDoc(`pairingRequests/${requestId}`);
    assert.equal(request.status, "expired");
    // The sender can read this document. A status that names the refusal, or
    // a timestamp that dates it earlier than P2-28's seven-day sweep, both
    // tell them a person said no.
    assert.equal(request.settledAt, undefined, "no settledAt timing oracle");
    assert.equal(request.coupleId, undefined);

    // A decline changes nothing else.
    assert.equal((await readAll("couples")).length, 0);
    assert.equal((await readDoc(`users/${a.uid}`)).coupleId, null);
    assert.equal((await readDoc(`users/${b.uid}`)).coupleId, null);
    assert.equal((await readDoc("pairingCodes/AAA111")).ownerId, a.uid);
    await assertPairingInvariant("decline");
  });

  test("only the recipient may decline", async () => {
    const [a, b, c] = pool;
    await seedProfile(a.uid);
    await seedProfile(b.uid);
    await seedProfile(c.uid);
    const requestId = await seedRequest(a.uid, b.uid);

    for (const caller of [a, c]) {
      await assert.rejects(caller.respond(requestId, false), (error) => {
        assert.equal(error.code, "functions/permission-denied");
        assert.equal(error.details?.reason, "not-recipient");
        return true;
      });
    }
    assert.equal(
      (await readDoc(`pairingRequests/${requestId}`)).status,
      "pending",
    );
    await assertPairingInvariant("decline by non-recipient");
  });

  test("a settled request cannot be declined again", async () => {
    const [a, b] = pool;
    await seedProfile(a.uid);
    await seedProfile(b.uid);
    const requestId = await seedRequest(a.uid, b.uid);

    await b.respond(requestId, false);
    await assert.rejects(b.respond(requestId, false), (error) => {
      assert.equal(error.code, "functions/failed-precondition");
      assert.equal(error.details?.reason, "request-not-pending");
      return true;
    });
    await assertPairingInvariant("double decline");
  });

  test("a declined request cannot later be accepted", async () => {
    const [a, b] = pool;
    await seedProfile(a.uid, { pairingCode: "AAA111" });
    await seedProfile(b.uid, { pairingCode: "BBB222" });
    const requestId = await seedRequest(a.uid, b.uid);

    await b.respond(requestId, false);
    await assert.rejects(b.respond(requestId, true), (error) => {
      assert.equal(error.details?.reason, "request-not-pending");
      return true;
    });
    assert.equal((await readAll("couples")).length, 0);
    await assertPairingInvariant("decline then accept");
  });
});
