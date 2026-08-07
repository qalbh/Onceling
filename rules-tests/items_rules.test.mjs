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
  writeBatch,
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

// The writes the P2-12 client actually makes, in the exact shape it makes
// them. The tests above prove the rules; these prove the *app* satisfies them.
//
// Source of truth for these payloads is `itemCreatePayload` and
// `secretBodyPayload` in `lib/features/feed/models/feed_item_mapper.dart`.
// Dart and JS cannot share a constant, so a change there must be mirrored
// here — and a `flutter test` alone would not catch the drift, because the
// Dart side has no rules engine behind it.
describe('P2-12 — the client\'s own payloads', () => {
  test('a text send is accepted', async () => {
    await assertSucceeds(
      setDoc(doc(db(ALICE), 'items', 'p2-12-text'), {
        senderId: ALICE,
        reactions: {},
        type: 'text',
        body: 'be there in ten',
        coupleId: OURS,
        createdAt: serverTimestamp(),
      }),
    );
  });

  test('an emoji send is accepted, count and all', async () => {
    await assertSucceeds(
      setDoc(doc(db(ALICE), 'items', 'p2-12-emoji'), {
        senderId: ALICE,
        reactions: {},
        type: 'emoji',
        emoji: '🧋',
        count: 1,
        coupleId: OURS,
        createdAt: serverTimestamp(),
      }),
    );
  });

  test('a timed secret is accepted with no openingStartedAt', async () => {
    // The mapper strips null-valued keys, so the field P3-01 owns is absent
    // rather than null. It is not in itemKeysFor('secret') at all.
    await assertSucceeds(
      setDoc(doc(db(ALICE), 'items', 'p2-12-secret'), {
        senderId: ALICE,
        reactions: {},
        type: 'secret',
        secretState: 'sealed',
        revealDurationSeconds: 10,
        heldFullCountdown: false,
        coupleId: OURS,
        createdAt: serverTimestamp(),
      }),
    );
  });

  test('an untilClosed secret OMITS revealDurationSeconds rather than nulling it', async () => {
    await assertSucceeds(
      setDoc(doc(db(ALICE), 'items', 'p2-12-untilclosed'), {
        senderId: ALICE,
        reactions: {},
        type: 'secret',
        secretState: 'sealed',
        heldFullCountdown: false,
        coupleId: OURS,
        createdAt: serverTimestamp(),
      }),
    );
  });

  test('the same secret WITH a null openingStartedAt is rejected', async () => {
    // The reason the mapper strips nulls, asserted rather than asserted-about:
    // in Firestore an explicit null is a present key, and hasOnly() counts it.
    await assertFails(
      setDoc(doc(db(ALICE), 'items', 'p2-12-nulled'), {
        senderId: ALICE,
        reactions: {},
        type: 'secret',
        secretState: 'sealed',
        revealDurationSeconds: 10,
        openingStartedAt: null,
        heldFullCountdown: false,
        coupleId: OURS,
        createdAt: serverTimestamp(),
      }),
    );
  });

  test('a client cannot open its own secret by creating it as opening', async () => {
    // P3-01 owns sealed -> opening, and it runs on the Admin SDK. A client
    // that could create an item already `opening` would hand itself a
    // readable body.
    await assertFails(
      setDoc(doc(db(ALICE), 'items', 'p2-12-selfopen'), {
        senderId: ALICE,
        reactions: {},
        type: 'secret',
        secretState: 'opening',
        revealDurationSeconds: 10,
        heldFullCountdown: false,
        coupleId: OURS,
        createdAt: serverTimestamp(),
      }),
    );
  });

  test('a reaction goes in as a FIELD PATH merge, not a map replace', async () => {
    // What FirestoreFeedService.react() sends: `{'reactions.<uid>': emoji}`.
    // A different write shape from the whole-map replace tested above, and
    // the one that actually ships.
    await testEnv.withSecurityRulesDisabled((c) =>
      updateDoc(doc(c.firestore(), 'items', 'ours-1'), {
        reactions: { [ALICE]: '🥹' },
      }),
    );

    await assertSucceeds(
      updateDoc(doc(db(BOB), 'items', 'ours-1'), { [`reactions.${BOB}`]: '😮' }),
    );

    // ...and it merged rather than replaced: Alice's reaction survived.
    let stored;
    await testEnv.withSecurityRulesDisabled(async (c) => {
      stored = (await getDoc(doc(c.firestore(), 'items', 'ours-1'))).data();
    });
    assert.deepEqual(stored.reactions, { [ALICE]: '🥹', [BOB]: '😮' });
  });

  test('a field-path merge cannot touch the partner\'s key either', async () => {
    await assertFails(
      updateDoc(doc(db(BOB), 'items', 'ours-1'), {
        [`reactions.${ALICE}`]: '😮',
      }),
    );
  });

  test('the secret batch is all-or-nothing at the rules layer', async () => {
    // FirestoreFeedService.sendSecret() commits the item and its body
    // together. A batch fails whole if any write in it is denied, so a
    // malformed body cannot leave a bodyless secret behind.
    const alice = db(ALICE);
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'items', 'p2-12-batch'), {
      senderId: ALICE,
      reactions: {},
      type: 'secret',
      secretState: 'sealed',
      revealDurationSeconds: 10,
      heldFullCountdown: false,
      coupleId: OURS,
      createdAt: serverTimestamp(),
    });
    // Missing coupleId — the field P2-36's sweep needs.
    batch.set(doc(alice, 'secretBodies', 'p2-12-batch'), {
      senderId: ALICE,
      body: 'this should not survive',
      createdAt: serverTimestamp(),
    });
    await assertFails(batch.commit());

    let orphanExists;
    await testEnv.withSecurityRulesDisabled(async (c) => {
      orphanExists = (
        await getDoc(doc(c.firestore(), 'items', 'p2-12-batch'))
      ).exists();
    });
    assert.equal(orphanExists, false, 'the item must not have landed alone');
  });

  test('a well-formed batch lands both documents', async () => {
    const alice = db(ALICE);
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'items', 'p2-12-ok'), {
      senderId: ALICE,
      reactions: {},
      type: 'secret',
      secretState: 'sealed',
      revealDurationSeconds: 10,
      heldFullCountdown: false,
      coupleId: OURS,
      createdAt: serverTimestamp(),
    });
    batch.set(doc(alice, 'secretBodies', 'p2-12-ok'), {
      coupleId: OURS,
      senderId: ALICE,
      body: 'the surprise is a dog',
      createdAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  test('a grown pagination window is still a permitted query', async () => {
    // Pagination is one growing limit, not startAfter — page two is the same
    // query asking for more. The rule must not care how large the window is.
    for (const size of [30, 60, 90]) {
      await assertSucceeds(
        getDocs(
          query(
            collection(db(ALICE), 'items'),
            where('coupleId', '==', OURS),
            orderBy('createdAt', 'desc'),
            limit(size),
          ),
        ),
      );
    }
  });
});

// P3-01 bounded `untilClosed`, which used to gate on state alone and stay
// readable for as long as it stayed `opening`. The ceiling is the same hour
// isWellFormedItem already caps revealDurationSeconds at, so the invariant is
// uniform: no reveal session outlasts an hour.
describe('P3-01 — the untilClosed ceiling', () => {
  const hoursAgo = (n) => new Date(Date.now() - n * 3600 * 1000);

  test('an untilClosed body is readable inside the hour', async () => {
    await testEnv.withSecurityRulesDisabled(async (c) => {
      const raw = c.firestore();
      await setDoc(doc(raw, 'items', 'uc-fresh'), item({
        type: 'secret', secretState: 'opening', body: null,
        openingStartedAt: new Date(Date.now() - 60 * 1000),
      }));
      await setDoc(doc(raw, 'secretBodies', 'uc-fresh'), {
        coupleId: OURS, senderId: ALICE, body: 'still readable',
        createdAt: new Date(),
      });
    });
    await assertSucceeds(getDoc(doc(db(BOB), 'secretBodies', 'uc-fresh')));
  });

  test('an untilClosed body is DENIED past the hour', async () => {
    // The case that used to be readable forever. A reader who never finishes
    // would otherwise leave the text on the server indefinitely, which is the
    // retention brief §10 promises against.
    await testEnv.withSecurityRulesDisabled(async (c) => {
      const raw = c.firestore();
      await setDoc(doc(raw, 'items', 'uc-stale'), item({
        type: 'secret', secretState: 'opening', body: null,
        openingStartedAt: hoursAgo(2),
      }));
      await setDoc(doc(raw, 'secretBodies', 'uc-stale'), {
        coupleId: OURS, senderId: ALICE, body: 'should be unreachable',
        createdAt: new Date(),
      });
    });
    await assertFails(getDoc(doc(db(BOB), 'secretBodies', 'uc-stale')));
  });

  test('a timed secret keeps its own shorter window, not the ceiling', async () => {
    // The ceiling is a backstop, never a promotion: a 30s secret must not
    // become readable for an hour because the fallback exists.
    await testEnv.withSecurityRulesDisabled(async (c) => {
      const raw = c.firestore();
      await setDoc(doc(raw, 'items', 'timed-stale'), item({
        type: 'secret', secretState: 'opening', body: null,
        revealDurationSeconds: 30,
        openingStartedAt: new Date(Date.now() - 5 * 60 * 1000),
      }));
      await setDoc(doc(raw, 'secretBodies', 'timed-stale'), {
        coupleId: OURS, senderId: ALICE, body: 'expired long ago',
        createdAt: new Date(),
      });
    });
    await assertFails(getDoc(doc(db(BOB), 'secretBodies', 'timed-stale')));
  });
});

// Raised by the P3-01 audit: the Admin SDK stamps `openingStartedAt`, which
// itemKeysFor('secret') did not list. Reactions still worked because
// isWellFormedItem does not run on update — but that is a coincidence worth
// pinning, and the key set now matches the stored shape either way.
describe('P3-01 — a stamped secret is still a normal item', () => {
  test('the recipient can still react to a secret being opened', async () => {
    await assertSucceeds(
      updateDoc(doc(db(BOB), 'items', 'opening-1'), {
        [`reactions.${BOB}`]: '🥹',
      }),
    );
  });

  test('reacting still cannot smuggle a state change alongside it', async () => {
    await assertFails(
      updateDoc(doc(db(BOB), 'items', 'opening-1'), {
        [`reactions.${BOB}`]: '🥹',
        secretState: 'opened',
      }),
    );
  });

  test('a client still cannot create an item already `opening`', async () => {
    // The path that would self-authorise a body read.
    await assertFails(
      setDoc(doc(db(ALICE), 'items', 'self-open'), item({
        type: 'secret',
        secretState: 'opening',
        openingStartedAt: serverTimestamp(),
        revealDurationSeconds: 30,
        body: null,
        createdAt: serverTimestamp(),
      })),
    );
  });

  test('a client cannot stamp openingStartedAt on a sealed create either', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'items', 'presrtamped'), item({
        type: 'secret',
        secretState: 'sealed',
        openingStartedAt: serverTimestamp(),
        revealDurationSeconds: 30,
        body: null,
        createdAt: serverTimestamp(),
      })),
    );
  });
});

describe('P3-03 — milestone items are the server\'s testimony', () => {
  test('a client cannot create one, even perfectly formed', async () => {
    // The create enum deliberately excludes 'milestone'. Only the scheduled
    // tick writes these, with the Admin SDK — a couple's history of
    // milestones is the server's record, not something a member can author.
    await assertFails(
      setDoc(doc(db(ALICE), 'items', 'forged-milestone'), {
        coupleId: OURS,
        type: 'milestone',
        day: 100,
        reactions: {},
        createdAt: serverTimestamp(),
      }),
    );
  });

  test('members can REACT to one — it is still an item in their thread', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'items', 'ms-1'), {
        coupleId: OURS,
        type: 'milestone',
        day: 100,
        reactions: {},
        createdAt: new Date(),
      });
    });
    await assertSucceeds(
      updateDoc(doc(db(ALICE), 'items', 'ms-1'), {
        'reactions.alice': '🥰',
      }),
    );
  });

  test('a non-member cannot read it', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'items', 'ms-2'), {
        coupleId: OURS,
        type: 'milestone',
        day: 100,
        reactions: {},
        createdAt: new Date(),
      });
    });
    await assertFails(getDoc(doc(db(EVE), 'items', 'ms-2')));
  });
});
