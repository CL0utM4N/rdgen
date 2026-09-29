import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// Asks where to save [bytes] and writes them there. False if cancelled.
Future<bool> saveBytes(String name, List<int> bytes) async {
  final path = await FilePicker.platform.saveFile(fileName: name);
  if (path == null) return false;
  await File(path).writeAsBytes(bytes, flush: true);
  return true;
}
