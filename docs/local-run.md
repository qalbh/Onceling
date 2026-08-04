# Running Onceling locally

Split out of `CLAUDE.md`, which had grown to 372 lines with three sections making up
40% of it. This is the operational half: the emulator suite, the two watcher
processes, the simulators, the seeded accounts, and how to prove what is actually
running on a device.

**Read this before a device walkthrough, before starting or restarting the emulator,
and before trusting anything you saw on a simulator.** Not needed to write a provider
or a widget.

Nothing here is summarised — it is the same text, moved. Every rule was earned by
something going wrong, and the reasoning is what stops it being undone.

---

## Firebase — the emulator suite

- **Build against the Local Emulator Suite, not the cloud project.** Wipe between
  runs, test concurrent writes, run Security Rules unit tests. The dev cloud project
  is for device testing with real push, not for iteration.
- Emulator ports: Auth 9099, Functions 5001, Firestore 8080, UI 4000. Do not change
  them — tooling and docs assume the defaults.
- Emulator host is resolved by `lib/common/emulator_host.dart` (**P2-21**), not
  hardcoded: `localhost` for iOS simulators and desktop, `10.0.2.2` for the Android
  emulator, and whatever `--dart-define=EMULATOR_HOST=` names when it is set. Both
  loopback cases need no flag. See **Reaching the suite from a real device** below.
- Local dev runs two persistent processes: `firebase emulators:start` at the repo
  root, and `npm run build:watch` in `functions/`. The emulator loads
  `functions/lib/index.js`, not the TypeScript source — without the watcher running,
  function changes silently do not take effect and you will debug stale code.
- Emulator gaps to remember: no FCM, indexes are not enforced, data is ephemeral, and
  there is no network latency. A query that passes locally can still fail in the
  cloud with a missing-index error. Verify index-dependent queries against dev.
- The Storage emulator is not enabled. Until it is, Functions calls to Cloud Storage
  hit the real dev bucket. Enable it before **P2-13** (photo upload).

## Reaching the suite from a real device

Simulators and the AVD share the host's network stack and need nothing. A physical
phone does not. Two routes work; **`adb reverse` is the better one.**

**Preferred — `adb reverse`.** For a USB-connected device, which you need anyway to
install a debug build:

    adb -s <device-id> reverse tcp:8080 tcp:8080
    adb -s <device-id> reverse tcp:9099 tcp:9099
    adb -s <device-id> reverse tcp:5001 tcp:5001
    flutter run -d <device-id> --dart-define=EMULATOR_HOST=localhost

The phone reaches the suite on its own loopback: no LAN, no `0.0.0.0` binding, nothing
that breaks when the network changes. The tunnels do not survive an unplug — re-run
them after reconnecting. Verified on the SM-A325F.

> **The gotcha that makes this look broken: the plugins rewrite the host.**
> `useAuthEmulator`, `useFirestoreEmulator` and `useFunctionsEmulator` all default
> `automaticHostMapping: true`, which on Android silently turns `localhost` and
> `127.0.0.1` into `10.0.2.2`. That is a convenience for the AVD and a trap on a
> handset, where `10.0.2.2` is not the host but nothing at all — so the tunnel is
> never used and sign-in dies with `network-request-failed`, or with
> `Failed to connect to /10.0.2.2:9099` if you are lucky enough to get the address in
> the message. **`main.dart` passes `automaticHostMapping: false` on all three**, since
> `EmulatorHost` already resolved the host deliberately. If loopback ever stops
> working from a handset, check that first: the plugin announces itself in the device
> log with `Mapping Firestore Emulator host "localhost" to "10.0.2.2"`.

**Fallback — the LAN**, for wifi-`adb` or a device you cannot tunnel from. It needs
three things, and each fails differently — the symptom tells you which one is missing:

1. `--dart-define=EMULATOR_HOST=<Mac LAN IP>` (`ipconfig getifaddr en0`). *Symptom if
   missing: the app starts, logs a `WARNING:` naming this, falls back to `localhost`,
   and then behaves like (2) unless the tunnels happen to be up.* Confirm with
   `[backend] emulator at … explicit=true`.
2. **Both devices on the same network.** *Symptom: the app starts fine and then hangs
   — sign-in times out after about ten seconds with
   `[firebase_auth/network-request-failed]`.* Nothing names the host, because from the
   app's side an unreachable address and a wrong one look the same. Phones drop to
   cellular silently; a hotspot moves the host's IP, so re-check
   `ipconfig getifaddr en0` after any network change rather than trusting the IP that
   worked yesterday.
3. **The emulators bound to `0.0.0.0` in `firebase.json`** (see **D-25**). The default
   `127.0.0.1` accepts only host-local connections, so the packet arrives and is
   refused. *Symptom: fast and specific — connection refused, immediately, naming the
   IP and port.*

**A hang means (2); an instant connection-refused means (3); a `WARNING:` in the
startup log means (1).** Check the log before theorising — it distinguishes the first
case for free.

The LAN IP changes with the network. Do not commit it anywhere — `emulator_host.dart`
has a test asserting no private address is baked into the source.

**A physical device never resolves `10.0.2.2`.** That address is the *Android
emulator's* alias for the host loopback and means nothing on a handset.
`EmulatorHost` asks the platform whether it is real hardware (`device_info_plus`,
because the discriminating signal is the `ro.kernel.qemu` system property and no
file-existence check can see it) and falls back to `localhost`, which is correct under
`adb reverse`, with a `WARNING:` naming every way out. That fallback is only correct
because the plugin host rewriting is disabled — see the note above.

## Testing against the dev project

    flutter run -d <device-id> --dart-define=USE_EMULATOR=false

Skips `_connectToEmulators()` entirely, so the build talks to **real Firebase** on
`qalb-coupleapp-dev`. Needed for anything with no emulator behind it:

- **Push (P3-04).** There is no FCM emulator. `notifyOnItem` and the pairing triggers
  are deployed to dev, so a notification can only be observed this way.
- Index-dependent queries, which the Firestore emulator does not enforce (**P3-06**).

Real data, real quota, and none of the seeded accounts — `maya@onceling.test` and the
rest exist only in the emulator, which is the quickest way to confirm which backend
you are on. The startup line names it outright:

    [backend] REAL FIREBASE — dev project, no emulator (--dart-define=USE_EMULATOR=false)

The emulator is still the development environment (CLAUDE.md). This flag is for a
specific verification, not a way of working — and it is deliberately opt-*out* so a
forgotten flag can only ever send you to the emulator, never to real users' data.

Android also blocks cleartext HTTP by default, and the suite speaks plain HTTP.
`android/app/src/debug/res/xml/network_security_config.xml` permits it for **debug
builds only**; release inherits Android's default and `android_network_config_test.dart`
fails if that stops being true. *Symptom if it regresses: an error naming cleartext
rather than the host, surfacing out of a failed sign-in.*

## Cloud Functions — build and runtime

- Functions can be built and tested on the Spark plan via the emulator. Blaze is only
  required to deploy (**P2-16** for dev, **P4-06** for prod).
- Functions are scaffolded in `functions/` using TypeScript. Source lives in
  `functions/src/`, compiled output in `functions/lib/`. The pairing transaction
  (**P2-09**) goes here.
- `functions/package.json` pins Node 22 to match the local runtime. Do not bump it to
  24 without upgrading the local Node install first — emulator and deploy target must
  match.
- `functions/package.json` includes `@firebase/app` as a direct dependency. Our code
  does not use it. `firebase-admin@13.x` ships `@firebase/database-compat`, which
  requires `@firebase/app` as a peer but does not install it — the Functions emulator
  fails with MODULE_NOT_FOUND without it. Do not remove it as unused.

## Seed data

- `tools/seed-emulator.mjs` creates five test users with real profiles and claimed
  pairing codes. Emulator only — it refuses to run without the emulator env vars set.
  Run it after any `clearFirestore()` or emulator restart. Codes go through
  `ensurePairingCode`, never written by hand, so seeded state is indistinguishable
  from real state.

- Seeded test accounts, all with password `testpass123`: `maya@onceling.test`,
  `devon@onceling.test`, `sam@onceling.test`, `alex@onceling.test`,
  `jo@onceling.test`.

  **Pairing codes are not fixed and must not be recorded here.** `claimPairingCode`
  mints a fresh random code on every seed run, so any code written down is stale by
  the next one. The script prints the current five — read them from its output.

  Re-run `tools/seed-emulator.mjs` after any emulator restart or `clearFirestore()` —
  emulator data is ephemeral, and both Node suites clear it. A cached auth session
  pointing at a deleted uid strands the app on the splash screen; since **P2-34**
  that screen offers sign-out and a profile rebuild rather than trapping you.

## Local run

- **Install on every booted simulator, not one.** Onceling is a two-person app and
  most flows worth checking involve two accounts. After any change that alters app
  behaviour, install the current build on all booted iOS simulators so the user can
  tap through both sides without relaunching:

      flutter devices                    # list booted simulators
      flutter run -d <device-id>         # one per simulator, separate terminals

  Verification only needs one device — run the suites there. Installing on both is
  for the user's tap-through, not for the agent.

  Report each device ID, the model, and which account (if any) each is signed in as.
  If only one simulator is booted, say so rather than silently installing on one.

- **Never run two `flutter run` processes concurrently from the same project
  directory**, especially with differing `--dart-define` values. They race on the
  shared build output and the second reuses the first's kernel — both devices end up
  running the same build. This invalidated a device verification silently: two
  simulators both ran the same account's instrumented binary. Install sequentially,
  and if the builds differ in any way, verify the artifact on each device before
  drawing conclusions.

- Temporary instrumentation is not reverted until a clean build is installed on every
  booted simulator **and the artifact is checked**. `--dart-define` values compile
  into the binary and leave no trace in the repo, so grepping the source tree proves
  nothing about what is running on a device. Verify with:

      grep -c -a AUTOFLOW <app>/Frameworks/App.framework/flutter_assets/kernel_blob.bin

  Without `-a`, BSD grep treats the file as binary and reports 0 whether or not the
  string is present — the check silently passes on an instrumented build. Prove the
  command works by grepping for a string you have watched render on screen; if that
  returns 0, the command is broken, not the build.

  `flutter run` reuses an existing kernel when nothing has changed, so an artifact
  timestamp can legitimately predate the run. Timestamp is not evidence; content is.

  Source state and device state are different things. An instrumented build survived
  on both simulators for a full session after the source was clean, and prefilled the
  sign-in sheet and auto-submitted it — which read as an app bug.
