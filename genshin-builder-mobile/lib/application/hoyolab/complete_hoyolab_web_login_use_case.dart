import '../../core/errors/user_facing_error.dart';
import '../../data/hoyolab/hoyolab_cookie_service.dart';
import '../../data/hoyolab/hoyolab_exceptions.dart';
import '../../data/repositories/hoyolab_repository.dart';

/// UI-safe result of completing HoYoLAB WebView login (no cookie bodies).
class HoyolabWebLoginResult {
  const HoyolabWebLoginResult._({required this.success, this.userMessage});

  const HoyolabWebLoginResult.success() : this._(success: true);

  const HoyolabWebLoginResult.failure(String userMessage)
    : this._(success: false, userMessage: userMessage);

  final bool success;
  final String? userMessage;
}

/// One-shot: collect cookie → existing [HoyolabRepository.completeLogin] → UI result.
class CompleteHoyolabWebLoginUseCase {
  const CompleteHoyolabWebLoginUseCase({
    required HoyolabCookieService cookieService,
    required HoyolabRepository repository,
  }) : _cookies = cookieService,
       _repository = repository;

  final HoyolabCookieService _cookies;
  final HoyolabRepository _repository;

  Future<HoyolabWebLoginResult> call() async {
    final cookie = await _cookies.collectNormalizedCookie();
    if (cookie == null) {
      return const HoyolabWebLoginResult.failure(
        'Cookie を取得できませんでした。ログイン完了後にもう一度お試しください。',
      );
    }

    try {
      await _repository.completeLogin(cookie: cookie);
      return const HoyolabWebLoginResult.success();
    } on HoyolabApiException catch (e) {
      return HoyolabWebLoginResult.failure(e.userMessage);
    } catch (e, st) {
      logAppError(e, st, 'hoyolab.webLogin');
      return HoyolabWebLoginResult.failure(
        userFacingError(e, fallback: '連携に失敗しました。ログイン状態を確認して再試行してください。'),
      );
    }
  }
}
