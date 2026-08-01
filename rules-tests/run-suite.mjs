// Runs a test suite, retains its full output, and reports failures on stderr.
//
// **This exists because of D-14.** The functions suite has intermittently
// reported a single failure that passes on retry. Three times now the fix has
// been "capture which test failed before re-running" — and three times that
// depended on someone remembering not to pipe the run through a summary-only
// filter. The third time, the `not ok` line was discarded by a
// `grep -E '^# (tests|pass|fail)'` and the identity was lost for good.
//
// Two things make the capture structural rather than remembered, and it is
// worth being exact about which one carries the weight:
//
//   1. **The full output is written to a log file that survives the run.**
//      This is the actual guarantee. The identity is recoverable afterwards no
//      matter what the caller did to the streams, including the case below.
//   2. **The failure summary is printed to stderr.** This helps only when the
//      caller filters stdout alone (`npm test | grep …`). It does NOT defeat
//      the mistake that lost D-14's identity, which was
//      `npm test 2>&1 | grep …` — that merges stderr into the pipe before the
//      filter runs, so this block is discarded with everything else. Verified
//      both ways by sabotaging a test rather than assumed.
//
// So: if a run reports a failure you cannot see, read logs/<name>.log.
//
// usage: node run-suite.mjs <log-name> <node args...>

import { spawn } from "node:child_process";
import { createWriteStream, mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const [logName, ...nodeArgs] = process.argv.slice(2);

if (logName == null || nodeArgs.length === 0) {
  console.error("usage: node run-suite.mjs <log-name> <node args...>");
  process.exit(2);
}

const logDir = join(import.meta.dirname, "logs");
mkdirSync(logDir, { recursive: true });
// Overwritten per run, not appended: one run's output is what a failure needs,
// and an append-only log is how the emulator filled the disk three times.
const logPath = join(logDir, `${logName}.log`);
const log = createWriteStream(logPath);

const child = spawn(process.execPath, nodeArgs, {
  cwd: import.meta.dirname,
  stdio: ["inherit", "pipe", "pipe"],
});

child.stdout.on("data", (chunk) => {
  process.stdout.write(chunk);
  log.write(chunk);
});
child.stderr.on("data", (chunk) => {
  process.stderr.write(chunk);
  log.write(chunk);
});

child.on("error", (err) => {
  console.error(`run-suite: could not start node — ${err.message}`);
  process.exit(1);
});

child.on("close", (code, signal) => {
  log.end(() => {
    const failed = code !== 0 || signal != null;
    if (!failed) {
      process.exit(0);
    }

    // TAP marks a failing test with `not ok <n> - <name>`, nested by suite.
    // Reporting every one of them, not just the count.
    let failures = [];
    try {
      failures = readFileSync(logPath, "utf8")
        .split("\n")
        .filter((line) => /^\s*not ok \d+ - /.test(line))
        .map((line) => line.trim());
    } catch (err) {
      console.error(`run-suite: could not re-read ${logPath} — ${err.message}`);
    }

    // stderr, deliberately — see the header. Do not "clean this up" onto
    // stdout; being un-pipeable is the point.
    console.error("");
    console.error(`─── ${logName}: FAILED ───`);
    if (failures.length > 0) {
      console.error(`${failures.length} failing test(s):`);
      for (const failure of failures) console.error(`  ${failure}`);
    } else {
      console.error("No `not ok` lines — the suite died before reporting.");
    }
    console.error(`Full output retained at: ${logPath}`);
    console.error(
      "D-14: if this is the intermittent one-off, record the name above " +
        "BEFORE re-running.",
    );
    console.error("");

    process.exit(code === 0 ? 1 : code);
  });
});
