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
      return copyDatabaseFileAtomically(legacy, primary);
    }
  }

  await primary.parent.create(recursive: true);
  return primary;
}

/// Copies a legacy DB without ever exposing a partially-written destination.
///
/// The source is retained. Only the temporary copy is removed on failure.
Future<File> copyDatabaseFileAtomically(File source, File destination) async {
  if (await destination.exists()) return destination;
  await destination.parent.create(recursive: true);

  final temporary = File(
    '${destination.path}.copying-$pid-${DateTime.now().microsecondsSinceEpoch}',
  );
  try {
    final copied = await source.copy(temporary.path);
    if (await copied.length() != await source.length()) {
      throw const FileSystemException('Database copy verification failed');
    }

    if (await destination.exists()) {
      await temporary.delete();
      return destination;
    }
    return await temporary.rename(destination.path);
  } catch (_) {
    if (await temporary.exists()) {
      await temporary.delete();
    }
    rethrow;
  }
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
