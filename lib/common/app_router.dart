import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/screens/sign_in_screen.dart';
import '../features/feed/models/feed_item.dart';
import '../features/feed/screens/feed_screen.dart';
import '../features/pairing/screens/pairing_screen.dart';
import '../features/secret/screens/secret_reveal_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import 'providers.dart';

/// Route paths. One place, so the redirect and the route table cannot drift.
abstract final class AppRoutes {
  static const splash = '/splash';
  static const signIn = '/';
  static const pairing = '/pairing';
  static const feed = '/feed';
  static const settings = '/settings';
  static const secretReveal = '/secret-reveal';
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
/// 3. Only then route on coupleId.
String? resolveRedirect({
  required bool isLoadingAuth,
  required bool isSignedIn,
  required bool isLoadingProfile,
  required bool profileExists,
  required String? coupleId,
  required String currentLocation,
}) {
  final wanted = switch ((isLoadingAuth, isSignedIn)) {
    (true, _) => AppRoutes.splash,
    (false, false) => AppRoutes.signIn,
    (false, true) when isLoadingProfile || !profileExists => AppRoutes.splash,
    (false, true) => coupleId == null ? AppRoutes.pairing : AppRoutes.feed,
  };

  // Sub-locations of the wanted area stay put: being at /settings while the
  // gate wants /feed is fine — settings is only reachable from feed. The
  // secret reveal rides on top of the feed the same way.
  final allowed = switch (wanted) {
    AppRoutes.feed => const {
      AppRoutes.feed,
      AppRoutes.settings,
      AppRoutes.secretReveal,
    },
    // Unpaired users keep settings too — sign-out lives there.
    AppRoutes.pairing => const {AppRoutes.pairing, AppRoutes.settings},
    final w => {w},
  };

  return allowed.contains(currentLocation) ? null : wanted;
}

/// Bridges Riverpod state changes into go_router's refreshListenable.
class _GateNotifier extends ChangeNotifier {
  _GateNotifier(Ref ref) {
    // Re-evaluate the redirect whenever auth or the profile document moves.
    ref.listen(authStateProvider, (_, _) => notifyListeners());
    ref.listen(currentUserProvider, (_, _) => notifyListeners());
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
              body: args.body,
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
  const SecretRevealArgs({
    required this.secret,
    required this.senderName,
    required this.body,
  });

  final SecretMessage secret;
  final String senderName;
  final String body;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: _timedOut
              ? _TimeoutMessage(onRetry: _retry)
              : const CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class _TimeoutMessage extends StatelessWidget {
  const _TimeoutMessage({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Taking longer than it should.',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          Text(
            'Check your connection, then try again.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge!.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              elevation: 0,
              shape: const StadiumBorder(),
            ),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
