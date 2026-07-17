import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/application/legal/legal_url_launcher.dart';
import 'package:genshin_builder_mobile/features/settings/legal_documents_section.dart';

void main() {
  Future<void> pumpSection(
    WidgetTester tester, {
    required LegalUrlLauncher launcher,
    ThemeData? theme,
    Size? size,
    double textScaleFactor = 1,
  }) async {
    if (size != null) {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
              child: child!,
            ),
        home: Scaffold(
          body: ListView(children: [LegalDocumentsSection(launcher: launcher)]),
        ),
      ),
    );
  }

  testWidgets('shows distinct privacy policy and terms links', (tester) async {
    await pumpSection(tester, launcher: (_) async => true);

    expect(find.text('法的情報'), findsOneWidget);
    expect(find.text('プライバシーポリシー'), findsOneWidget);
    expect(find.text('利用規約'), findsOneWidget);
    expect(find.text('外部ブラウザで開きます'), findsNWidgets(2));
  });

  testWidgets('opens the official privacy policy URL', (tester) async {
    final launched = <Uri>[];
    await pumpSection(
      tester,
      launcher: (uri) async {
        launched.add(uri);
        return true;
      },
    );

    await tester.tap(find.byKey(const Key('privacy-policy-link')));
    await tester.pump();

    expect(launched, [Uri.parse(privacyPolicyUrl)]);
  });

  testWidgets('opens the official terms URL', (tester) async {
    final launched = <Uri>[];
    await pumpSection(
      tester,
      launcher: (uri) async {
        launched.add(uri);
        return true;
      },
    );

    await tester.tap(find.byKey(const Key('terms-of-use-link')));
    await tester.pump();

    expect(launched, [Uri.parse(termsOfUseUrl)]);
  });

  testWidgets('shows a safe error when the browser cannot open the URL', (
    tester,
  ) async {
    await pumpSection(tester, launcher: (_) async => false);

    await tester.tap(find.byKey(const Key('privacy-policy-link')));
    await tester.pump();

    expect(find.text('ページを開けませんでした。通信環境またはブラウザ設定を確認してください。'), findsOneWidget);
  });

  testWidgets('shows the same safe error when the launcher throws', (
    tester,
  ) async {
    await pumpSection(
      tester,
      launcher: (_) => throw StateError('sensitive implementation detail'),
    );

    await tester.tap(find.byKey(const Key('privacy-policy-link')));
    await tester.pump();

    expect(find.text('ページを開けませんでした。通信環境またはブラウザ設定を確認してください。'), findsOneWidget);
    expect(
      find.textContaining('sensitive implementation detail'),
      findsNothing,
    );
  });

  testWidgets('prevents another launch while one is in progress', (
    tester,
  ) async {
    final pending = Completer<bool>();
    var launches = 0;
    await pumpSection(
      tester,
      launcher: (_) {
        launches++;
        return pending.future;
      },
    );

    await tester.tap(find.byKey(const Key('privacy-policy-link')));
    await tester.pump();

    final termsTile = tester.widget<ListTile>(
      find.byKey(const Key('terms-of-use-link')),
    );
    expect(termsTile.enabled, isFalse);
    expect(launches, 1);

    pending.complete(true);
    await tester.pump();
  });

  testWidgets('does not update state after disposal', (tester) async {
    final pending = Completer<bool>();
    await pumpSection(tester, launcher: (_) => pending.future);

    await tester.tap(find.byKey(const Key('privacy-policy-link')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    pending.complete(true);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders on a small screen in light and dark themes', (
    tester,
  ) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await pumpSection(
        tester,
        launcher: (_) async => true,
        theme: ThemeData(brightness: brightness),
        size: const Size(320, 480),
        textScaleFactor: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('プライバシーポリシー'), findsOneWidget);
      expect(find.text('利用規約'), findsOneWidget);
    }
  });
}
