import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/legal/legal_url_launcher.dart';
import '../data/legal/url_launcher_legal_url_launcher.dart';

final legalUrlLauncherProvider = Provider<LegalUrlLauncher>((ref) {
  return launchExternalLegalUrl;
});
