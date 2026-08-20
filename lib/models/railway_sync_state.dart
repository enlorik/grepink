enum RailwaySyncStatus {
  notConfigured,
  idle,
  syncing,
  upToDate,
  pendingChanges,
  offline,
  authFailed,
  error,
}

class RailwaySyncState {
  final RailwaySyncStatus status;
  final DateTime? lastSyncedAt;
  final String? errorMessage;
  final bool conflictPreserved;

  const RailwaySyncState({
    this.status = RailwaySyncStatus.notConfigured,
    this.lastSyncedAt,
    this.errorMessage,
    this.conflictPreserved = false,
  });

  RailwaySyncState copyWith({
    RailwaySyncStatus? status,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? conflictPreserved,
  }) {
    return RailwaySyncState(
      status: status ?? this.status,
      lastSyncedAt:
          clearLastSyncedAt ? null : (lastSyncedAt ?? this.lastSyncedAt),
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      conflictPreserved: conflictPreserved ?? this.conflictPreserved,
    );
  }
}
