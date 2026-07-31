// Functions tests for the pairing callables (P2-08, P2-09, P2-09c, P2-27).
// Run: cd rules-tests && npm run test:functions   (emulator suite must be up,
// with build:watch keeping functions/lib/ fresh).

import { createRequire } from 'node:module';
import { randomUUID } from 'node:crypto';
import { after, before, beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { deleteApp, initializeApp } from 'firebase/app';
import {
  connectAuthEmulator,
  createUserWithEmailAndPassword,
  getAuth,
} from 'firebase/auth';
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
} from 'firebase/functions';
import { doc, getDoc, setDoc } from 'firebase/firestore';

// The compiled functions module, imported directly so the pure pieces
// (alphabet, generator, claim-with-retry) are testable without HTTP.
// Point the admin SDK it initialises at the emulator first.
process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
process.env.GCLOUD_PROJECT ??= 'qalb-coupleapp-dev';
// Resolve from functions/ — firebase-admin is its dependency, not ours.
const requireFromFunctions = createRequire(
  new URL('../functions/package.json', import.meta.url),
);
const pairing = requireFromFunctions('./lib/pairing.js');
const { getFirestore } = requireFromFunctions('firebase-admin/firestore');

const PROJECT = 'qalb-coupleapp-dev';

let testEnv;
const apps = [];

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { host: '127.0.0.1', port: 8080 },
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
    { apiKey: 'fake-api-key', projectId: PROJECT },
    `app-${randomUUID()}`,
  );
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  const cred = await createUserWithEmailAndPassword(
    auth,
    `${randomUUID()}@onceling.test`,
    'hunter22',
  );
  const functions = getFunctions(app);
  connectFunctionsEmulator(functions, '127.0.0.1', 5001);
  return {
    uid: cred.user.uid,
    call: (name, data) => httpsCallable(functions, name)(data),
  };
}

/** Unauthenticated functions handle. */
function anonCaller() {
  const app = initializeApp(
    { apiKey: 'fake-api-key', projectId: PROJECT },
    `anon-${randomUUID()}`,
  );
  apps.push(app);
  const functions = getFunctions(app);
  connectFunctionsEmulator(functions, '127.0.0.1', 5001);
  return (name, data) => httpsCallable(functions, name)(data);
}

/** Seeds a minimal users/{uid} document past the rules. */
async function seedProfile(uid, extra = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users', uid), {
      displayName: 'Test',
      avatarUrl: null,
      coupleId: null,
      favoriteEmojis: [],
      accentColor: null,
      createdAt: new Date(),
      ...extra,
    });
  });
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
      assert.equal(error.details?.reason, reason, 'details.reason');
    }
  }
}

describe('code generation (pure)', () => {
  test('the alphabet has no ambiguous characters', () => {
    for (const banned of ['0', 'O', '1', 'I', 'L']) {
      assert.ok(
        !pairing.CODE_ALPHABET.includes(banned),
        `alphabet must not contain ${banned}`,
      );
    }
  });

  test('generated codes stay inside the alphabet, at length 6', () => {
    for (let i = 0; i < 10_000; i++) {
      const code = pairing.generateCode();
      assert.equal(code.length, pairing.CODE_LENGTH);
      for (const char of code) {
        assert.ok(pairing.CODE_ALPHABET.includes(char), `bad char ${char}`);
      }
    }
  });
});

describe('ensurePairingCode', () => {
  test('repeated calls return the same code', async () => {
    const user = await newUser();
    await seedProfile(user.uid);

    const first = (await user.call('ensurePairingCode')).data.code;
    const second = (await user.call('ensurePairingCode')).data.code;

    assert.equal(first, second);
    assert.equal(first.length, 6);
    const profile = await readDoc(`users/${user.uid}`);
    assert.equal(profile.pairingCode, first);
    const claim = await readDoc(`pairingCodes/${first}`);
    assert.equal(claim.ownerId, user.uid);
  });

  test('collision retries onto a fresh code without disturbing the owner', async () => {
    const victim = await newUser();
    await seedProfile(victim.uid);
    await writeDoc('pairingCodes/AAAAAA', {
      ownerId: 'someone-else',
      createdAt: new Date(),
    });

    // Force the generator to collide first, then produce a free code.
    const sequence = ['AAAAAA', 'BBBBBB'];
    const code = await pairing.claimPairingCode(
      getFirestore(),
      victim.uid,
      () => sequence.shift() ?? 'CCCCCC',
    );

    assert.equal(code, 'BBBBBB');
    const original = await readDoc('pairingCodes/AAAAAA');
    assert.equal(original.ownerId, 'someone-else', 'collision must not overwrite');
  });

  test('gives up with resource-exhausted after the attempt cap', async () => {
    const user = await newUser();
    await seedProfile(user.uid);
    await writeDoc('pairingCodes/DDDDDD', {
      ownerId: 'someone-else',
      createdAt: new Date(),
    });

    await assert.rejects(
      pairing.claimPairingCode(getFirestore(), user.uid, () => 'DDDDDD'),
      (error) => error.code === 'resource-exhausted',
    );
  });

  test('refuses a paired caller', async () => {
    const user = await newUser();
    await seedProfile(user.uid, { coupleId: 'couple-1' });
    await expectCallableError(
      user.call('ensurePairingCode'),
      'functions/failed-precondition',
      'caller-already-paired',
    );
  });
});

describe('requestPairing — the six rejections', () => {
  test('unauthenticated', async () => {
    const call = anonCaller();
    await expectCallableError(
      call('requestPairing', { code: 'ABC234' }),
      'functions/unauthenticated',
      null,
    );
  });

  test('caller already paired', async () => {
    const user = await newUser();
    await seedProfile(user.uid, { coupleId: 'couple-1' });
    await expectCallableError(
      user.call('requestPairing', { code: 'ABC234' }),
      'functions/failed-precondition',
      'caller-already-paired',
    );
  });

  test('code does not exist', async () => {
    const user = await newUser();
    await seedProfile(user.uid);
    await expectCallableError(
      user.call('requestPairing', { code: 'ZZZ999' }),
      'functions/not-found',
      'code-not-found',
    );
  });

  test('self-pairing', async () => {
    const user = await newUser();
    await seedProfile(user.uid);
    const code = (await user.call('ensurePairingCode')).data.code;
    await expectCallableError(
      user.call('requestPairing', { code }),
      'functions/invalid-argument',
      'self-pairing',
    );
  });

  test('owner already paired', async () => {
    const owner = await newUser();
    await seedProfile(owner.uid);
    const code = (await owner.call('ensurePairingCode')).data.code;
    // Pair the owner behind the scenes, leaving the code dangling.
    await seedProfile(owner.uid, { coupleId: 'couple-1', pairingCode: code });

    const requester = await newUser();
    await seedProfile(requester.uid);
    await expectCallableError(
      requester.call('requestPairing', { code }),
      'functions/failed-precondition',
      'owner-already-paired',
    );
  });

  test('duplicate pending request to the same owner', async () => {
    const owner = await newUser();
    await seedProfile(owner.uid);
    const code = (await owner.call('ensurePairingCode')).data.code;

    const requester = await newUser();
    await seedProfile(requester.uid);
    await requester.call('requestPairing', { code });
    await expectCallableError(
      requester.call('requestPairing', { code }),
      'functions/already-exists',
      'request-already-pending',
    );
  });
});

describe('requestPairing — happy path', () => {
  test('creates exactly one pending document and returns only its id', async () => {
    const owner = await newUser();
    await seedProfile(owner.uid);
    const code = (await owner.call('ensurePairingCode')).data.code;

    const requester = await newUser();
    await seedProfile(requester.uid);
    const result = await requester.call('requestPairing', { code });

    assert.deepEqual(Object.keys(result.data), ['requestId'], 'nothing but the id');
    const request = await readDoc(`pairingRequests/${result.data.requestId}`);
    assert.equal(request.fromUid, requester.uid);
    assert.equal(request.toUid, owner.uid);
    assert.equal(request.status, 'pending');
  });
});

describe('requestPairing — rate limit (P2-27)', () => {
  test('the cap triggers, and a VALID code gets the same error as an invalid one', async () => {
    const owner = await newUser();
    await seedProfile(owner.uid);
    const validCode = (await owner.call('ensurePairingCode')).data.code;

    const prober = await newUser();
    await seedProfile(prober.uid);

    // Spend the whole budget on garbage codes — failed probes are not free.
    for (let i = 0; i < 5; i++) {
      await expectCallableError(
        prober.call('requestPairing', { code: 'ZZZ999' }),
        'functions/not-found',
        'code-not-found',
      );
    }

    // Over the cap: identical error whether the code is real or not.
    await expectCallableError(
      prober.call('requestPairing', { code: 'ZZZ999' }),
      'functions/resource-exhausted',
      'rate-limited',
    );
    await expectCallableError(
      prober.call('requestPairing', { code: validCode }),
      'functions/resource-exhausted',
      'rate-limited',
    );
  });

  test('the budget resets once the window has passed', async () => {
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
      user.call('requestPairing', { code: 'ZZZ999' }),
      'functions/not-found',
      'code-not-found',
    );
  });
});

describe('cancelPairingRequest', () => {
  async function pendingRequest() {
    const owner = await newUser();
    await seedProfile(owner.uid);
    const code = (await owner.call('ensurePairingCode')).data.code;
    const sender = await newUser();
    await seedProfile(sender.uid);
    const { data } = await sender.call('requestPairing', { code });
    return { sender, owner, requestId: data.requestId };
  }

  test('the sender can cancel a pending request', async () => {
    const { sender, requestId } = await pendingRequest();
    await sender.call('cancelPairingRequest', { requestId });
    const request = await readDoc(`pairingRequests/${requestId}`);
    assert.equal(request.status, 'cancelled');
  });

  test('the recipient cannot cancel it', async () => {
    const { owner, requestId } = await pendingRequest();
    await expectCallableError(
      owner.call('cancelPairingRequest', { requestId }),
      'functions/permission-denied',
      'not-sender',
    );
  });

  test('a settled request cannot be cancelled again', async () => {
    const { sender, requestId } = await pendingRequest();
    await sender.call('cancelPairingRequest', { requestId });
    await expectCallableError(
      sender.call('cancelPairingRequest', { requestId }),
      'functions/failed-precondition',
      'request-not-pending',
    );
  });

  test('an unknown request is not-found', async () => {
    const user = await newUser();
    await seedProfile(user.uid);
    await expectCallableError(
      user.call('cancelPairingRequest', { requestId: 'nope' }),
      'functions/not-found',
      'request-not-found',
    );
  });
});
