import 'package:flutter/foundation.dart';

/// Android のシステム Back を AppShell で扱うか。
///
/// Web では [defaultTargetPlatform] が Android になり得るため [kIsWeb] で除外する。
bool get isAndroidSystemBackHandlingEnabled =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
