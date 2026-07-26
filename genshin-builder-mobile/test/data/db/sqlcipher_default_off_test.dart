import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/db/drift/app_database.dart';

void main() {
  test('production default does not enable SQLCipher encryption', () {
    // Forced plaintext→SQLCipher migration must not start without dart-define.
    expect(kEnableSqlCipher, isFalse);
  });
}
