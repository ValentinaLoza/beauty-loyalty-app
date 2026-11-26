// Fills the branding placeholders of the compiled web app.
//
//   dart run tool/apply_brand.dart [config/local.json] [build/web]
//
// Reads APP_TITLE, APP_SHORT_NAME (optional, defaults to APP_TITLE) and
// THEME_COLOR (optional, #RRGGBB) from the config file and replaces
// {{APP_NAME}}, {{APP_SHORT_NAME}} and {{THEME_COLOR}} in the static files
// Flutter copied from web/ (page titles, PWA manifests, push worker).
import 'dart:convert';
import 'dart:io';

const _files = <String>[
  'index.html',
  'manifest.json',
  'client-manifest.json',
  'client/index.html',
  'push-sw.js',
];

void main(List<String> args) {
  final configPath = args.isNotEmpty ? args[0] : 'config/local.json';
  final outDir = args.length > 1 ? args[1] : 'build/web';

  final config =
      jsonDecode(File(configPath).readAsStringSync()) as Map<String, dynamic>;

  final name = (config['APP_TITLE'] as String?)?.trim();
  if (name == null || name.isEmpty) {
    stderr.writeln('APP_TITLE is missing in $configPath');
    exit(1);
  }
  final shortName =
      (config['APP_SHORT_NAME'] as String?)?.trim().isNotEmpty == true
          ? (config['APP_SHORT_NAME'] as String).trim()
          : name;
  final color = (config['THEME_COLOR'] as String?)?.trim() ?? '#8F5E78';
  if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
    stderr.writeln('THEME_COLOR must look like #8F5E78, got "$color"');
    exit(1);
  }

  String escapeFor(String file, String value) {
    if (file.endsWith('.html')) {
      return const HtmlEscape(HtmlEscapeMode.attribute).convert(value);
    }
    // JSON and JS string literals.
    final encoded = jsonEncode(value);
    return encoded.substring(1, encoded.length - 1);
  }

  for (final relative in _files) {
    final file = File('$outDir/$relative');
    if (!file.existsSync()) {
      stderr.writeln('Missing $outDir/$relative — run flutter build web first');
      exit(1);
    }
    final text = file
        .readAsStringSync()
        .replaceAll('{{APP_NAME}}', escapeFor(relative, name))
        .replaceAll('{{APP_SHORT_NAME}}', escapeFor(relative, shortName))
        .replaceAll('{{THEME_COLOR}}', color);
    file.writeAsStringSync(text);
  }

  stdout.writeln('Branding applied: "$name" ($shortName, $color)');
}
