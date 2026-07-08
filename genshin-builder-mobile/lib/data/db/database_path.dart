import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// sqflite と同等の DB ディレクトリを path_provider のみで解決する。
Future<File> resolveDatabaseFile(String fileName) async {
  final primary = await _primaryDatabaseFile(fileName);
  if (await primary.exists()) return primary;

  for (final legacy in await _legacyDatabaseCandidates(fileName)) {
    if (await legacy.exists()) {
      await primary.parent.create(recursive: true);
      await legacy.copy(primary.path);
      return primary;
    }
  }

  await primary.parent.create(recursive: true);
  return primary;
}

Future<File> _primaryDatabaseFile(String fileName) async {
  final dir = await _primaryDatabaseDirectory();
  return File(p.join(dir.path, fileName));
}

Future<Directory> _primaryDatabaseDirectory() async {
  if (Platform.isAndroid) {
    final docs = await getApplicationDocumentsDirectory();
    final parent = Directory(p.dirname(docs.path));
    return Directory(p.join(parent.path, 'databases'));
  }

  if (Platform.isIOS || Platform.isMacOS) {
    return getApplicationDocumentsDirectory();
  }

  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'databases'));
}

Future<List<File>> _legacyDatabaseCandidates(String fileName) async {
  final candidates = <File>[];

  if (Platform.isAndroid) {
    final docs = await getApplicationDocumentsDirectory();
    final parent = Directory(p.dirname(docs.path));
    candidates.add(File(p.join(parent.path, 'databases', fileName)));
  }

  if (Platform.isIOS || Platform.isMacOS) {
    final docs = await getApplicationDocumentsDirectory();
    candidates.add(File(p.join(docs.path, fileName)));
  }

  final support = await getApplicationSupportDirectory();
  candidates.add(File(p.join(support.path, 'databases', fileName)));

  final docs = await getApplicationDocumentsDirectory();
  candidates.add(File(p.join(docs.path, 'databases', fileName)));

  if (Platform.isWindows || Platform.isLinux) {
    final exeDir = Directory(p.dirname(Platform.resolvedExecutable));
    candidates.add(File(p.join(exeDir.path, 'databases', fileName)));
  }

  return candidates;
}
