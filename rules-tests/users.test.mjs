// Firestore Security Rules tests for users/{uid} — part of P2-11.
//
// Requires the Firestore emulator on 8080 (`firebase emulators:start`).
// Run: cd rules-tests && npm test

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, deleteDoc, serverTimestamp, updateDoc } from 'firebase/firestore';

const ALICE = 'uid-alice';
const BOB = 'uid-bob';

/** A well-formed profile, exactly the six keys the rules require. */
function profile(overrides = {}) {
  return {
    displayName: 'Alice',
    avatarUrl: null,
    coupleId: null,
    favoriteEmojis: ['❤️', '😂'],
    accentColor: null,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'qalb-coupleapp-dev',
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
});

/** Seeds a document straight past the rules, so tests start from a real row. */
async function seedProfile(uid, data = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users', uid), {
      displayName: 'Alice',
      avatarUrl: null,
      coupleId: null,
      favoriteEmojis: ['❤️'],
      accentColor: null,
      createdAt: new Date('2026-07-01T10:00:00Z'),
      ...data,
    });
  });
}

function db(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

describe('users/{uid} — read', () => {
  test('the owner can read their own document', async () => {
    await seedProfile(ALICE);
    await assertSucceeds(getDoc(doc(db(ALICE), 'users', ALICE)));
  });

  test('another signed-in user cannot read it', async () => {
    await seedProfile(ALICE);
    await assertFails(getDoc(doc(db(BOB), 'users', ALICE)));
  });

  test('a signed-out client cannot read it', async () => {
    await seedProfile(ALICE);
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, 'users', ALICE)));
  });
});

describe('users/{uid} — create', () => {
  test('the owner can create their own profile', async () => {
    await assertSucceeds(setDoc(doc(db(ALICE), 'users', ALICE), profile()));
  });

  test('cannot create a document for someone else', async () => {
    await assertFails(setDoc(doc(db(BOB), 'users', ALICE), profile()));
  });

  test('create with a non-null coupleId is rejected', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'users', ALICE), profile({ coupleId: 'couple-1' })),
    );
  });

  test('create with an extra field is rejected', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'users', ALICE), { ...profile(), isAdmin: true }),
    );
  });

  test('create missing a required field is rejected', async () => {
    const { accentColor, ...partial } = profile();
    void accentColor;
    await assertFails(setDoc(doc(db(ALICE), 'users', ALICE), partial));
  });

  test('create with an over-long displayName is rejected', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'users', ALICE), profile({ displayName: 'x'.repeat(41) })),
    );
  });

  test('create with an empty displayName is rejected', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'users', ALICE), profile({ displayName: '' })),
    );
  });

  test('create with a client-chosen createdAt is rejected', async () => {
    await assertFails(
      setDoc(
        doc(db(ALICE), 'users', ALICE),
        profile({ createdAt: new Date('2020-01-01T00:00:00Z') }),
      ),
    );
  });

  test('create with more than eight favourites is rejected', async () => {
    await assertFails(
      setDoc(
        doc(db(ALICE), 'users', ALICE),
        profile({ favoriteEmojis: Array(9).fill('❤️') }),
      ),
    );
  });
});

describe('users/{uid} — the coupleId invariant', () => {
  test('a user setting their own coupleId is REJECTED', async () => {
    await seedProfile(ALICE);
    await assertFails(
      updateDoc(doc(db(ALICE), 'users', ALICE), { coupleId: 'couple-1' }),
    );
  });

  test('a user CLEARING their coupleId is REJECTED', async () => {
    // An unrestricted clear orphans a couple: one partner paired to nobody,
    // the other paired to a ghost.
    await seedProfile(ALICE, { coupleId: 'couple-1' });
    await assertFails(
      updateDoc(doc(db(ALICE), 'users', ALICE), { coupleId: null }),
    );
  });

  test('a user changing coupleId to another couple is rejected', async () => {
    await seedProfile(ALICE, { coupleId: 'couple-1' });
    await assertFails(
      updateDoc(doc(db(ALICE), 'users', ALICE), { coupleId: 'couple-2' }),
    );
  });

  test('editing displayName while coupleId is present and unchanged SUCCEEDS', async () => {
    // The passing case that stops an over-strict rule from silently breaking
    // profile edits.
    await seedProfile(ALICE, { coupleId: 'couple-1' });
    await assertSucceeds(
      updateDoc(doc(db(ALICE), 'users', ALICE), { displayName: 'Alice B' }),
    );
  });

  test('editing displayName while unpaired succeeds', async () => {
    await seedProfile(ALICE);
    await assertSucceeds(
      updateDoc(doc(db(ALICE), 'users', ALICE), { displayName: 'Alice B' }),
    );
  });

  test('editing favourites succeeds', async () => {
    await seedProfile(ALICE);
    await assertSucceeds(
      updateDoc(doc(db(ALICE), 'users', ALICE), {
        favoriteEmojis: ['🔥', '🫶'],
      }),
    );
  });
});

describe('users/{uid} — update guards', () => {
  test('another user cannot edit the document', async () => {
    await seedProfile(ALICE);
    await assertFails(
      updateDoc(doc(db(BOB), 'users', ALICE), { displayName: 'Owned' }),
    );
  });

  test('cannot rewrite createdAt', async () => {
    await seedProfile(ALICE);
    await assertFails(
      updateDoc(doc(db(ALICE), 'users', ALICE), {
        createdAt: new Date('2020-01-01T00:00:00Z'),
      }),
    );
  });

  test('cannot add an unknown field on update', async () => {
    await seedProfile(ALICE);
    await assertFails(
      updateDoc(doc(db(ALICE), 'users', ALICE), { isAdmin: true }),
    );
  });

  test('cannot break displayName type on update', async () => {
    await seedProfile(ALICE);
    await assertFails(
      updateDoc(doc(db(ALICE), 'users', ALICE), { displayName: 42 }),
    );
  });
});

describe('users/{uid} — delete', () => {
  test('nobody can delete a profile, not even the owner', async () => {
    await seedProfile(ALICE);
    await assertFails(deleteDoc(doc(db(ALICE), 'users', ALICE)));
  });
});

describe('collections with no rules yet', () => {
  test('are closed by the catch-all deny', async () => {
    await assertFails(getDoc(doc(db(ALICE), 'couples', 'couple-1')));
    await assertFails(
      setDoc(doc(db(ALICE), 'pairingCodes', 'ABC123'), { uid: ALICE }),
    );
    await assertFails(setDoc(doc(db(ALICE), 'items', 'i1'), { body: 'hi' }));
  });
});

describe('sanity', () => {
  test('the rules file compiled', () => {
    assert.ok(testEnv, 'test environment initialised, so the rules parsed');
  });
});
