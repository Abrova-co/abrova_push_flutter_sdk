// Copies the Abrova Push service worker into a Flutter web app, for `AbrovaPushConfig(webPush: true)`.
//
//   dart run abrova_push:web_push_setup          (in the app's folder, the one with pubspec.yaml and web/)
//   dart run abrova_push:web_push_setup --root   (also for webPushAtRoot: true — writes web/flutter_bootstrap.js so
//                                                 Flutter's own service worker is not started)
//
// Run it again after upgrading abrova_push, so the worker matches the package.
import 'dart:io';
import 'dart:isolate';

Future<void> main(List<String> args) async {
  final web = Directory('web');
  if (!web.existsSync()) {
    stderr.writeln('No web/ folder here. Run this in the Flutter app folder (add web with `flutter create --platforms=web .`).');
    exit(1);
  }
  final library = await Isolate.resolvePackageUri(Uri.parse('package:abrova_push/abrova_push.dart'));
  if (library == null) {
    stderr.writeln('abrova_push is not a dependency of this app.');
    exit(1);
  }
  final source = File.fromUri(library.resolve('../assets/web/abrova-push-sw.js'));
  if (!source.existsSync()) {
    stderr.writeln('The service worker is missing from the abrova_push package (${source.path}).');
    exit(1);
  }
  final target = File('web/abrova-push-sw.js');
  source.copySync(target.path);
  stdout.writeln('Copied abrova-push-sw.js to ${target.path}. Use AbrovaPushConfig(webPush: true).');

  if (args.contains('--root')) {
    final bootstrap = File('web/flutter_bootstrap.js');
    if (bootstrap.existsSync() && !bootstrap.readAsStringSync().contains(_bootstrapMark)) {
      stderr.writeln('web/flutter_bootstrap.js exists and is your own: make sure its _flutter.loader.load() has no '
          'serviceWorkerSettings, then use AbrovaPushConfig(webPush: true, webPushAtRoot: true).');
      exit(1);
    }
    bootstrap.writeAsStringSync(_bootstrap);
    stdout.writeln('Wrote ${bootstrap.path} (Flutter\'s own service worker off). Use AbrovaPushConfig(webPush: true, webPushAtRoot: true).');
  }
}

const _bootstrapMark = 'abrova_push:web_push_setup';

/// Flutter's default bootstrap without serviceWorkerSettings: Flutter's own worker would take the root scope.
const _bootstrap = """// Written by `dart run abrova_push:web_push_setup --root`: Flutter's own service worker is not started, so the
// Abrova Push worker keeps the root scope (webPushAtRoot: true).
{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load();
""";
