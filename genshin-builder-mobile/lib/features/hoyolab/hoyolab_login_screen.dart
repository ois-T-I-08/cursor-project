import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/hoyolab/hoyolab_constants.dart';
import '../../providers/hoyolab_providers.dart';
import 'widgets/hoyolab_disclaimer_banner.dart';

class HoyolabLoginScreen extends ConsumerStatefulWidget {
  const HoyolabLoginScreen({super.key});

  @override
  ConsumerState<HoyolabLoginScreen> createState() => _HoyolabLoginScreenState();
}

class _HoyolabLoginScreenState extends ConsumerState<HoyolabLoginScreen> {
  WebViewController? _controller;
  var _loading = true;
  var _completing = false;
  String? _error;

  static const _hoyolabHosts = {'m.hoyolab.com', 'www.hoyolab.com'};

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    const loginObserverScript = '''
let signInFormShown = false;

(() => {
  const observer = new MutationObserver(() => {
    const signInForm = document.querySelector("#hyv-account-frame");
    if (signInForm !== null && !signInFormShown) {
      signInFormShown = true;
    } else if (signInForm === null && signInFormShown) {
      if (document.cookie.includes("; ltuid_v2=") || document.cookie.includes("ltuid_v2=")) {
        webViewMessenger.postMessage("tokenReceived");
      } else {
        webViewMessenger.postMessage("signInFormClosed");
      }
      observer.disconnect();
    }
  });

  observer.observe(document.body, {
    childList: true,
    subtree: true,
  });
})();
''';

    final now = DateTime.now().millisecondsSinceEpoch;
    final skipDialogScript = '''
if (location.href.startsWith("https://m.hoyolab.com/") || location.href.startsWith("https://www.hoyolab.com/")) {
  localStorage.setItem("bbs_interest_saved", '{"timestamp":$now,"value":"1632380230"}');
  localStorage.setItem("guide_download_app_dialog", '{"timestamp":$now,"value":$now}');
  true;
} else {
  false;
}
''';

    await WebViewCookieManager().clearCookies();
    final controller = WebViewController();
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            setState(() => _loading = true);
            _runSkipDialogLoop(controller, skipDialogScript);
          },
          onPageFinished: (url) {
            setState(() => _loading = false);
            final host = Uri.parse(url).host;
            if (_hoyolabHosts.contains(host)) {
              controller.runJavaScript(loginObserverScript);
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.parse(request.url);
            if (_hoyolabHosts.contains(uri.host) ||
                (uri.host == 'account.hoyolab.com' &&
                    uri.path != '/single-page/cross-login.html')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..addJavaScriptChannel(
        'webViewMessenger',
        onMessageReceived: (message) async {
          if (message.message == 'signInFormClosed') {
            if (mounted) Navigator.of(context).pop();
            return;
          }
          if (message.message == 'tokenReceived') {
            await _completeLogin();
          }
        },
      )
      ..loadRequest(Uri.parse(HoyolabConstants.loginUrl));

    if (!mounted) return;
    setState(() => _controller = controller);
  }

  Future<void> _runSkipDialogLoop(
    WebViewController controller,
    String script,
  ) async {
    for (var i = 0; i < 30; i++) {
      final result = await controller.runJavaScriptReturningResult(script);
      if (result == true || result == 'true') return;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _completeLogin() async {
    if (_completing) return;
    setState(() {
      _completing = true;
      _error = null;
    });

    try {
      final useCase = await ref.read(
        completeHoyolabWebLoginUseCaseProvider.future,
      );
      final result = await useCase();
      if (!mounted) return;
      if (result.success) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _completing = false;
        _error = result.userMessage ?? '連携に失敗しました。ログイン状態を確認して再試行してください。';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _completing = false;
        _error = '連携に失敗しました。ログイン状態を確認して再試行してください。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(title: const Text('HoYoLAB ログイン')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: HoyolabDisclaimerBanner(compact: true),
          ),
          Expanded(
            child:
                controller == null
                    ? const Center(child: CircularProgressIndicator())
                    : Stack(
                      children: [
                        WebViewWidget(controller: controller),
                        if (_loading)
                          const Center(child: CircularProgressIndicator()),
                      ],
                    ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'HoYoLAB にログインすると自動で連携が完了します。'
                    'ログイン後に反応がない場合は下のボタンを押してください。',
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _completing ? null : _completeLogin,
                    icon:
                        _completing
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.check),
                    label: const Text('連携を完了'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
