import 'dart:io';

/// Opens a web page or folder with the OS default handler.
Future<void> openExternal(String target) async {
  if (Platform.isMacOS) {
    await Process.run('open', [target]);
  } else if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', target]);
  } else {
    await Process.run('xdg-open', [target]);
  }
}
