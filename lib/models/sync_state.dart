enum SyncStatus { idle, syncing, error }

class SyncState {
  final SyncStatus status;
  final DateTime? lastSyncedAt;
  final String? errorMessage;
  final bool isSignedIn;
  final String? accountEmail;

  const SyncState({
    this.status = SyncStatus.idle,
    this.lastSyncedAt,
    this.errorMessage,
    this.isSignedIn = false,
    this.accountEmail,
  });

  SyncState copyWith({
    SyncStatus? status,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isSignedIn,
    String? accountEmail,
    bool clearAccountEmail = false,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastSyncedAt: clearLastSyncedAt ? null : (lastSyncedAt ?? this.lastSyncedAt),
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      isSignedIn: isSignedIn ?? this.isSignedIn,
      accountEmail: clearAccountEmail ? null : (accountEmail ?? this.accountEmail),
    );
  }
}
