/// Lifecycle of a `pairingRequests/{id}` document.
///
/// `expired` is deliberately doing two jobs: it is what the 7-day sweep
/// (**P2-28**) writes *and* what a decline writes (**P2-09b**). The sender
/// cannot tell the two apart, and that is the point — **PI-05** forbids telling
/// them a person refused. Never surface this as "declined" or "rejected".
enum PairingRequestStatus {
  pending,
  accepted,

  /// Timed out, or declined. Indistinguishable on purpose.
  expired,

  /// Withdrawn by the sender (**P2-09c**).
  cancelled;

  /// Unknown values map to [expired] rather than throwing.
  ///
  /// Same reasoning as the reveal-duration fallback: if a later server version
  /// introduces a status this build has never heard of, an old client must
  /// degrade to "no longer waiting" instead of crashing on new data.
  static PairingRequestStatus parse(String? raw) {
    return switch (raw) {
      'pending' => PairingRequestStatus.pending,
      'accepted' => PairingRequestStatus.accepted,
      'cancelled' => PairingRequestStatus.cancelled,
      _ => PairingRequestStatus.expired,
    };
  }
}

/// A row of `pairingRequests/{id}`.
///
/// Written only by the callables; the client never writes this collection.
class PairingRequest {
  const PairingRequest({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.status,
    required this.fromDisplayName,
    this.fromAvatarUrl,
    this.createdAt,
  });

  final String id;
  final String fromUid;
  final String toUid;
  final PairingRequestStatus status;

  /// The sender's name *as it was when they asked*, denormalised by
  /// `requestPairing` so the recipient can render it without a rule that lets
  /// anyone read anyone's profile. A later rename does not update it, on
  /// purpose — see the comment in `functions/src/pairing.ts`.
  final String fromDisplayName;

  final String? fromAvatarUrl;
  final DateTime? createdAt;

  bool get isPending => status == PairingRequestStatus.pending;

  factory PairingRequest.fromFirestore(String id, Map<String, dynamic> data) {
    final name = (data['fromDisplayName'] as String?)?.trim();

    return PairingRequest(
      id: id,
      fromUid: data['fromUid'] as String? ?? '',
      toUid: data['toUid'] as String? ?? '',
      status: PairingRequestStatus.parse(data['status'] as String?),
      // The server bounds and defaults this, but a request created before the
      // field existed has none — never render a blank where a name goes.
      fromDisplayName: (name == null || name.isEmpty) ? 'Someone' : name,
      fromAvatarUrl: data['fromAvatarUrl'] as String?,
      // Duck-typed: a pending write has no Timestamp yet. Same as P2-22.
      createdAt: switch (data['createdAt']) {
        null => null,
        final DateTime value => value,
        final Object value => (value as dynamic).toDate() as DateTime,
      },
    );
  }
}
