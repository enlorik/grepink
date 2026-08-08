import 'dart:io';

Future<void> writeToDesktopPath(String path, List<int> bytes) async {
  await File(path).writeAsBytes(bytes);
}
