import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/screens/sign_in_screen.dart';
import '../features/feed/models/feed_item.dart';
import '../features/feed/screens/feed_screen.dart';
import '../features/milestone/milestone_moment.dart';
import '../features/milestone/screens/milestone_screen.dart';
import '../features/pairing/pairing_celebration.dart';
import '../features/pairing/screens/paired_screen.dart';
import '../features/onboarding/screens/how_secrets_work_screen.dart';
import '../features/onboarding/screens/onboarding_screen.dart';
import '../features/pairing/screens/pairing_screen.dart';
import '../features/secret/screens/secret_reveal_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../theme/theme_colors.dart';
import 'providers.dart';

/// Route paths. One place, so the redirect and the route table cannot drift.
abstract final class AppRoutes {
  static const splash = '/splash';
  static const signIn = '/';
  static const pairing = '/pairing';
  static const paired = '/paired';
  static const milestone = '/milestone';
  static const feed = '/feed';
  static const settings = '/settings';
  static const secretReveal = '/secret-reveal';
  static const onboarding = '/onboarding';
  static const howSecretsWork = '/how-secrets-work';
}

/// The auth gate, as a pure function — the only navigation decision in the app,
/// so it is unit-testable without pumping a widget.
///
/// Returns the path to redirect to, or null to stay put.
///
/// The order of the checks is the contract:
/// 1. While anything is loading, hold on splash. Falling through to sign-in
///    here would flash the sign-in screen on every cold start.
/// 2. A signed-in user with no profile document yet is *loading*, not
///    unpaired — the write from sign-up may still be in flight. The splash
///    screen owns the timeout for the case where it never lands.
/// 3. Only then route on coupleId, with the pairing moment (**P2-26**) sitting
///    between a fresh coupleId and the feed.
String? resolveRedirect({
  required bool isLoadingAuth,
  required bool isSignedIn,
  required bool isLoadingProfile,
  required bool profileExists,
  required String? coupleId,
  required String currentLocation,
  bool justPaired = false,
  bool hasSeenOnboarding = true,
  bool milestonePending = false,
}) {
  // The branch ORDER here is load-bearing, not stylistic.
  //
  // Sign-out is not atomic across the two streams: auth emits null first, and
  // the profile stream keeps serving the *old* signed-in value for a few
  // milliseconds after. Device traces caught the window — `signedIn=false`
  // alongside `profExists=true, coupleId=<the old couple>`. Because the
  // signed-out branch is tested before anything that reads `coupleId`, that
  // window resolves to sign-in and the user leaves cleanly.
  //
  // Reorder these and a signing-out user routes to /feed or /paired on the
  // strength of a profile they no longer have a session for. `routes on a
  // stale profile during sign-out` in app_router_test.dart pins this.
  final wanted = switch ((isLoadingAuth, isSignedIn)) {
    (true, _) => AppRoutes.splash,
    (false, false) => AppRoutes.signIn,
    (false, true) when isLoadingProfile || !profileExists => AppRoutes.splash,
    // **P3-07 / PI-02**, and its position is the decision. Onboarding sits
    // after the profile exists and BEFORE the coupleId branch, because it
    // explains what the space is before anyone invites another person into it
    // — and because PI-02 gates external testing, so a tester who paired on an
    // older build must still meet the disclosure rather than skip it by having
    // been early.
    //
    // Ahead of the pairing branch but behind the profile branch: a signed-in
    // user with no document yet is still loading, and showing them onboarding
    // would race the sign-up write.
    (false, true) when !hasSeenOnboarding => AppRoutes.onboarding,
    (false, true) when coupleId == null => AppRoutes.pairing,
    // justPaired is only ever true when this session watched coupleId appear,
    // so a cold start on a paired account falls straight through to the feed.
    //
    // **P3-03** sits after it: a pairing moment and a milestone moment cannot
    // both be owed today (a couple paired today is on day zero), but if P2-39's
    // backdating ever makes it possible, the pairing moment is the one that
    // must not lose — it is brief §11's activation instant, and the milestone
    // will still be pending when it clears.
    (false, true) when justPaired => AppRoutes.paired,
    (false, true) when milestonePending => AppRoutes.milestone,
    (false, true) => AppRoutes.feed,
  };

  // Sub-locations of the wanted area stay put: being at /settings while the
  // gate wants /feed is fine — settings is only reachable from feed. The
  // secret reveal rides on top of the feed the same way.
  final allowed = switch (wanted) {
    AppRoutes.feed => const {
      AppRoutes.feed,
      AppRoutes.settings,
      AppRoutes.secretReveal,
      AppRoutes.howSecretsWork,
    },
    // Unpaired users keep settings too — sign-out lives there, and so does
    // the disclosure they can re-read at any time.
    AppRoutes.pairing => const {
      AppRoutes.pairing,
      AppRoutes.settings,
      AppRoutes.howSecretsWork,
    },
    // The moment is a destination in its own right, not a layer over the feed.
    AppRoutes.paired => const {AppRoutes.paired},
    AppRoutes.milestone => const {AppRoutes.milestone},
    final w => {w},
  };

  return allowed.contains(currentLocation) ? null : wanted;
}

/// Bridges Riverpod state changes into go_router's refreshListenable.
class _GateNotifier extends ChangeNotifier {
  _GateNotifier(Ref ref) {
    // **P3-04.** Somewhere has to hold this alive for the app's lifetime, and
    // the gate is the one provider guaranteed to exist from first frame to
    // last. Reading it here starts the auth listener that keeps `pushToken` in
    // step with the session — including clearing it on sign-out.
    ref.read(pushRegistrationProvider);
    // Re-evaluate the redirect whenever auth or the profile document moves.
    ref.listen(authStateProvider, (_, _) => notifyListeners());
    ref.listen(currentUserProvider, (_, _) => notifyListeners());
    // Acknowledging the pairing moment is what releases the gate to the feed.
    ref.listen(pairingCelebrationProvider, (_, _) => notifyListeners());
    // Same mechanism for the milestone moment (**P3-03**). Because this
    // watches live state, a couple whose midnight passes while the app is
    // foregrounded gets the moment then, not just on the next cold start.
    ref.listen(milestoneMomentProvider, (_, _) => notifyListeners());
  }
}

final _gateNotifierProvider = Provider<_GateNotifier>(_GateNotifier.new);

/// The app's router. Watches nothing itself — the notifier above pokes it.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: ref.watch(_gateNotifierProvider),
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final profile = ref.read(currentUserProvider);
      final user = auth.valueOrNull;

      return resolveRedirect(
        justPaired: ref.read(pairingCelebrationProvider) != null,
        milestonePending: ref.read(milestoneMomentProvider) != null,
        hasSeenOnboarding: profile.valueOrNull?.hasSeenOnboarding ?? true,
        isLoadingAuth: auth.isLoading,
        isSignedIn: user != null,
        // currentUserProvider re-enters loading when auth flips; treat only
        // the signed-in case as profile-loading.
        isLoadingProfile: user != null && profile.isLoading,
        profileExists: profile.valueOrNull != null,
        coupleId: profile.valueOrNull?.coupleId,
        currentLocation: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: AppRoutes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(
        path: AppRoutes.pairing,
        builder: (_, _) => const PairingScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, _) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.howSecretsWork,
        builder: (_, _) => const HowSecretsWorkScreen(),
      ),
      GoRoute(path: AppRoutes.paired, builder: (_, _) => const PairedScreen()),
      GoRoute(
        path: AppRoutes.milestone,
        builder: (_, _) => const MilestoneScreen(),
      ),
      GoRoute(path: AppRoutes.feed, builder: (_, _) => const FeedScreen()),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.secretReveal,
        pageBuilder: (_, state) {
          final args = state.extra! as SecretRevealArgs;
          // Preserves the pre-router presentation: the reveal fades in over
          // the thread rather than sliding like a page.
          return CustomTransitionPage<SecretRevealResult>(
            opaque: false,
            barrierDismissible: false,
            transitionDuration: const Duration(milliseconds: 320),
            child: SecretRevealScreen(
              secret: args.secret,
              senderName: args.senderName,
            ),
            transitionsBuilder: (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
          );
        },
      ),
    ],
  );
});

/// Arguments for the secret reveal route, passed via `state.extra`.
class SecretRevealArgs {
  const SecretRevealArgs({required this.secret, required this.senderName});

  final SecretMessage secret;
  final String senderName;
}

/// Held while auth or the profile document is still resolving.
///
/// Owns the give-up timer: a signed-in user whose document never appears gets
/// an error and a retry instead of an endless spinner.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key, this.timeout = const Duration(seconds: 6)});

  final Duration timeout;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _timedOut = false;
  bool _working = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _armTimer();
  }

  @override
  void dispose() {
    // Cancellable on purpose: the splash usually lives for a fraction of a
    // second, and an orphaned timer would outlive the route.
    _timer?.cancel();
    super.dispose();
  }

  void _armTimer() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, () {
      if (mounted) setState(() => _timedOut = true);
    });
  }

  void _retry() {
    setState(() => _timedOut = false);
    // Refetching the document is enough: the router re-evaluates as soon as
    // the stream emits. Invalidate to force a fresh subscription.
    ref.invalidate(currentUserProvider);
    _armTimer();
  }

  /// **P2-34.** Re-runs the P2-30 write. This is the recovery a retry cannot
  /// provide: when the document was never written, refetching it forever finds
  /// nothing, because there is nothing to find.
  Future<void> _recreateProfile() async {
    setState(() => _working = true);
    try {
      await ref.read(authServiceProvider).recoverProfile();
      if (!mounted) return;
      // The document stream carries the new profile and the gate moves on. If
      // it somehow does not, fall back to the error state rather than hanging.
      setState(() {
        _working = false;
        _timedOut = false;
      });
      _armTimer();
    } catch (error) {
      developer.log('recoverProfile failed: $error', name: 'SplashScreen');
      if (mounted) setState(() => _working = false);
    }
  }

  /// The last resort, and the one that always works: drop the session. The
  /// gate resolves signed-out to sign-in, from where a fresh sign-in rewrites
  /// the profile anyway.
  Future<void> _signOut() async {
    setState(() => _working = true);
    try {
      await ref.read(authServiceProvider).signOut();
    } catch (error) {
      developer.log('signOut from splash failed: $error', name: 'SplashScreen');
      if (mounted) setState(() => _working = false);
    }
  }

  /// Signed in, the profile stream has *resolved*, and there is no document.
  ///
  /// Distinguishing this from a slow network matters for the copy: "check your
  /// connection" is wrong and misleading when the connection is fine and the
  /// document simply is not there.
  bool get _profileMissing {
    final auth = ref.watch(authStateProvider);
    final profile = ref.watch(currentUserProvider);
    return auth.valueOrNull != null &&
        !profile.isLoading &&
        profile.valueOrNull == null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: _timedOut
              ? _TimeoutMessage(
                  profileMissing: _profileMissing,
                  busy: _working,
                  onRetry: _retry,
                  onRecreate: _recreateProfile,
                  onSignOut: _signOut,
                )
              : const CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

/// The splash error state, with recovery (**P2-34**).
///
/// Two distinct failures share this screen and must not share copy:
///
/// - **slow** — auth or the document is still in flight. A retry is the right
///   advice, and the connection genuinely might be the problem.
/// - **profileMissing** — signed in, the stream resolved, no document. Retry
///   cannot help: it refetches something that does not exist. This is the
///   sign-up that died between creating the account and writing the profile,
///   and before P2-34 it stranded the user until they deleted the app.
class _TimeoutMessage extends StatelessWidget {
  const _TimeoutMessage({
    required this.profileMissing,
    required this.busy,
    required this.onRetry,
    required this.onRecreate,
    required this.onSignOut,
  });

  final bool profileMissing;
  final bool busy;
  final VoidCallback onRetry;
  final VoidCallback onRecreate;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              profileMissing
                  ? "We couldn't finish setting up your account."
                  : 'Taking longer than it should.',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Text(
              profileMissing
                  ? 'Your sign-in worked, but your profile never finished '
                        'saving. Setting it up again usually fixes this.'
                  : 'Check your connection, then try again.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            // Primary is whichever action can actually fix the state in front
            // of the user: rewriting the document, or refetching it.
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                key: const Key('splash-primary'),
                onPressed: busy
                    ? null
                    : (profileMissing ? onRecreate : onRetry),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  disabledBackgroundColor: context.palette.disabled,
                  disabledForegroundColor: theme.colorScheme.onPrimary,
                  elevation: 0,
                  shape: const StadiumBorder(),
                ),
                child: Text(profileMissing ? 'Set up my profile' : 'Try again'),
              ),
            ),
            const SizedBox(height: 8),
            // Always present, and it always works — clearing the session is
            // the one recovery that does not depend on the server doing
            // anything. Before P2-34 this screen had no way out at all.
            SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton(
                key: const Key('splash-sign-out'),
                onPressed: busy ? null : onSignOut,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
                child: const Text('Sign out'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
