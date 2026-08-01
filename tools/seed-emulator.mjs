#!/usr/bin/env node
// Emulator seed script (P2-33). Dev tooling — not app code, not deployed.
//
// Creates five unpaired test users, each with a users/{uid} document matching
// exactly what P2-30 writes and a pairing code claimed through the real path.
// Run it after any clearFirestore() or emulator restart.
//
//   cd tools && npm run seed          # create (idempotent)
//   cd tools && npm run seed:reset    # delete these five, then recreate
//
// Deliberately not in functions/ (not deployed) and not in lib/ (not app code).

import { createRequire } from 'node:module';
import { statSync, truncateSync } from 'node:fs';

// firebase-admin is a dependency of functions/, not of this directory — same
// resolution trick rules-tests/ uses, so there is no third node_modules tree.
const requireFromFunctions = createRequire(
  new URL('../functions/package.json', import.meta.url),
);
const { getApps, initializeApp } = requireFromFunctions('firebase-admin/app');
const { getAuth } = requireFromFunctions('firebase-admin/auth');
const {
  FieldValue,
  getFirestore,
} = requireFromFunctions('firebase-admin/firestore');

// ---------------------------------------------------------------------------
// Safety gate — this must never be able to reach a real project.
// ---------------------------------------------------------------------------

const PROJECT = process.env.GCLOUD_PROJECT ?? 'qalb-coupleapp-dev';

function refuse(message) {
  console.error(`\nseed-emulator: refusing to run.\n\n${message}\n`);
  process.exit(1);
}

for (const variable of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST']) {
  if (!process.env[variable]) {
    refuse(
      `${variable} is not set, so the Admin SDK would talk to the real ` +
        `project instead of the emulator.\n` +
        `Use the npm script, which sets both:  cd tools && npm run seed`,
    );
  }
}

// Belt and braces. The env vars above are the real guard; this catches the
// case where they are set but point at prod by mistake.
if (PROJECT.includes('prod')) {
  refuse(`GCLOUD_PROJECT is "${PROJECT}". This script is emulator-only.`);
}

// ---------------------------------------------------------------------------
// The cast. Passwords are fake and emulator-only; nothing here is a credential.
// ---------------------------------------------------------------------------

const PASSWORD = 'testpass123';

const USERS = [
  { email: 'maya@onceling.test', displayName: 'Maya' },
  { email: 'devon@onceling.test', displayName: 'Devon' },
  { email: 'sam@onceling.test', displayName: 'Sam' },
  { email: 'alex@onceling.test', displayName: 'Alex' },
  { email: 'jo@onceling.test', displayName: 'Jo' },
];

// Imported from the compiled Cloud Function rather than copied. Since P2-35
// the server owns the profile shape outright, so there is exactly one
// definition of what a new profile looks like and a seeded one cannot drift
// from a real one.
const { DEFAULT_FAVORITE_EMOJIS } = requireFromFunctions('./lib/profile.js');

if (getApps().length === 0) initializeApp({ projectId: PROJECT });
const auth = getAuth();
const db = getFirestore();

// The generation-and-claim path the ensurePairingCode callable wraps. Imported
// rather than reimplemented — see the note in the report.
const { claimPairingCode } = requireFromFunctions('./lib/pairing.js');

// ---------------------------------------------------------------------------

/** Emulator debug logs, at the repo root. Regenerated; safe to empty. */
const DEBUG_LOGS = [
  'firebase-debug.log',
  'firestore-debug.log',
  'ui-debug.log',
  'database-debug.log',
  'pubsub-debug.log',
];

/**
 * Empties the emulator debug logs and reports what that reclaimed.
 *
 * These grow without bound — both Node suites log every request, and the P2-18
 * concurrency tests alone fire thousands. They reached 640 MB combined during
 * development and filled the disk, which stopped a simulator build entirely.
 * The seed script is the right home for this: it is what you already run after
 * every wipe, and a documented manual step is a step people skip.
 *
 * SPARSE-FILE WARNING. The emulator holds these files open, so truncating does
 * not reset its write offset — the next write lands at the old offset and
 * leaves a hole. Afterwards `ls -l` reports the *apparent* size, which stays
 * huge and is misleading; `du` reports blocks actually on disk, which is the
 * truth. This cost a wrong diagnosis once: `ls` said 199 MB while `du` said
 * 16 K. Measure with `du`.
 */
function truncateDebugLogs() {
  let reclaimed = 0;
  for (const name of DEBUG_LOGS) {
    const path = new URL(`../${name}`, import.meta.url);
    try {
      // blocks * 512 is real disk usage; statSync().size would be the
      // apparent size and would overreport a sparse file.
      reclaimed += statSync(path).blocks * 512;
      truncateSync(path, 0);
    } catch (error) {
      // Missing is fine — the emulator writes them lazily.
      if (error.code !== 'ENOENT') throw error;
    }
  }
  return reclaimed;
}

/** The auth account, created if missing. Never overwrites an existing one. */
async function ensureAccount({ email, displayName }) {
  try {
    const existing = await auth.getUserByEmail(email);
    return { uid: existing.uid, created: false };
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
  }
  const created = await auth.createUser({
    email,
    password: PASSWORD,
    displayName,
  });
  return { uid: created.uid, created: true };
}

/**
 * users/{uid}, byte-for-byte what P2-30's ensureProfile writes.
 *
 * Idempotent in the same way: an existing document is left alone rather than
 * clobbered, so a second run cannot reset a profile mid-test.
 */
async function ensureProfile(uid, displayName) {
  const ref = db.doc(`users/${uid}`);
  const snap = await ref.get();
  if (snap.exists) return false;

  await ref.set({
    displayName,
    avatarUrl: null,
    coupleId: null,
    favoriteEmojis: DEFAULT_FAVORITE_EMOJIS,
    accentColor: null,
    createdAt: FieldValue.serverTimestamp(),
  });
  return true;
}

/** Removes exactly the five seeded users and their codes. Nothing else. */
async function reset() {
  let removed = 0;
  for (const { email } of USERS) {
    let user;
    try {
      user = await auth.getUserByEmail(email);
    } catch (error) {
      if (error.code === 'auth/user-not-found') continue;
      throw error;
    }

    // Read the profile first: it holds the code, which is the only way to
    // find the pairingCodes document without scanning the collection.
    const profileRef = db.doc(`users/${user.uid}`);
    const profile = await profileRef.get();
    const code = profile.exists ? profile.data().pairingCode : null;
    if (typeof code === 'string' && code !== '') {
      await db.doc(`pairingCodes/${code}`).delete();
    }
    if (profile.exists) await profileRef.delete();
    await auth.deleteUser(user.uid);
    removed++;
  }
  console.log(`--reset: removed ${removed} seeded user(s).\n`);
}

async function main() {
  // Behind the same emulator guard as everything else: this only ever touches
  // logs sitting next to an emulator we have already proven we are talking to.
  const reclaimed = truncateDebugLogs();

  const shouldReset = process.argv.includes('--reset');
  if (shouldReset) await reset();

  const rows = [];
  for (const spec of USERS) {
    const { uid, created } = await ensureAccount(spec);
    const wroteProfile = await ensureProfile(uid, spec.displayName);

    // A paired account has no code, and asking for one throws
    // caller-already-paired. That used to abort the whole loop partway, which
    // left later users with an auth account and no profile — a state the app
    // reads as "signed in, profile missing" and strands on the splash screen.
    // Any walkthrough that actually pairs someone leaves the emulator here, so
    // this is the normal case, not an edge case.
    const paired = (await db.doc(`users/${uid}`).get()).data()?.coupleId != null;
    const pairingCode = paired
      ? '—'
      : // Idempotent by construction: claimPairingCode returns the existing
        // code when the profile already carries one, so a rerun is a no-op.
        await claimPairingCode(db, uid);

    rows.push({
      email: spec.email,
      uid,
      displayName: spec.displayName,
      pairingCode,
      note: paired
        ? 'PAIRED — use --reset'
        : created
          ? 'created'
          : wroteProfile
            ? 'profile added'
            : 'existing',
    });
  }

  const columns = ['email', 'uid', 'displayName', 'pairingCode', 'note'];
  const width = Object.fromEntries(
    columns.map((c) => [c, Math.max(c.length, ...rows.map((r) => r[c].length))]),
  );
  const line = (cells) =>
    columns.map((c, i) => cells[i].padEnd(width[c])).join('  ');

  console.log(line(columns));
  console.log(columns.map((c) => '-'.repeat(width[c])).join('  '));
  for (const row of rows) console.log(line(columns.map((c) => row[c])));
  const anyPaired = rows.some((r) => r.note.startsWith('PAIRED'));
  console.log(
    anyPaired
      ? `\nSome accounts are paired and kept their couple. Password: ${PASSWORD}`
      : `\nAll five are unpaired. Password for every account: ${PASSWORD}`,
  );
  const mb = (reclaimed / 1024 / 1024).toFixed(1);
  console.log(`Emulator debug logs truncated — ${mb} MB reclaimed.`);
}

await main();
