import 'i18n_en.dart';

/// Looks up the web console's wording for [key], filling in {name} style
/// placeholders from [params]. [n] above 1 picks the plural form.
String T(String key, [Map<String, Object?>? params, int n = 0]) {
  final forms = kEnglish[key] ?? _extra[key];
  if (forms == null) return key;
  final msg = n > 1 && forms.length > 1 ? forms[1] : forms[0];
  if (params == null) return msg;
  return msg.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
    final v = params[m.group(1)];
    return v == null || v == '' ? m.group(0)! : '$v';
  });
}

/// Wording only the app needs, or that the web console left untranslated.
const _extra = <String, List<String>>{
  'ChooseFile': ['Choose file'],
  'ClientNotAvailable': ['The RustDesk client isn\'t available here.'],
  'ClientSettings': ['RustDesk settings'],
  'DarkMode': ['Dark mode'],
  'LightMode': ['Light mode'],
  'Id': ['ID'],
  'IdP': ['Identity provider'],
  'Information': ['Information'],
  'InvalidParam': ['{param} isn\'t valid'],
  'NoAccess': ['You don\'t have access to this page.'],
  'NoData': ['No data'],
  'PkceEnable': ['PKCE'],
  'PkceMethod': ['PKCE method'],
  'Select': ['Select'],
  'Success': ['Done'],
  'Token': ['Token'],
  'TransferFiles': ['Transfer files'],
  'View': ['View'],
  'WaitingForBrowser': ['Finish signing in in your browser…'],
  'or login in with': ['or sign in with'],
};

/// "5 minutes ago", matching the web console.
String timeAgo(int unixSeconds) {
  final dis = DateTime.now().millisecondsSinceEpoch - unixSeconds * 1000;
  const minute = 60 * 1000, hour = 60 * minute, day = 24 * hour, month = 30 * day;
  if (dis < minute) return T('JustNow');
  if (dis < hour) return _ago('MinutesAgo', dis ~/ minute);
  if (dis < day) return _ago('HoursAgo', dis ~/ hour);
  if (dis < month) return _ago('DaysAgo', dis ~/ day);
  if (dis < 12 * month) return _ago('MonthsAgo', dis ~/ month);
  return _ago('YearsAgo', dis ~/ (12 * month));
}

String _ago(String key, int n) => T(key, {'param': n}, n);

String _pad(int n) => n.toString().padLeft(2, '0');

/// 2026-09-29 14:05:09
String formatTime(int unixSeconds, {bool seconds = true}) {
  if (unixSeconds <= 0) return '-';
  final d = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  final s = '${d.year}-${_pad(d.month)}-${_pad(d.day)} ${_pad(d.hour)}:${_pad(d.minute)}';
  return seconds ? '$s:${_pad(d.second)}' : s;
}

String formatDay(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

/// 1.5 MB
String sizeFormat(num? bytes) {
  final b = (bytes ?? 0).toDouble();
  if (b <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  var v = b;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
}
