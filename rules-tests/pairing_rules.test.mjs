// Security Rules tests for the pairing collections — part of P2-11.
// Run: cd rules-tests && npm test   (emulator must be up)

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

const ALICE = 'uid-alice';
const BOB = 'uid-bob';
const EVE = 'uid-eve';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    // Own namespace: node --test runs files in parallel, and a shared
    // project would let one file's clearFirestore() wipe another's seed.
    projectId: 'onceling-rules-pairing',
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: readFileSync('../firestore.rules', 'utf8'),
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  // A claimed code, a pending request Bob→Alice, and a budget row for Bob.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'pairingCodes', 'ABC234'), {
      ownerId: ALICE,
      createdAt: new Date(),
    });
    await setDoc(doc(db, 'pairingRequests', 'req-1'), {
      fromUid: BOB,
      toUid: ALICE,
      status: 'pending',
      createdAt: new Date(),
    });
    await setDoc(doc(db, 'rateLimits', BOB), {
      windowStart: new Date(),
      count: 3,
    });
  });
});

function db(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

describe('pairingCodes — sealed to clients', () => {
  test('cannot be read by id, even by the owner', async () => {
    await assertFails(getDoc(doc(db(ALICE), 'pairingCodes', 'ABC234')));
    await assertFails(getDoc(doc(db(BOB), 'pairingCodes', 'ABC234')));
  });

  test('cannot be found by query — no owner lookup, no enumeration', async () => {
    await assertFails(
      getDocs(
        query(
          collection(db(BOB), 'pairingCodes'),
          where('ownerId', '==', ALICE),
        ),
      ),
    );
    await assertFails(getDocs(collection(db(BOB), 'pairingCodes')));
  });

  test('cannot be written — claimed only via the callable', async () => {
    await assertFails(
      setDoc(doc(db(EVE), 'pairingCodes', 'ZZZ999'), { ownerId: EVE }),
    );
    await assertFails(
      updateDoc(doc(db(EVE), 'pairingCodes', 'ABC234'), { ownerId: EVE }),
    );
    await assertFails(deleteDoc(doc(db(ALICE), 'pairingCodes', 'ABC234')));
  });
});

describe('pairingRequests — participants only', () => {
  test('the sender can read their request', async () => {
    await assertSucceeds(getDoc(doc(db(BOB), 'pairingRequests', 'req-1')));
  });

  test('the recipient can read their request', async () => {
    await assertSucceeds(getDoc(doc(db(ALICE), 'pairingRequests', 'req-1')));
  });

  test('a third party cannot read it', async () => {
    await assertFails(getDoc(doc(db(EVE), 'pairingRequests', 'req-1')));
  });

  test('list scoped to own uid is allowed, both directions', async () => {
    await assertSucceeds(
      getDocs(
        query(
          collection(db(BOB), 'pairingRequests'),
          where('fromUid', '==', BOB),
        ),
      ),
    );
    await assertSucceeds(
      getDocs(
        query(
          collection(db(ALICE), 'pairingRequests'),
          where('toUid', '==', ALICE),
        ),
      ),
    );
  });

  test('list aimed at someone else is rejected', async () => {
    await assertFails(
      getDocs(
        query(
          collection(db(EVE), 'pairingRequests'),
          where('toUid', '==', ALICE),
        ),
      ),
    );
    await assertFails(getDocs(collection(db(EVE), 'pairingRequests')));
  });

  test('no direct writes, not even by participants', async () => {
    await assertFails(
      setDoc(doc(db(BOB), 'pairingRequests', 'req-new'), {
        fromUid: BOB,
        toUid: ALICE,
        status: 'pending',
        createdAt: new Date(),
      }),
    );
    // The interesting one: the recipient "accepting" by editing the status.
    await assertFails(
      updateDoc(doc(db(ALICE), 'pairingRequests', 'req-1'), {
        status: 'accepted',
      }),
    );
    await assertFails(deleteDoc(doc(db(BOB), 'pairingRequests', 'req-1')));
  });
});

describe('rateLimits — no client access at all', () => {
  test('own budget is not readable — no probing oracle', async () => {
    await assertFails(getDoc(doc(db(BOB), 'rateLimits', BOB)));
  });

  test('own budget is not writable — no refills', async () => {
    await assertFails(
      setDoc(doc(db(BOB), 'rateLimits', BOB), {
        windowStart: new Date(),
        count: 0,
      }),
    );
    await assertFails(deleteDoc(doc(db(BOB), 'rateLimits', BOB)));
  });
});

describe('users — the server-owned pairingCode field', () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'users', ALICE), {
        displayName: 'Alice',
        avatarUrl: null,
        coupleId: null,
        favoriteEmojis: ['❤️'],
        accentColor: null,
        createdAt: new Date('2026-07-01T10:00:00Z'),
        pairingCode: 'ABC234',
      });
    });
  });

  test('a profile edit while a code is present succeeds', async () => {
    await assertSucceeds(
      updateDoc(doc(db(ALICE), 'users', ALICE), { displayName: 'Alice B' }),
    );
  });

  test('the owner cannot change their code', async () => {
    await assertFails(
      updateDoc(doc(db(ALICE), 'users', ALICE), { pairingCode: 'ZZZ999' }),
    );
  });

  test('the owner cannot clear their code', async () => {
    await assertFails(
      updateDoc(doc(db(ALICE), 'users', ALICE), { pairingCode: null }),
    );
  });

  test('create cannot smuggle a code in', async () => {
    await assertFails(
      setDoc(doc(db(BOB), 'users', BOB), {
        displayName: 'Bob',
        avatarUrl: null,
        coupleId: null,
        favoriteEmojis: [],
        accentColor: null,
        createdAt: new Date(),
        pairingCode: 'BBB222',
      }),
    );
  });
});
