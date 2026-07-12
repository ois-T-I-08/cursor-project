package io.github.oisti08.genshinbuilder

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // MethodChannel handlers run on the Android main (UI) thread by default.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "genshin_builder_mobile/hoyolab_cookie",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "fetchCookie" -> fetchHoyolabCookie(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun fetchHoyolabCookie(result: MethodChannel.Result) {
        try {
            val manager = CookieManager.getInstance()
            val domains = listOf(
                "https://m.hoyolab.com",
                "https://www.hoyolab.com",
                "https://act.hoyolab.com",
                "https://account.hoyolab.com",
            )
            for (domain in domains) {
                try {
                    val cookie = manager.getCookie(domain)
                    if (!cookie.isNullOrBlank() && hasAuthCookie(cookie)) {
                        result.success(cookie)
                        return
                    }
                } catch (_: Exception) {
                    // Continue other domains; do not put cookie bodies in errors.
                }
            }
            // No usable cookie is a normal state (not an error).
            result.success(null)
        } catch (_: Exception) {
            result.error(
                "COOKIE_MANAGER_ERROR",
                "Cookie manager failed",
                null,
            )
        }
    }

    private fun hasAuthCookie(cookie: String): Boolean {
        return cookie.contains("ltoken_v2=") ||
            cookie.contains("ltoken=") ||
            cookie.contains("ltuid_v2=") ||
            cookie.contains("account_id_v2=")
    }
}
