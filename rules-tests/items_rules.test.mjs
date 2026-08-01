// Security Rules tests for items and secretBodies (P2-10, P2-11).
// Run: cd rules-tests && npm test   (emulator must be up)
//
// Own project namespace: node --test runs files in parallel and a shared
// project would let one file's clearFirestore() wipe another's seed.

import assert from 'node:assert/strict';
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
  limit,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

const ALICE = 'alice';
const BOB = 'bob';
const EVE = 'eve';
const OURS = 'couple-ab';
const THEIRS = 'couple-eve';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'onceling-rules-items',
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

const db = (uid) => testEnv.authenticatedContext(uid).firestore();
const anon = () => testEnv.unauthenticatedContext().firestore();

function profile(coupleId) {
  return {
    displayName: 'Someone',
    avatarUrl: null,
    coupleId,
    favoriteEmojis: [],
    accentColor: null,
    createdAt: new Date(),
  };
}

/** A well-formed item, as toFirestore() writes one. */
function item(overrides = {}) {
  return {
    coupleId: OURS,
    senderId: ALICE,
    type: 'text',
    createdAt: new Date(),
    reactions: {},
    body: 'hello',
    ...overrides,
  };
}

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const raw = context.firestore();
    // Alice and Bob are a couple; Eve is in her own.
    await setDoc(doc(raw, 'users', ALICE), profile(OURS));
    await setDoc(doc(raw, 'users', BOB), profile(OURS));
    await setDoc(doc(raw, 'users', EVE), profile(THEIRS));

    await setDoc(doc(raw, 'items', 'ours-1'), item());
    await setDoc(doc(raw, 'items', 'ours-2'), item({ senderId: BOB, body: 'hi' }));
    await setDoc(doc(raw, 'items', 'theirs-1'), item({ coupleId: THEIRS, senderId: EVE }));

    // Every secret state, each with a body, so the window can be pinned.
    const bodyFor = (id) =>
      setDoc(doc(raw, 'secretBodies', id), {
        coupleId: OURS,
        senderId: ALICE,
        body: 'the secret',
        createdAt: new Date(),
      });

    await setDoc(doc(raw, 'items', 'sealed-1'), item({
      type: 'secret', secretState: 'sealed', revealDurationSeconds: 30,
      body: null,
    }));
    await bodyFor('sealed-1');

    // Opening, window still running.
    await setDoc(doc(raw, 'items', 'opening-1'), item({
      type: 'secret', secretState: 'opening', revealDurationSeconds: 30,
      openingStartedAt: new Date(), body: null,
    }));
    await bodyFor('opening-1');

    // Opening, window long past.
    await setDoc(doc(raw, 'items', 'opening-expired'), item({
      type: 'secret', secretState: 'opening', revealDurationSeconds: 30,
      openingStartedAt: new Date(Date.now() - 600_000), body: null,
    }));
    await bodyFor('opening-expired');

    // Opening with no start time — malformed, must fail closed.
    await setDoc(doc(raw, 'items', 'opening-nostart'), item({
      type: 'secret', secretState: 'opening', revealDurationSeconds: 30,
      body: null,
    }));
    await bodyFor('opening-nostart');

    // untilClosed: no numeric window, so state alone gates it.
    await setDoc(doc(raw, 'items', 'opening-untilclosed'), item({
      type: 'secret', secretState: 'opening', openingStartedAt: new Date(),
      body: null,
    }));
    await bodyFor('opening-untilclosed');

    // An already-opened secret, whose body should no longer be readable.
    await setDoc(doc(raw, 'items', 'opened-1'), item({
      type: 'secret',
      secretState: 'opened',
      revealDurationSeconds: 30,
      body: null,
    }));
    await setDoc(doc(raw, 'secretBodies', 'opened-1'), {
      coupleId: OURS,
      senderId: ALICE,
      body: 'already seen',
      createdAt: new Date(),
    });

    // Eve's own secret, to prove cross-couple denial.
    await setDoc(doc(raw, 'items', 'theirs-secret'), item({
      coupleId: THEIRS,
      senderId: EVE,
      type: 'secret',
      secretState: 'sealed',
      body: null,
    }));
    await setDoc(doc(raw, 'secretBodies', 'theirs-secret'), {
      coupleId: THEIRS,
      senderId: EVE,
      body: 'not yours',
      createdAt: new Date(),
    });
  });
});

describe('items — reads are scoped to the couple', () => {
  test('a member reads their own couple by id', async () => {
    await assertSucceeds(getDoc(doc(db(ALICE), 'items', 'ours-1')));
    await assertSucceeds(getDoc(doc(db(BOB), 'items', 'ours-1')));
  });

  test('a scoped, ordered, paginated query is allowed — P2-12 needs this', async () => {
    await assertSucceeds(
      getDocs(
        query(
          collection(db(ALICE), 'items'),
          where('coupleId', '==', OURS),
          orderBy('createdAt', 'desc'),
          limit(20),
        ),
      ),
    );
  });

  test('an outsider cannot read an item by id', async () => {
    await assertFails(getDoc(doc(db(EVE), 'items', 'ours-1')));
  });

  test('a member cannot read another couple by id', async () => {
    await assertFails(getDoc(doc(db(ALICE), 'items', 'theirs-1')));
  });

  test('an UNFILTERED query is rejected', async () => {
    await assertFails(getDocs(collection(db(ALICE), 'items')));
  });

  test('a query scoped to someone else\'s couple is rejected', async () => {
    await assertFails(
      getDocs(
        query(collection(db(ALICE), 'items'), where('coupleId', '==', THEIRS)),
      ),
    );
  });

  test('an unpaired user reads nothing — null must match no couple', async () => {
    await testEnv.withSecurityRulesDisabled((c) =>
      setDoc(doc(c.firestore(), 'users', 'lonely'), profile(null)),
    );
    await assertFails(getDoc(doc(db('lonely'), 'items', 'ours-1')));
  });

  test('anonymous callers are denied', async () => {
    await assertFails(getDoc(doc(anon(), 'items', 'ours-1')));
    await assertFails(getDocs(collection(anon(), 'items')));
  });
});

describe('items — create', () => {
  test('a member writes a well-formed item', async () => {
    await assertSucceeds(
      setDoc(doc(db(ALICE), 'items', 'new-1'), item({ createdAt: serverTimestamp() })),
    );
  });

  test('cannot forge a senderId', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'items', 'forged'), item({
        senderId: BOB,
        createdAt: serverTimestamp(),
      })),
    );
  });

  test('cannot write into another couple', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'items', 'trespass'), item({
        coupleId: THEIRS,
        createdAt: serverTimestamp(),
      })),
    );
  });

  test('cannot back-date createdAt', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'items', 'backdated'), item({
        createdAt: new Date('2020-01-01T00:00:00Z'),
      })),
    );
  });

  test('cannot arrive with reactions already on it', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'items', 'prereacted'), item({
        createdAt: serverTimestamp(),
        reactions: { [BOB]: '❤️' },
      })),
    );
  });

  test('an unknown type is rejected', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'items', 'weird'), item({
        type: 'ransom',
        createdAt: serverTimestamp(),
      })),
    );
  });

  test('an unknown field is rejected', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'items', 'extra'), item({
        createdAt: serverTimestamp(),
        isAdmin: true,
      })),
    );
  });

  test('an over-long body is rejected', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'items', 'huge'), item({
        createdAt: serverTimestamp(),
        body: 'x'.repeat(2001),
      })),
    );
  });

  test('openedAt must be a timestamp', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'items', 'bad-openedat'), item({
        type: 'secret',
        secretState: 'sealed',
        openedAt: 'not-a-time',
        body: null,
        createdAt: serverTimestamp(),
      })),
    );
  });

  test('a text item cannot smuggle secret fields', async () => {
    // Keys are validated per type, not as a union: a union let a text item
    // carry secretState, which the P2-06 mapper would silently ignore while
    // the document claimed to be something it is not.
    await assertFails(
      setDoc(doc(db(ALICE), 'items', 'smuggle'), item({
        createdAt: serverTimestamp(),
        secretState: 'sealed',
      })),
    );
  });

  test('a photo item cannot carry emoji-only fields', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'items', 'wrong-shape'), item({
        type: 'photo',
        mediaUrl: 'https://example.test/p.jpg',
        count: 3,
        body: null,
        createdAt: serverTimestamp(),
      })),
    );
  });

  test('each type accepts its own shape', async () => {
    await assertSucceeds(
      setDoc(doc(db(ALICE), 'items', 'ok-photo'), {
        coupleId: OURS, senderId: ALICE, type: 'photo',
        createdAt: serverTimestamp(), reactions: {},
        mediaUrl: 'https://example.test/p.jpg', caption: 'us',
      }),
    );
    await assertSucceeds(
      setDoc(doc(db(ALICE), 'items', 'ok-emoji'), {
        coupleId: OURS, senderId: ALICE, type: 'emoji',
        createdAt: serverTimestamp(), reactions: {}, emoji: '❤️', count: 3,
      }),
    );
    await assertSucceeds(
      setDoc(doc(db(ALICE), 'items', 'ok-secret'), {
        coupleId: OURS, senderId: ALICE, type: 'secret',
        createdAt: serverTimestamp(), reactions: {},
        secretState: 'sealed', revealDurationSeconds: 30,
        openedAt: null, heldFullCountdown: false,
      }),
    );
  });

  test('anonymous cannot create', async () => {
    await assertFails(
      setDoc(doc(anon(), 'items', 'anon-1'), item({ createdAt: serverTimestamp() })),
    );
  });
});

describe('items — update is reactions, and only your own', () => {
  test('a member adds their own reaction', async () => {
    await assertSucceeds(
      updateDoc(doc(db(BOB), 'items', 'ours-1'), { reactions: { [BOB]: '❤️' } }),
    );
  });

  test('a member changes their own reaction', async () => {
    await testEnv.withSecurityRulesDisabled((c) =>
      updateDoc(doc(c.firestore(), 'items', 'ours-1'), { reactions: { [BOB]: '❤️' } }),
    );
    await assertSucceeds(
      updateDoc(doc(db(BOB), 'items', 'ours-1'), { reactions: { [BOB]: '😂' } }),
    );
  });

  test('cannot touch the PARTNER\'S reaction entry', async () => {
    await testEnv.withSecurityRulesDisabled((c) =>
      updateDoc(doc(c.firestore(), 'items', 'ours-1'), { reactions: { [ALICE]: '❤️' } }),
    );
    // Bob rewriting Alice's reaction.
    await assertFails(
      updateDoc(doc(db(BOB), 'items', 'ours-1'), { reactions: { [ALICE]: '💔' } }),
    );
  });

  test('cannot clear the partner\'s reaction by replacing the map', async () => {
    await testEnv.withSecurityRulesDisabled((c) =>
      updateDoc(doc(c.firestore(), 'items', 'ours-1'), { reactions: { [ALICE]: '❤️' } }),
    );
    await assertFails(
      updateDoc(doc(db(BOB), 'items', 'ours-1'), { reactions: {} }),
    );
  });

  test('cannot edit the body', async () => {
    await assertFails(
      updateDoc(doc(db(ALICE), 'items', 'ours-1'), { body: 'rewritten' }),
    );
  });

  test('cannot move an item to another couple', async () => {
    await assertFails(
      updateDoc(doc(db(ALICE), 'items', 'ours-1'), { coupleId: THEIRS }),
    );
  });

  test('cannot flip a secret to opened', async () => {
    // The state transition is server-side; a client that could set it would
    // control when a body becomes unreadable.
    await assertFails(
      updateDoc(doc(db(BOB), 'items', 'sealed-1'), { secretState: 'opened' }),
    );
  });

  test('an outsider cannot react at all', async () => {
    await assertFails(
      updateDoc(doc(db(EVE), 'items', 'ours-1'), { reactions: { [EVE]: '👀' } }),
    );
  });
});

describe('items — delete', () => {
  test('nobody deletes an item, not even its author', async () => {
    await assertFails(deleteDoc(doc(db(ALICE), 'items', 'ours-1')));
    await assertFails(deleteDoc(doc(db(BOB), 'items', 'ours-1')));
    await assertFails(deleteDoc(doc(db(EVE), 'items', 'theirs-1')));
    await assertFails(deleteDoc(doc(anon(), 'items', 'ours-1')));
  });
});

describe('secretBodies', () => {
  test('the recipient reads a body while the window is open', async () => {
    await assertSucceeds(getDoc(doc(db(BOB), 'secretBodies', 'opening-1')));
  });

  test('a SEALED body is not readable — opening is a real state', async () => {
    // With two states "while opening" meant "while sealed", i.e. every
    // unopened secret forever. That is the retention brief §10 forbids.
    await assertFails(getDoc(doc(db(BOB), 'secretBodies', 'sealed-1')));
  });

  test('an EXPIRED window is denied', async () => {
    await assertFails(getDoc(doc(db(BOB), 'secretBodies', 'opening-expired')));
  });

  test('opening with no start time fails closed', async () => {
    await assertFails(getDoc(doc(db(BOB), 'secretBodies', 'opening-nostart')));
  });

  test('untilClosed has no clock, so state alone gates it', async () => {
    await assertSucceeds(
      getDoc(doc(db(BOB), 'secretBodies', 'opening-untilclosed')),
    );
  });

  test('the SENDER cannot read their own body back', async () => {
    // Brief §10: the body is for the recipient, once.
    await assertFails(getDoc(doc(db(ALICE), 'secretBodies', 'opening-1')));
  });

  test('nobody reads a body whose item is already opened', async () => {
    await assertFails(getDoc(doc(db(BOB), 'secretBodies', 'opened-1')));
  });

  test('an outsider cannot read a body mid-window', async () => {
    await assertFails(getDoc(doc(db(EVE), 'secretBodies', 'opening-1')));
  });

  test('a member cannot read another couple\'s body', async () => {
    await assertFails(getDoc(doc(db(ALICE), 'secretBodies', 'theirs-secret')));
    await assertFails(getDoc(doc(db(BOB), 'secretBodies', 'theirs-secret')));
  });

  test('bodies cannot be listed or enumerated', async () => {
    await assertFails(getDocs(collection(db(BOB), 'secretBodies')));
    await assertFails(
      getDocs(
        query(collection(db(BOB), 'secretBodies'), where('coupleId', '==', OURS)),
      ),
    );
  });

  test('the sender creates a body', async () => {
    await assertSucceeds(
      setDoc(doc(db(ALICE), 'secretBodies', 'new-secret'), {
        coupleId: OURS,
        senderId: ALICE,
        body: 'for you',
        createdAt: serverTimestamp(),
      }),
    );
  });

  test('cannot create a body attributed to someone else', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'secretBodies', 'forged-body'), {
        coupleId: OURS,
        senderId: BOB,
        body: 'not mine to send',
        createdAt: serverTimestamp(),
      }),
    );
  });

  test('cannot create a body in another couple', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'secretBodies', 'trespass-body'), {
        coupleId: THEIRS,
        senderId: ALICE,
        body: 'x',
        createdAt: serverTimestamp(),
      }),
    );
  });

  test('a body without coupleId is rejected — the sweep needs it', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'secretBodies', 'orphan-body'), {
        senderId: ALICE,
        body: 'unreachable by P2-36',
        createdAt: serverTimestamp(),
      }),
    );
  });

  test('bodies are never updated or deleted by a client', async () => {
    await assertFails(
      updateDoc(doc(db(ALICE), 'secretBodies', 'opening-1'), { body: 'edited' }),
    );
    await assertFails(deleteDoc(doc(db(ALICE), 'secretBodies', 'opening-1')));
    await assertFails(deleteDoc(doc(db(BOB), 'secretBodies', 'opening-1')));
  });

  test('anonymous is denied everywhere', async () => {
    await assertFails(getDoc(doc(anon(), 'secretBodies', 'opening-1')));
    await assertFails(
      setDoc(doc(anon(), 'secretBodies', 'anon-body'), {
        coupleId: OURS,
        senderId: ALICE,
        body: 'x',
        createdAt: serverTimestamp(),
      }),
    );
  });
});
