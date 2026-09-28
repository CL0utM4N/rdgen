
// Comtech: settings the Client Builder puts in the app (assets/custom.txt),
// signed so only our server can make them
Future<String> _comtechCustomConfig() async {
  try {
    return (await rootBundle.loadString('assets/custom.txt')).trim();
  } catch (_) {
    return '';
  }
}
