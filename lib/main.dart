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
  _connectToEmulators();

  runApp(const ProviderScope(child: OncelingApp()));
}

/// Points the SDKs at the Local Emulator Suite — debug builds only.
///
/// Isolated in one function on purpose: a stray emulator call left in a release
/// build would silently send real users' data nowhere, and that is much easier
/// to spot here than scattered through `main()`.
///
/// Ports match the ones pinned in CLAUDE.md. The *host* is per-platform and
/// resolved by [EmulatorHost] — see there for why a real device has to be told
/// rather than guessing.
void _connectToEmulators() {
  if (!kDebugMode) return;

  final host = EmulatorHost.resolved;
  debugPrint('[emulator] host=$host explicit=${EmulatorHost.isExplicit}');
  FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  // **The region must match `functionsProvider`**, not the default instance.
  // `FirebaseFunctions.instance` and `instanceFor(region: …)` are different
  // objects, so wiring the emulator on the wrong one fails silently in the
  // worst possible direction: a debug build would keep working while calling
  // the REAL dev functions. Pinned to one constant so they cannot drift.
  FirebaseFunctions.instanceFor(
    region: functionsRegion,
  ).useFunctionsEmulator(host, 5001);
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
