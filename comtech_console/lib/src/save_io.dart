import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// Asks where to save [bytes] and writes them there. False if cancelled.
Future<bool> saveBytes(String name, List<int> bytes) async {
  String? path;
  if (Platform.isAndroid || Platform.isIOS) {
    // phones can't ask for a file name, only a folder
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return false;
    path = '$dir/$name';
  } else {
    path = await FilePicker.platform.saveFile(fileName: name);
  }
  if (path == null) return false;
  await File(path).writeAsBytes(bytes, flush: true);
  return true;
}
