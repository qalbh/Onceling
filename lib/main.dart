import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'common/app_router.dart';
import 'common/emulator_host.dart';
import 'common/providers.dart';
import 'firebase_options_dev.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Both families are bundled in assets/fonts/; never reach out to Google.
  GoogleFonts.config.allowRuntimeFetching = false;

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _connectToEmulators();

  runApp(const ProviderScope(child: OncelingApp()));
}

/// Points the SDKs at the Local Emulator Suite — debug builds only.
///
/// Isolated in one function on purpose: a stray emulator call left in a release
/// build would silently send real users' data nowhere, and that is much easier
/// to spot here than scattered through `main()`.
///
/// Ports match the ones pinned in CLAUDE.md. The *host* is per-target and
/// resolved by [EmulatorHost] — see there for why a physical device cannot be
/// guessed at.
///
/// **Always logs which backend it settled on.** Naming the host alone was not
/// enough: `host=10.0.2.2` says nothing about whether that is an emulator or
/// the dev project, and the whole class of bug here is talking to the wrong one
/// while everything looks fine.
Future<void> _connectToEmulators() async {
  if (!kDebugMode) return;

  if (!EmulatorHost.useEmulator) {
    // Deliberate: the only way to exercise anything with no emulator behind it.
    // Loud because a build that reaches real Firebase should never be a
    // surprise — see docs/local-run.md.
    debugPrint(
      '[backend] REAL FIREBASE — dev project, no emulator '
      '(--dart-define=USE_EMULATOR=false)',
    );
    return;
  }

  final host = await EmulatorHost.resolve();
  debugPrint(
    '[backend] emulator at $host '
    '(auth 9099, firestore 8080, functions 5001) '
    'explicit=${EmulatorHost.isExplicit}',
  );

  final warning = EmulatorHost.warningFor(
    isPhysicalDevice: await EmulatorHost.isPhysicalDevice(),
    host: host,
  );
  if (warning != null) debugPrint('[backend] WARNING: $warning');

  // **`automaticHostMapping: false` on all three, and it is load-bearing.**
  //
  // Left at its default, every one of these plugins silently rewrites
  // `localhost` and `127.0.0.1` to `10.0.2.2` on Android — see
  // `cloud_firestore/lib/src/firestore.dart`, "Android considers localhost as
  // 10.0.2.2". That is a kindness for the AVD and a trap everywhere else: it
  // overrides the host we just resolved deliberately, so a physical device
  // asking for loopback gets the emulator alias instead and fails against an
  // address that does not exist. [EmulatorHost] already knows which target it
  // is on; the plugin guessing on top of that can only be wrong.
  FirebaseAuth.instance.useAuthEmulator(
    host,
    9099,
    automaticHostMapping: false,
  );
  FirebaseFirestore.instance.useFirestoreEmulator(
    host,
    8080,
    automaticHostMapping: false,
  );
  // **The region must match `functionsProvider`**, not the default instance.
  // `FirebaseFunctions.instance` and `instanceFor(region: …)` are different
  // objects, so wiring the emulator on the wrong one fails silently in the
  // worst possible direction: a debug build would keep working while calling
  // the REAL dev functions. Pinned to one constant so they cannot drift.
  FirebaseFunctions.instanceFor(
    region: functionsRegion,
  ).useFunctionsEmulator(host, 5001, automaticHostMapping: false);
}

class OncelingApp extends ConsumerWidget {
  const OncelingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Onceling',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
