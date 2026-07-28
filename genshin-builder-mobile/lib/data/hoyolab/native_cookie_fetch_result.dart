/// Result of a native [MethodChannel] cookie fetch (data layer only).
enum NativeCookieFetchStatus {
  /// Non-empty cookie string returned.
  ok,

  /// No cookie / empty (normal).
  absent,

  /// CookieManager threw; WebView fallback should still run.
  managerError,

  /// Plugin not registered; WebView fallback should still run.
  pluginMissing,
}

class NativeCookieFetchResult {
  const NativeCookieFetchResult._(this.status, [this.value]);

  const NativeCookieFetchResult.ok(String cookie)
    : this._(NativeCookieFetchStatus.ok, cookie);

  const NativeCookieFetchResult.absent()
    : this._(NativeCookieFetchStatus.absent);

  const NativeCookieFetchResult.managerError()
    : this._(NativeCookieFetchStatus.managerError);

  const NativeCookieFetchResult.pluginMissing()
    : this._(NativeCookieFetchStatus.pluginMissing);

  final NativeCookieFetchStatus status;
  final String? value;

  bool get isOk => status == NativeCookieFetchStatus.ok;
}
