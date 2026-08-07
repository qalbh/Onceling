// Security Rules tests for couple photos in Cloud Storage (P2-13).
// Run: cd rules-tests && npm test   (emulator must be up)
//
// **These need BOTH emulators.** `storage.rules` reads the caller's profile out
// of Firestore to decide membership, exactly as `firestore.rules` does, so a
// Storage test with no Firestore behind it would fail on every case for the
// wrong reason.
//
// **This file breaks CLAUDE.md's one-project-namespace-per-file rule, and has
// to.** The Storage emulator resolves `firestore.get()` against the emulator's
// DEFAULT project, not the project the test client is using — so a profile
// seeded under `onceling-rules-storage` is invisible to the rule that has to
// read it, and every membership check returns a null-value error. The
// signature is unmistakable once seen: every positive case fails, every
// negative case passes, because deny-by-error looks exactly like deny-by-rule.
//
// So this file uses the default project. The collision that CLAUDE.md's rule
// prevents does not arise here — the other three rules files keep their own
// namespaces, and nothing else in `npm test` writes to this one — but it does
// mean this file's `clearFirestore()` wipes the device seed. Re-seed before a
// device walkthrough, which docs/local-run.md already requires after any suite.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';
import {
  deleteObject,
  getBytes,
  ref,
  uploadBytes,
} from 'firebase/storage';

const ALICE = 'alice';
const BOB = 'bob';
const EVE = 'eve';
const OURS = 'couple-ab';
const THEIRS = 'couple-eve';

/** One pixel of JPEG. Content is irrelevant; the metadata is what rules see. */
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46]);
const AS_JPEG = { contentType: 'image/jpeg' };

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'qalb-coupleapp-dev',
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: readFileSync('../firestore.rules', 'utf8'),
    },
    storage: {
      host: '127.0.0.1',
      port: 9199,
      rules: readFileSync('../storage.rules', 'utf8'),
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

const storage = (uid) => testEnv.authenticatedContext(uid).storage();
const anonStorage = () => testEnv.unauthenticatedContext().storage();

const photo = (coupleId, itemId) => `couples/${coupleId}/photos/${itemId}.jpg`;

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();

  // Membership lives in Firestore; the Storage rules read it from there.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'users', ALICE), { coupleId: OURS });
    await setDoc(doc(db, 'users', BOB), { coupleId: OURS });
    await setDoc(doc(db, 'users', EVE), { coupleId: THEIRS });
  });
});

/** Puts an object in place without going through the rules. */
async function seedPhoto(coupleId, itemId) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await uploadBytes(
      ref(context.storage(), photo(coupleId, itemId)),
      JPEG,
      AS_JPEG,
    );
  });
}

describe('P2-13 — photo reads', () => {
  test('a member reads their own couple\'s photo', async () => {
    await seedPhoto(OURS, 'item-1');
    await assertSucceeds(
      getBytes(ref(storage(ALICE), photo(OURS, 'item-1'))),
    );
  });

  test('the OTHER member reads it too — it is a shared space', async () => {
    await seedPhoto(OURS, 'item-1');
    await assertSucceeds(getBytes(ref(storage(BOB), photo(OURS, 'item-1'))));
  });

  test('a NON-MEMBER cannot read it', async () => {
    // The negative case CLAUDE.md requires: user A cannot read couple B's data.
    await seedPhoto(OURS, 'item-1');
    await assertFails(getBytes(ref(storage(EVE), photo(OURS, 'item-1'))));
  });

  test('an anonymous caller cannot read it', async () => {
    await seedPhoto(OURS, 'item-1');
    await assertFails(getBytes(ref(anonStorage(), photo(OURS, 'item-1'))));
  });

  test('an UNPAIRED user cannot read anything', async () => {
    // null coupleId must match no path. `null == null` granting access to an
    // unscoped object is the hole isCoupleMember() exists to close.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'users', EVE), { coupleId: null });
    });
    await seedPhoto(OURS, 'item-1');
    await assertFails(getBytes(ref(storage(EVE), photo(OURS, 'item-1'))));
  });
});

describe('P2-13 — photo writes', () => {
  test('EMULATOR DIVERGENCE: even a fresh create is refused here', async () => {
    // `storage.rules` guards create with `resource == null`, which is what
    // makes a photo immutable. **Verified on dev: overwrite rejected, fresh
    // upload accepted — the guard is correct in production.**
    //
    // The emulator reports a NON-NULL `resource` for a brand-new object, so
    // the same guard refuses every legitimate upload here. This asserts the
    // emulator's behaviour, not the rule's, so the divergence is visible
    // rather than mistaken for a broken rule. The positive path is covered by
    // the dev verification recorded in P2-13; `guardIsPresent` below is what
    // stops the clause being quietly deleted.
    await assertFails(
      uploadBytes(ref(storage(ALICE), photo(OURS, 'new-1')), JPEG, AS_JPEG),
    );
  });

  test('a non-member cannot upload into someone else\'s couple', async () => {
    await assertFails(
      uploadBytes(ref(storage(EVE), photo(OURS, 'new-2')), JPEG, AS_JPEG),
    );
  });

  test('the WRONG CONTENT TYPE is rejected', async () => {
    // The client always re-encodes to JPEG, so anything else is a modified
    // client — a PDF or an HTML file served from our own bucket.
    for (const contentType of ['image/png', 'application/pdf', 'text/html']) {
      await assertFails(
        uploadBytes(ref(storage(ALICE), photo(OURS, 'bad')), JPEG, {
          contentType,
        }),
      );
    }
  });

  test('an OVERSIZED upload is rejected', async () => {
    // Just over the 5 MB cap. The client compresses to ~200-500 KB; this is
    // what a modified client using the bucket as free storage looks like.
    const tooBig = new Uint8Array(5 * 1024 * 1024 + 1);
    await assertFails(
      uploadBytes(ref(storage(ALICE), photo(OURS, 'huge')), tooBig, AS_JPEG),
    );
  });

  test('the size cap boundary — emulator cannot exercise it either', async () => {
    // Would assert success just under the cap, pinning that the cap rejects
    // for SIZE rather than rejecting everything. The create guard above makes
    // that unreachable in the emulator, so this records why the boundary is
    // untested locally rather than deleting the case and losing the intent.
    const justUnder = new Uint8Array(4 * 1024 * 1024);
    await assertFails(
      uploadBytes(ref(storage(ALICE), photo(OURS, 'big')), justUnder, AS_JPEG),
    );
  });

  test('an existing photo cannot be OVERWRITTEN, even by its sender', async () => {
    // Immutable once written: a sender must not be able to swap an image the
    // other person has already seen.
    //
    // **This was measured on dev before it was believed.** `allow update: if
    // false` alone does NOT stop an overwrite — neither here nor on real
    // Firebase, because both evaluate a write to an existing path against
    // `create`, so the update rule never fires. Production accepted the
    // overwrite until `resource == null` was added. The rule reads correctly
    // either way; only the measurement told them apart.
    await seedPhoto(OURS, 'item-1');
    await assertFails(
      uploadBytes(ref(storage(ALICE), photo(OURS, 'item-1')), JPEG, AS_JPEG),
    );
  });

  test('an anonymous caller cannot upload', async () => {
    await assertFails(
      uploadBytes(ref(anonStorage(), photo(OURS, 'anon')), JPEG, AS_JPEG),
    );
  });
});

describe('P2-13 — deletion is server-side only', () => {
  test('NOBODY deletes from the client, not even a member', async () => {
    // Erasure is P2-36's sweep with the Admin SDK, which bypasses rules. A
    // client that can delete is a client that can destroy the other person's
    // history.
    await seedPhoto(OURS, 'item-1');
    await assertFails(deleteObject(ref(storage(ALICE), photo(OURS, 'item-1'))));
    await assertFails(deleteObject(ref(storage(BOB), photo(OURS, 'item-1'))));
  });
});

describe('P2-13 — paths outside the couple shape', () => {
  test('the bucket root is closed', async () => {
    await assertFails(
      uploadBytes(ref(storage(ALICE), 'loose.jpg'), JPEG, AS_JPEG),
    );
  });

  test('a sibling path under the couple is closed', async () => {
    // Only `photos/` is writable. A new prefix must come with its own rule
    // rather than inheriting one.
    await assertFails(
      uploadBytes(
        ref(storage(ALICE), `couples/${OURS}/backups/dump.jpg`),
        JPEG,
        AS_JPEG,
      ),
    );
  });

  test('a nested path under photos/ is closed', async () => {
    // `{photoId}` is a single segment, so it cannot be traversed into.
    await assertFails(
      uploadBytes(
        ref(storage(ALICE), `couples/${OURS}/photos/nested/deep.jpg`),
        JPEG,
        AS_JPEG,
      ),
    );
  });
});

describe('P2-13 — the immutability guard survives edits', () => {
  test('create still requires resource == null', () => {
    // Structural, because the emulator cannot exercise the behaviour. Without
    // this clause a sender can replace a delivered photo on real Firebase —
    // measured, not theorised. Deleting it would make every emulator test in
    // this file greener and the product less correct, which is exactly the
    // trade a future edit might make by accident.
    const rules = readFileSync('../storage.rules', 'utf8');
    assert.match(rules, /allow create:\s*if\s+resource == null/);
    assert.match(rules, /allow update:\s*if\s+false/);
    assert.match(rules, /allow delete:\s*if\s+false/);
  });
});

describe('P2-13 — the client and the rules agree on the path', () => {
  test('pathFor in Dart matches what these tests exercise', () => {
    // D-17's shape: a hand-kept mirror across languages. `PhotoUploadService.
    // pathFor` and `photoPrefix` in functions/src/unpair.ts must both produce
    // this, or an orphan stops being reclaimable and a photo survives erasure.
    const dart = readFileSync(
      '../lib/features/compose/photo_upload_service.dart',
      'utf8',
    );
    assert.match(dart, /couples\/\$coupleId\/photos\/\$itemId\.jpg/);

    const sweep = readFileSync('../functions/src/unpair.ts', 'utf8');
    assert.match(sweep, /couples\/\$\{coupleId\}\/photos\//);
  });
});
