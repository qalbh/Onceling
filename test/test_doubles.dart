import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/common/providers.dart';
import 'package:couple_app/features/auth/auth_service.dart';
import 'package:couple_app/features/auth/models/user_profile.dart';
import 'package:couple_app/features/auth/profile_service.dart';
import 'package:couple_app/features/mood/mood_service.dart';
import 'package:couple_app/features/notifications/push_service.dart';
import 'package:couple_app/features/pairing/couple_names.dart';
import 'package:couple_app/features/settings/anniversary_service.dart';
import 'package:couple_app/features/pairing/device_timezone.dart';
import 'package:couple_app/features/pairing/models/couple.dart';
import 'package:couple_app/features/pairing/models/pairing_request.dart';
import 'package:couple_app/features/pairing/pairing_service.dart';
import 'package:couple_app/features/secret/secret_service.dart';

/// A signed-in user, for the redirect and for **P3-04**'s token registration.
///
/// It used to null everything through [noSuchMethod], on the grounds that the
/// redirect only asks "is there a user". Push registration then started reading
/// `uid` and the fake failed loudly — which is what that design was for, but
/// the answer is to supply the field rather than to guard around a null uid in
/// production code.
class FakeUser implements User {
  FakeUser({this.uid = 'uid-test'});

  @override
  final String uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

UserProfile fakeProfile({
  String uid = 'uid-test',
  String displayName = 'Maya',
  String? coupleId,
  String? pairingCode,
  // Defaults to seen so every pre-P3-07 test keeps testing what it was
  // written to test rather than landing on onboarding. A bool rather than a
  // DateTime because DateTime has no const constructor and the exact stamp is
  // never what a test cares about.
  bool onboardingSeen = true,
  // The eight ensureUserProfile writes, so tray-driven tests exercise the
  // real shape rather than a one-emoji stub.
  List<String> favoriteEmojis = const [
    '❤️',
    '😂',
    '🥹',
    '🔥',
    '🫶',
    '🌙',
    '🧋',
    '🐈',
  ],
}) => UserProfile(
  uid: uid,
  displayName: displayName,
  favoriteEmojis: favoriteEmojis,
  coupleId: coupleId,
  pairingCode: pairingCode,
  onboardingSeenAt: onboardingSeen ? DateTime(2026, 1, 1) : null,
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
    String? timezone,
  }) async {
    // The timezone is recorded so P2-40 can assert the accepting device sent
    // one, and that a decline does not.
    calls.add('respondToPairing:$requestId:$accept:${timezone ?? '-'}');
    return accept ? (coupleId ?? 'couple-1') : null;
  }
}

/// Records calls; never reaches the Functions emulator.
///
/// **PI-02**: `markOnboardingSeen` is what the gate keys on, so a test needs to
/// assert it was called without a live Functions emulator.
class FakeProfileService implements ProfileService {
  FakeProfileService({this.markError});

  /// Thrown by [markOnboardingSeen] when set — drives the path where the
  /// record fails and the reader must not be trapped on the disclosure.
  final Object? markError;

  final List<String> calls = [];

  @override
  Future<ProfileState> ensureProfile({String? displayName}) async {
    calls.add('ensureProfile');
    return const ProfileState(created: false);
  }

  @override
  Future<void> markOnboardingSeen() async {
    calls.add('markOnboardingSeen');
    if (markError case final error?) throw error;
  }
}

/// Records calls; never reaches the Functions emulator.
///
/// A fake rather than a fake-Firestore write, because `setMood` is a callable:
/// `couples` denies every client write, so there is no document path to fake.
class FakeMoodService implements MoodService {
  FakeMoodService({this.error});

  /// Thrown by [setMood] when set — drives the send-failure copy.
  final Object? error;

  final List<({String emoji, String note})> calls = [];

  @override
  Future<void> setMood({required String emoji, required String note}) async {
    calls.add((emoji: emoji, note: note));
    if (error case final failure?) throw failure;
  }
}

/// Records the two reveal transitions; never reaches the Functions emulator.
///
/// Defaults model the happy path: a window that opened just now and a body to
/// read. Each failure the screen has to handle gets its own switch, because
/// they are genuinely different outcomes and collapsing them would hide which
/// one the screen mishandles.
class FakeSecretService implements SecretService {
  FakeSecretService({
    this.body = 'I already booked the thing for your birthday. Act surprised.',
    this.window = const Duration(seconds: 30),
    this.startedAt,
    this.beginError,
    this.bodyError,
    this.completeError,
    this.alreadyOpening = false,
  });

  final String body;
  final Duration window;

  /// Lets a test open a window that is already partly, or entirely, spent.
  final DateTime? startedAt;

  final Object? beginError;
  final Object? bodyError;
  final Object? completeError;
  final bool alreadyOpening;

  final List<String> calls = [];

  @override
  Future<RevealWindow> beginReveal(String itemId) async {
    calls.add('beginReveal:$itemId');
    if (beginError case final error?) throw error;
    return RevealWindow(
      openingStartedAt: startedAt ?? DateTime.now(),
      window: window,
      alreadyOpening: alreadyOpening,
    );
  }

  @override
  Future<String> readBody(String itemId) async {
    calls.add('readBody:$itemId');
    if (bodyError case final error?) throw error;
    return body;
  }

  @override
  Future<void> completeReveal(String itemId) async {
    calls.add('completeReveal:$itemId');
    if (completeError case final error?) throw error;
  }
}

/// Records token registration; never touches FCM.
///
/// **P3-04.** The behaviour worth pinning is `unregister` on sign-out: a stale
/// token keeps delivering a couple's notifications to a handset somebody else
/// may now be holding.
/// Records anniversary edits (**P2-39**); can fail on demand.
class FakeAnniversaryService implements AnniversaryService {
  FakeAnniversaryService({this.error, this.milestone});

  final Object? error;
  final int? milestone;
  final List<DateTime> calls = [];

  @override
  Future<int?> setAnniversary(DateTime date) async {
    calls.add(date);
    if (error case final e?) throw e;
    return milestone;
  }
}

class FakePushService implements PushService {
  final List<String> calls = [];
  final _refresh = StreamController<String>.broadcast();

  @override
  Stream<String> get onTokenRefresh => _refresh.stream;

  /// Simulates FCM rotating the token mid-session.
  void rotate(String token) => _refresh.add(token);

  @override
  Future<String?> register({required String uid}) async {
    calls.add('register:$uid');
    return 'fake-token-$uid';
  }

  @override
  Future<void> unregister({required String uid}) async {
    calls.add('unregister:$uid');
  }

  void dispose() => _refresh.close();
}

/// Writes an `items` document straight into a fake Firestore.
///
/// Bypasses [FeedService] on purpose: seeding is meant to model messages that
/// are *already there*, including ones this client could never have written —
/// the partner's, and another couple's.
///
/// [secondsAgo] orders the thread. Larger is older, so `seedItem(..., 0)` is
/// the newest message.
Future<String> seedItem(
  FakeFirebaseFirestore db, {
  required String coupleId,
  required String senderId,
  String type = 'text',
  String? body,
  String? emoji,
  int secondsAgo = 0,
  Map<String, String> reactions = const {},
  Map<String, dynamic> extra = const {},
}) async {
  final ref = await db.collection('items').add({
    'coupleId': coupleId,
    'senderId': senderId,
    'type': type,
    'createdAt': Timestamp.fromDate(
      DateTime(2026, 7, 30, 9).subtract(Duration(seconds: secondsAgo)),
    ),
    'reactions': reactions,
    'body': ?body,
    'emoji': ?emoji,
    ...extra,
  });
  return ref.id;
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

/// A couple carrying denormalised member names (**M-02**).
/// [uid] is the signed-in member, so membership follows whoever the test is.
Couple fakeCouple({
  String id = 'couple-1',
  String uid = 'uid-test',
  String partnerUid = 'uid-partner',
  String myName = 'Maya',
  String partnerName = 'Devon',
  bool withNames = true,
  String? coupleName,
  int streakCount = 0,
  String? streakBrokenAt,
  // Null models a couple paired before M-10, exactly as withNames: false
  // models one paired before M-02. Both degrade, neither migrates.
  DateTime? anniversaryDate,
}) => Couple(
  id: id,
  memberIds: [uid, partnerUid],
  // withNames: false models a couple formed before M-02 — no migration by
  // design, so the client must degrade rather than blank.
  memberNames: withNames ? {uid: myName, partnerUid: partnerName} : const {},
  coupleName: coupleName,
  anniversaryDate: anniversaryDate,
  streakCount: streakCount,
  streakBrokenAt: streakBrokenAt,
);

/// Overrides for a signed-out session: the gate lands on sign-in.
List<Override> signedOutOverrides({PushService? push}) => [
  pushServiceProvider.overrideWithValue(push ?? FakePushService()),
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
  Couple? couple,
}) => [
  incomingRequestsProvider.overrideWith((ref) => Stream.value(incoming)),
  outgoingRequestProvider.overrideWith((ref) => Stream.value(outgoing)),
  coupleProvider.overrideWith((ref) => Stream.value(couple)),
];

/// Overrides for a signed-in session with the given pairing state.
///
/// [pairingCode] defaults to a claimed code so the pairing screen does not
/// fire `ensurePairingCode` during unrelated tests.
List<Override> signedInOverrides({
  String uid = 'uid-test',
  String displayName = 'Maya',
  String? coupleId,
  String? pairingCode = 'MK4Q7B',
  bool onboardingSeen = true,
  PairingService? pairing,
  List<PairingRequest> incoming = const [],
  PairingRequest? outgoing,
  bool withNames = true,
  String partnerUid = 'uid-partner',
  DateTime? anniversaryDate,
  int streakCount = 0,
  String? streakBrokenAt,
  // A fake Firestore, when the test exercises a real query. Overriding the
  // root provider rather than the feed's own means the query, the mapper and
  // the writes all run for real — only the backend is fake.
  FakeFirebaseFirestore? firestore,
  MoodService? mood,
  AnniversaryService? anniversary,
  SecretService? secret,
  // P3-04. Overridden by default: the real one touches
  // `FirebaseMessaging.instance`, which throws with no Firebase app.
  PushService? push,
  // P2-40. Overridden by default because the real reader is a platform
  // channel, which a widget test has no answer for — the call would hang
  // before `respondToPairing` was ever reached.
  String? deviceTimezone = 'Asia/Karachi',
}) => [
  pushServiceProvider.overrideWithValue(push ?? FakePushService()),
  deviceTimezoneProvider.overrideWithValue(() async => deviceTimezone),
  if (firestore case final db?) firestoreProvider.overrideWithValue(db),
  if (mood case final service?) moodServiceProvider.overrideWithValue(service),
  anniversaryServiceProvider.overrideWithValue(
    anniversary ?? FakeAnniversaryService(),
  ),
  if (secret case final service?)
    secretServiceProvider.overrideWithValue(service),
  authStateProvider.overrideWith((ref) => Stream.value(FakeUser())),
  currentUserProvider.overrideWith(
    (ref) => Stream.value(
      fakeProfile(
        uid: uid,
        displayName: displayName,
        coupleId: coupleId,
        pairingCode: pairingCode,
        onboardingSeen: onboardingSeen,
      ),
    ),
  ),
  pairingServiceProvider.overrideWithValue(pairing ?? FakePairingService()),
  ...pairingStreamOverrides(
    incoming: incoming,
    outgoing: outgoing,
    couple: coupleId == null
        ? null
        : fakeCouple(
            id: coupleId,
            uid: uid,
            partnerUid: partnerUid,
            myName: displayName,
            // The other half of the mock pair, so the title reads sensibly
            // whichever of the two the test is signed in as.
            partnerName: displayName == 'Devon' ? 'Maya' : 'Devon',
            withNames: withNames,
            anniversaryDate: anniversaryDate,
            streakCount: streakCount,
            streakBrokenAt: streakBrokenAt,
          ),
  ),
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

  /// **P2-19** — how many times the Google button reached auth.
  int _googleCalls = 0;
  int get googleCalls => _googleCalls;

  /// Thrown by the fake's Google path when set, so the failure copy is
  /// testable without a live account picker.
  Object? googleError;
  late bool _profilePresent;
  int _recoverCalls = 0;

  /// Exposed so a test can assert the token is cleared on sign-out (P3-04).
  final push = FakePushService();

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
      // P3-04: the gate starts push registration on first build.
      pushServiceProvider.overrideWithValue(push),
      ...pairingStreamOverrides(),
    ];
  }

  void dispose() {
    _controller.close();
    _profiles.close();
    push.dispose();
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

  /// Records the call so P2-19 can assert the button reaches auth without a
  /// live Google account picker.
  @override
  Future<void> signInWithGoogle() async {
    _session._googleCalls++;
    if (_session.googleError case final error?) throw error;
    _session._set(FakeUser());
  }

  @override
  Future<void> signOut() async {
    _session._set(null);
  }
}
