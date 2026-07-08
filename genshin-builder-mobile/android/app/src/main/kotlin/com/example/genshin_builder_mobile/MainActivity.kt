package com.example.genshin_builder_mobile

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "genshin_builder_mobile/hoyolab_cookie",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "fetchCookie" -> result.success(fetchHoyolabCookie())
                else -> result.notImplemented()
            }
        }
    }

    private fun fetchHoyolabCookie(): String? {
        val manager = CookieManager.getInstance()
        val domains = listOf(
            "https://m.hoyolab.com",
            "https://www.hoyolab.com",
            "https://act.hoyolab.com",
            "https://account.hoyolab.com",
        )
        for (domain in domains) {
            val cookie = manager.getCookie(domain)
            if (!cookie.isNullOrBlank() && hasAuthCookie(cookie)) {
                return cookie
            }
        }
        return null
    }

    private fun hasAuthCookie(cookie: String): Boolean {
        return cookie.contains("ltoken_v2=") ||
            cookie.contains("ltoken=") ||
            cookie.contains("ltuid_v2=") ||
            cookie.contains("account_id_v2=")
    }
}
