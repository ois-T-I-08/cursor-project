enum DatabaseFailureKind {
  migration,
  downgrade,
  locked,
  corrupt,
  io,
  readOnly,
  diskFull,
  unknown,
}

/// Safe database-open failure. It intentionally carries no path, SQL, or data.
class DatabaseOpenException implements Exception {
  const DatabaseOpenException(this.kind);

  final DatabaseFailureKind kind;

  String get code => 'database_${kind.name}';

  @override
  String toString() => code;
}
