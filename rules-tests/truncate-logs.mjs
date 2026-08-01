#!/usr/bin/env node
// Empties the emulator debug logs before a suite runs.
//
// Wired as `pretest` / `pretest:functions` so it is impossible to forget. The
// seed script does this too and keeps doing it — belt and braces on a problem
// that has stopped work three times in one session. The seed version only
// fires when seeding, and these suites run many times between seeds: the P2-18
// concurrency loops and the P2-36 unpair tests generate the bulk of the volume,
// several hundred MB in an afternoon, and a full disk stops simulator builds
// and produces test failures that look like real regressions.
//
// SPARSE-FILE WARNING. The emulator holds these files open, so truncating does
// not reset its write offset — the next write lands at the old offset and
// leaves a hole. Afterwards `ls -l` reports the apparent size, which stays huge
// and is misleading; `du` reports blocks actually on disk, which is the truth.
// This cost a wrong diagnosis once: `ls` said 199 MB while `du` said 16 K.

import { statSync, truncateSync } from 'node:fs';

// The same guard the seed script uses: never touch anything unless we have
// been pointed at an emulator.
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    'truncate-logs: FIRESTORE_EMULATOR_HOST is not set — refusing to run.',
  );
  process.exit(1);
}

const LOGS = [
  'firebase-debug.log',
  'firestore-debug.log',
  'ui-debug.log',
  'database-debug.log',
  'pubsub-debug.log',
];

let reclaimed = 0;
for (const name of LOGS) {
  const path = new URL(`../${name}`, import.meta.url);
  try {
    // blocks * 512 is real disk usage; statSync().size would be the apparent
    // size and would wildly overreport a sparse file.
    reclaimed += statSync(path).blocks * 512;
    truncateSync(path, 0);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

const mb = (reclaimed / 1024 / 1024).toFixed(1);
if (reclaimed > 0) console.log(`emulator debug logs truncated — ${mb} MB reclaimed`);
