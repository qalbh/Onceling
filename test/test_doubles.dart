import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/common/providers.dart';
import 'package:couple_app/features/auth/auth_service.dart';
import 'package:couple_app/features/auth/models/user_profile.dart';
import 'package:couple_app/features/pairing/models/pairing_request.dart';
import 'package:couple_app/features/pairing/pairing_service.dart';

/// The redirect only ever asks "is there a user" — no member is touched, so a
/// null-returning [noSuchMethod] is safe here and fails loudly anywhere else.
class FakeUser implements User {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

UserProfile fakeProfile({String? coupleId, String? pairingCode}) => UserProfile(
  uid: 'uid-test',
  displayName: 'Maya',
  favoriteEmojis: const ['❤️'],
  coupleId: coupleId,
  pairingCode: pairingCode,
);

/// Records calls; never reaches the Functions emulator.
class FakePairingService implements PairingService {
  FakePairingService({
    this.code = 'MK4Q7B',
    this.requestError,
    this.coupleId,
    this.unpairError,
  });

  final String code;

  /// Thrown by [requestPairing] when set — how the error-copy tests drive
  /// each rejection without a live Functions emulator.
  final Object? requestError;

  /// Returned by [respondToPairing] on accept.
  final String? coupleId;

  /// Thrown by [unpair] when set — drives the sheet's failure state.
  final Object? unpairError;

  final List<String> calls = [];

  @override
  Future<String> ensurePairingCode() async {
    calls.add('ensurePairingCode');
    return code;
  }

  @override
  Future<String> requestPairing(String code) async {
    calls.add('requestPairing:$code');
    if (requestError case final error?) throw error;
    return 'req-1';
  }

  @override
  Future<void> cancelPairingRequest(String requestId) async {
    calls.add('cancelPairingRequest:$requestId');
  }

  @override
  Future<void> unpair() async {
    calls.add('unpair');
    if (unpairError case final error?) throw error;
  }

  @override
  Future<String?> respondToPairing(
    String requestId, {
    required bool accept,
  }) async {
    calls.add('respondToPairing:$requestId:$accept');
    return accept ? (coupleId ?? 'couple-1') : null;
  }
}

/// A pairing request with sensible defaults; override what the test cares about.
PairingRequest fakeRequest({
  String id = 'req-1',
  String fromUid = 'uid-them',
  String toUid = 'uid-test',
  PairingRequestStatus status = PairingRequestStatus.pending,
  String fromDisplayName = 'Devon',
  String? fromAvatarUrl,
  DateTime? createdAt,
}) => PairingRequest(
  id: id,
  fromUid: fromUid,
  toUid: toUid,
  status: status,
  fromDisplayName: fromDisplayName,
  fromAvatarUrl: fromAvatarUrl,
  createdAt: createdAt,
);

/// Overrides for a signed-out session: the gate lands on sign-in.
List<Override> signedOutOverrides() => [
  authStateProvider.overrideWith((ref) => Stream.value(null)),
  currentUserProvider.overrideWith((ref) => Stream.value(null)),
  pairingServiceProvider.overrideWithValue(FakePairingService()),
  ...pairingStreamOverrides(),
];

/// Empty pairing streams. Without these every widget test touching the pairing
/// screen would try to reach a real Firestore.
List<Override> pairingStreamOverrides({
  List<PairingRequest> incoming = const [],
  PairingRequest? outgoing,
}) => [
  incomingRequestsProvider.overrideWith((ref) => Stream.value(incoming)),
  outgoingRequestProvider.overrideWith((ref) => Stream.value(outgoing)),
];

/// Overrides for a signed-in session with the given pairing state.
///
/// [pairingCode] defaults to a claimed code so the pairing screen does not
/// fire `ensurePairingCode` during unrelated tests.
List<Override> signedInOverrides({
  String? coupleId,
  String? pairingCode = 'MK4Q7B',
  PairingService? pairing,
  List<PairingRequest> incoming = const [],
  PairingRequest? outgoing,
}) => [
  authStateProvider.overrideWith((ref) => Stream.value(FakeUser())),
  currentUserProvider.overrideWith(
    (ref) =>
        Stream.value(fakeProfile(coupleId: coupleId, pairingCode: pairingCode)),
  ),
  pairingServiceProvider.overrideWithValue(pairing ?? FakePairingService()),
  ...pairingStreamOverrides(incoming: incoming, outgoing: outgoing),
];

/// A session whose auth state can be flipped mid-test — sign-out goes through
/// [service] and lands on the streams the router is watching.
///
/// Each subscriber first receives the current value, then live updates. A bare
/// broadcast stream would drop the initial signed-in event: it fires before
/// the providers subscribe, and the app would never leave splash.
class FakeSession {
  /// [profileMissing] models **P2-34**: signed in, but `users/{uid}` never
  /// landed. The profile stream resolves to null rather than staying loading,
  /// which is exactly what strands the splash screen.
  FakeSession({this.profileMissing = false}) {
    _profilePresent = !profileMissing;
  }

  final bool profileMissing;

  /// Set by [overrides]; existing callers pass it there rather than to the
  /// constructor.
  String? _coupleId;

  User? _user = FakeUser();
  late bool _profilePresent;
  int _recoverCalls = 0;

  final _controller = StreamController<User?>.broadcast();
  final _profiles = StreamController<UserProfile?>.broadcast();
  late final service = _FakeAuthService(this);

  /// How many times the splash screen asked to rewrite the profile.
  int get recoverCalls => _recoverCalls;

  void _set(User? user) {
    _user = user;
    _controller.add(user);
    _profiles.add(_profile());
  }

  UserProfile? _profile() => (_user == null || !_profilePresent)
      ? null
      : fakeProfile(coupleId: _coupleId, pairingCode: 'MK4Q7B');

  /// The P2-30 write finally landing — the document appears.
  void _recover() {
    _profilePresent = true;
    _profiles.add(_profile());
  }

  /// Makes the document appear without going through the service, for the
  /// "retry once it exists" path.
  void profileAppears() => _recover();

  List<Override> overrides({String? coupleId}) {
    _coupleId = coupleId;
    return [
      authStateProvider.overrideWith((ref) async* {
        yield _user;
        yield* _controller.stream;
      }),
      currentUserProvider.overrideWith((ref) async* {
        yield _profile();
        yield* _profiles.stream;
      }),
      authServiceProvider.overrideWithValue(service),
      pairingServiceProvider.overrideWithValue(FakePairingService()),
      ...pairingStreamOverrides(),
    ];
  }

  void dispose() {
    _controller.close();
    _profiles.close();
  }
}

class _FakeAuthService implements AuthService {
  _FakeAuthService(this._session);

  final FakeSession _session;

  @override
  Future<void> recoverProfile() async {
    _session._recoverCalls++;
    _session._recover();
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    _session._set(FakeUser());
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    _session._set(FakeUser());
  }

  @override
  Future<void> signOut() async {
    _session._set(null);
  }
}
