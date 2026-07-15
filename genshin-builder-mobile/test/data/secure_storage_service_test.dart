import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/secure/secure_storage_service.dart';

class _MemorySecureStorage extends SecureStorageService {
  final values = <String, String>{};
  int writes = 0;

  @override
  Future<String?> read(String key) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    values[key] = value;
  }
}

void main() {
  test('concurrent DB key requests share one generated key', () async {
    final storage = _MemorySecureStorage();

    final keys = await Future.wait([
      storage.getOrCreateDbKey(),
      storage.getOrCreateDbKey(),
      storage.getOrCreateDbKey(),
    ]);

    expect(keys.toSet(), hasLength(1));
    expect(storage.writes, 1);
  });
}
