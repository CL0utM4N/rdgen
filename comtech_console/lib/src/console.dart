import 'package:flutter/foundation.dart';

import 'api.dart';
import 'host.dart';
import 'widgets/dialog.dart';
import 'widgets/table.dart' show Row_;

/// The signed in user, where they are in the console and the theme.
class Console extends ChangeNotifier {
  static late Console I;

  final ConsoleHost host;
  late final Api api;

  bool dark;
  bool ready = false;
  bool sideCollapsed = false;

  Map<String, dynamic> user = {};
  List<String> routeNames = [];
  List<String> permissions = [];

  String route = 'Dashboard';
  Map<String, dynamic> args = {};

  /// Bumped on every navigation so the page is rebuilt fresh, like a route change.
  int nav = 0;

  String title = 'ComTech IT Remote';
  String hello = '';
  Map<String, dynamic> server = {};
  Map<String, dynamic> app = {};

  Console(this.host) : dark = host.loadSetting('console-dark') == null ? host.startDark : host.loadSetting('console-dark') == 'Y' {
    I = this;
    dialogDark = dark;
    api = Api(host.apiServer)
      ..onError = Toasts.error
      ..onSignedOut = () => signOut(tellServer: false);
  }

  bool get signedIn => user.isNotEmpty;
  String get displayName => '${user['nickname'] ?? ''}'.isNotEmpty ? '${user['nickname']}' : '${user['username'] ?? ''}';

  /// Whether the role holds any of [keys]; admins hold them all.
  bool can(List<String> keys) => permissions.contains('*') || keys.any(permissions.contains);

  bool canRoute(String name) => routeNames.contains('*') || routeNames.contains(name);

  /// Picks up a saved sign-in, or the one the client is using.
  Future<void> restore() async {
    for (final token in [host.loadSetting('console-token'), host.clientToken]) {
      if (token == null || token.isEmpty) continue;
      api.token = token;
      try {
        final data = await api.get('/user/current', quiet: true);
        if (data is Map) {
          _apply(Map<String, dynamic>.from(data), token);
          break;
        }
      } catch (_) {
        api.token = null;
      }
    }
    ready = true;
    notifyListeners();
  }

  /// Called after the login (and two-factor) step succeeds.
  void signedIn_(Map<String, dynamic> data) {
    _apply(data, '${data['token'] ?? ''}');
    notifyListeners();
  }

  void _apply(Map<String, dynamic> data, String token) {
    final t = '${data['token'] ?? ''}'.isNotEmpty ? '${data['token']}' : token;
    api.token = t;
    host.saveSetting('console-token', t);
    user = data;
    routeNames = List<String>.from(data['route_names'] ?? const []);
    permissions = List<String>.from(data['permissions'] ?? const []);
    route = canRoute('Dashboard') ? 'Dashboard' : 'MyInfo';
    args = {};
    nav++;
    host.onSignedIn(t);
    loadConfig();
  }

  Future<void> loadConfig() async {
    try {
      final a = await api.get('/config/admin', quiet: true);
      if (a is Map) {
        title = '${a['title'] ?? title}';
        hello = '${a['hello'] ?? ''}';
      }
    } catch (_) {}
    try {
      final s = await api.get('/config/server', quiet: true);
      if (s is Map) server = Map<String, dynamic>.from(s);
    } catch (_) {}
    try {
      final s = await api.get('/config/app', quiet: true);
      if (s is Map) app = Map<String, dynamic>.from(s);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> signOut({bool tellServer = true}) async {
    if (!signedIn && api.token == null) return;
    if (tellServer) {
      try {
        await api.post('/logout', quiet: true);
      } catch (_) {}
    }
    api.token = null;
    host.saveSetting('console-token', '');
    user = {};
    routeNames = [];
    permissions = [];
    host.onSignedOut();
    notifyListeners();
  }

  void go(String name, [Map<String, dynamic>? a]) {
    route = name;
    args = a ?? {};
    nav++;
    notifyListeners();
  }

  void toggleDark() {
    dark = !dark;
    dialogDark = dark;
    host.saveSetting('console-dark', dark ? 'Y' : 'N');
    host.onThemeChanged(dark);
    notifyListeners();
  }

  void toggleSide() {
    sideCollapsed = !sideCollapsed;
    notifyListeners();
  }
}

Api get api => Console.I.api;
bool can(List<String> keys) => Console.I.can(keys);

/// A paged list: its filters, the current page, the rows and which are ticked.
class ListCtl extends ChangeNotifier {
  final Future<dynamic> Function(Map<String, dynamic> query) fetch;
  final Map<String, dynamic> query;
  final Future<void> Function(List<Row_> rows)? decorate;

  int page = 1;
  int pageSize;
  int total = 0;
  bool loading = false;
  List<Row_> list = [];
  Set<int> selected = {};

  /// The whole response, for pages that read more than the list.
  dynamic data;

  ListCtl(this.fetch, {Map<String, dynamic>? query, this.pageSize = 10, this.decorate}) : query = query ?? {};

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      final d = await fetch({...query, 'page': page, 'page_size': pageSize});
      data = d;
      final r = PageResult.from(d);
      if (decorate != null) await decorate!(r.list);
      list = r.list;
      total = r.total;
      selected = {};
    } catch (_) {
      // the error was already shown
    }
    loading = false;
    notifyListeners();
  }

  /// The Filter button: back to page one.
  void filter() {
    page = 1;
    load();
  }

  void setPage(int p, int size) {
    page = size != pageSize ? 1 : p;
    pageSize = size;
    load();
  }

  void select(Set<int> s) {
    selected = s;
    notifyListeners();
  }

  /// Redraws after a row was changed in place.
  void touch() => notifyListeners();

  void set(String key, dynamic value) {
    query[key] = value;
    notifyListeners();
  }

  List<Row_> get selectedRows => [for (final i in selected) if (i < list.length) list[i]];
}

/// Lookups several pages share.
class Lookups {
  static Future<List<Row_>> _list(String path, [Map<String, dynamic>? q]) async {
    try {
      return PageResult.from(await api.get(path, params: {'page': 1, 'page_size': 9999, ...?q}, quiet: true)).list;
    } catch (_) {
      return [];
    }
  }

  static Future<List<Row_>> users() => _list('/user/list');
  static Future<List<Row_>> deviceGroups() => _list('/device_group/list');
  static Future<List<Row_>> userGroups() => _list('/group/list');
  static Future<List<Row_>> strategies() => _list('/strategy/list');

  /// Address book names; for another user when [userId] is set (admins).
  static Future<List<Row_>> collections({required bool mine, int? userId}) =>
      _list(mine ? '/my/address_book_collection/list' : '/address_book_collection/list', {if (userId != null) 'user_id': userId});

  static Future<List<Row_>> tags({required bool mine, int? userId, int? collectionId}) => _list(mine ? '/my/tag/list' : '/tag/list', {
        if (userId != null) 'user_id': userId,
        if (collectionId != null) 'collection_id': collectionId,
      });
}

String nameOf(List<Row_> items, dynamic id, {String field = 'name', String? fallback}) {
  for (final i in items) {
    if (i['id'] == id) return '${i[field] ?? ''}';
  }
  return fallback ?? (id == null ? '' : '$id');
}

/// Rows from endpoints that answer {list: [...]}, or a bare list.
List<Row_> rowsOf(dynamic d) {
  final raw = (d is Map ? d['list'] : d) as List? ?? const [];
  return [for (final r in raw) Map<String, dynamic>.from(r as Map)];
}
