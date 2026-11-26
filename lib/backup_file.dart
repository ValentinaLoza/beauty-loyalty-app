// Saving and opening backup files in the browser.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Downloads [content] as a file named [fileName].
void downloadTextFile(String fileName, String content) {
  final bytes = utf8.encode(content).toJS;
  final blob = web.Blob(
    <JSAny>[bytes].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  // Some mobile browsers start the download asynchronously.
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}

/// Lets the person choose a .json file and returns its text, or null if
/// they cancel.
Future<String?> pickTextFile() {
  final completer = Completer<String?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.json,application/json'
    ..style.display = 'none';

  void finish(String? value) {
    if (!completer.isCompleted) completer.complete(value);
    input.remove();
  }

  input.addEventListener(
    'change',
    ((web.Event _) {
      final file = input.files?.item(0);
      if (file == null) {
        finish(null);
        return;
      }
      file.text().toDart.then(
            (text) => finish(text.toDart),
            onError: (Object _) => finish(null),
          );
    }).toJS,
  );
  input.addEventListener('cancel', ((web.Event _) => finish(null)).toJS);

  web.document.body!.append(input);
  input.click();
  return completer.future;
}
