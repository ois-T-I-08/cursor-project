import 'package:url_launcher/url_launcher.dart';

Future<bool> launchExternalLegalUrl(Uri uri) {
  if (uri.scheme != 'https' || uri.host.isEmpty) {
    return Future.value(false);
  }
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
