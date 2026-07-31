import 'package:cloud_functions/cloud_functions.dart';

/// Client edge of the `ensureUserProfile` callable (**P2-30**, **P2-35**).
///
/// The profile document is written **only** by the server. The client used to
/// create it directly, which was fine until a missing profile had to be
/// recreated for someone who is still in a couple: the client can neither
/// discover their `coupleId` (the `couples` list rule is false) nor write it
/// (the users rules reject any client write to `coupleId`). Rather than relax
/// either rule, the write moved.
abstract interface class ProfileService {
  /// Creates `users/{uid}` if it is missing and returns its state.
  ///
  /// Idempotent: an existing document is returned untouched.
  Future<ProfileState> ensureProfile({String? displayName});
}

/// What the caller needs back from [ProfileService.ensureProfile].
class ProfileState {
  const ProfileState({required this.created, this.coupleId, this.pairingCode});

  /// True when this call wrote the document.
  final bool created;
  final String? coupleId;
  final String? pairingCode;

  factory ProfileState.fromCallable(Map<Object?, Object?> data) {
    return ProfileState(
      created: data['created'] == true,
      coupleId: data['coupleId'] as String?,
      pairingCode: data['pairingCode'] as String?,
    );
  }
}

class FirebaseFunctionsProfileService implements ProfileService {
  const FirebaseFunctionsProfileService(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<ProfileState> ensureProfile({String? displayName}) async {
    final result = await _functions.httpsCallable('ensureUserProfile').call({
      'displayName': ?displayName,
    });
    return ProfileState.fromCallable(result.data as Map<Object?, Object?>);
  }
}
