import 'package:flutter/material.dart';

import 'console.dart';
import 'i18n.dart';
import 'pages/login.dart';
import 'pages/my.dart' show showChangePassword;
import 'routes.dart';
import 'theme.dart';
import 'widgets/basic.dart';
import 'widgets/dialog.dart';

const clientRoute = 'Client';

/// The console: sidebar, header and the current page, laid out like the web
/// console. The RustDesk home page sits under Client.
class ConsoleShell extends StatefulWidget {
  const ConsoleShell({super.key});

  @override
  State<ConsoleShell> createState() => _ConsoleShellState();
}

class _ConsoleShellState extends State<ConsoleShell> {
  final scroll = ScrollController();
  Widget? clientPage;

  @override
  void initState() {
    super.initState();
    Console.I.addListener(_changed);
    if (!Console.I.ready) Console.I.restore();
  }

  @override
  void dispose() {
    Console.I.removeListener(_changed);
    scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final con = Console.I;
    // the client page keeps the app's own theme; its widgets rely on it
    final outer = Theme.of(context);
    return Theme(
      data: consoleTheme(con.dark),
      child: Builder(builder: (context) {
        final c = context.ct;
        clientPage ??= con.host.buildClientPage(context);
        final onClient = con.route == clientRoute || (!con.signedIn && con.route == clientRoute);
        Widget content;
        if (!con.ready) {
          content = const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)));
        } else if (!con.signedIn && !onClient) {
          content = const LoginPage();
        } else {
          final def = routeByName(con.route);
          content = Scrollbar(
            controller: scroll,
            child: SingleChildScrollView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
              child: KeyedSubtree(
                key: ValueKey(con.nav),
                child: def?.builder?.call(context) ?? Muted(T('NoAccess')),
              ),
            ),
          );
        }
        return Material(
          color: c.bg,
          child: DefaultTextStyle(
            style: TextStyle(fontSize: 14, color: c.text, fontFamily: DefaultTextStyle.of(context).style.fontFamily),
            child: Stack(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const _Sidebar(),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (con.signedIn || onClient) const _Header(),
                    Expanded(
                      child: Stack(children: [
                        // the client page stays alive while other pages are shown
                        if (clientPage != null)
                          Offstage(
                            offstage: !onClient,
                            child: TickerMode(
                              enabled: onClient,
                              child: Theme(
                                data: outer,
                                child: DefaultTextStyle(style: outer.textTheme.bodyMedium ?? const TextStyle(), child: clientPage!),
                              ),
                            ),
                          ),
                        if (!onClient) Positioned.fill(child: content),
                        if (onClient && clientPage == null) Center(child: Muted(T('ClientNotAvailable'))),
                      ]),
                    ),
                  ]),
                ),
              ]),
              const ToastLayer(),
            ]),
          ),
        );
      }),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final con = Console.I;
    final collapsed = con.sideCollapsed;
    final items = <Widget>[];
    if (!con.signedIn) {
      items.add(_Item(name: clientRoute, title: T('Client'), icon: Icons.screen_share_outlined, collapsed: collapsed));
      items.add(_Item(name: 'Login', title: T('Login'), icon: Icons.login, collapsed: collapsed));
    } else {
      for (final s in visibleSections()) {
        final kids = s.children.where((r) => !r.hide).toList();
        if (s.single || kids.length == 1) {
          final r = kids.first;
          items.add(_Item(name: r.name, title: T(r.title), icon: r.icon, collapsed: collapsed));
        } else if (collapsed) {
          for (final r in kids) {
            items.add(_Item(name: r.name, title: T(r.title), icon: r.icon, collapsed: true));
          }
        } else {
          items.add(_Section(title: T(s.title), children: [
            for (final r in kids) _Item(name: r.name, title: T(r.title), icon: r.icon, collapsed: false, indent: true),
          ]));
        }
      }
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: collapsed ? 72 : 248,
      decoration: BoxDecoration(color: c.sidebar, border: Border(right: BorderSide(color: c.border))),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: collapsed ? 72 : 248,
          maxWidth: collapsed ? 72 : 248,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 64,
              padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 18),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
              child: Row(mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: c.borderStrong),
                    image: const DecorationImage(image: AssetImage('packages/comtech_console/assets/comtech-logo.jpg'), fit: BoxFit.cover),
                  ),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('ComTech IT', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text, height: 1.2)),
                    Text('Remote Support', style: TextStyle(fontSize: 12, color: c.muted)),
                  ]),
                ],
              ]),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: collapsed ? 8 : 12, vertical: 12),
                children: items,
              ),
            ),
            if (!collapsed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
                child: Text(con.title, style: TextStyle(fontSize: 11, color: c.sidebarSection)),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Section extends StatefulWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  bool open = true;
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        child: GestureDetector(
          onTap: () => setState(() => open = !open),
          child: Container(
            height: 34,
            margin: const EdgeInsets.only(top: 14, bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: Colors.transparent,
            child: Row(children: [
              Expanded(
                child: Text(widget.title.toUpperCase(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.9, color: hover ? c.sidebarText : c.sidebarSection)),
              ),
              AnimatedRotation(
                turns: open ? 0 : 0.5,
                duration: const Duration(milliseconds: 150),
                child: Icon(Icons.keyboard_arrow_up, size: 14, color: c.sidebarSection),
              ),
            ]),
          ),
        ),
      ),
      if (open) ...widget.children,
    ]);
  }
}

class _Item extends StatefulWidget {
  final String name;
  final String title;
  final IconData icon;
  final bool collapsed;
  final bool indent;
  const _Item({required this.name, required this.title, required this.icon, required this.collapsed, this.indent = false});

  @override
  State<_Item> createState() => _ItemState();
}

class _ItemState extends State<_Item> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final active = Console.I.route == widget.name;
    Widget item = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: () => Console.I.go(widget.name),
        child: Container(
          height: 40,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: EdgeInsets.only(left: widget.collapsed ? 0 : (widget.indent ? 16 : 12)),
          alignment: widget.collapsed ? Alignment.center : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: active ? c.primary : (hover ? c.surfaceHover : Colors.transparent),
            borderRadius: BorderRadius.circular(ctRadiusSm),
          ),
          child: Row(mainAxisSize: widget.collapsed ? MainAxisSize.min : MainAxisSize.max, children: [
            Icon(widget.icon, size: 18, color: active ? Colors.white : c.muted),
            if (!widget.collapsed) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: active ? Colors.white : c.sidebarText)),
              ),
            ],
          ]),
        ),
      ),
    );
    if (widget.collapsed) item = Tooltip(message: widget.title, preferBelow: false, child: item);
    return item;
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final con = Console.I;
    final def = routeByName(con.route);
    final initials = (con.displayName.isEmpty ? '?' : con.displayName).characters.take(2).toString().toUpperCase();
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(color: c.bg, border: Border(bottom: BorderSide(color: c.border))),
      child: Row(children: [
        CtIconButton(con.sideCollapsed ? Icons.menu_open : Icons.menu, tooltip: T('Menu'), onPressed: con.toggleSide),
        const SizedBox(width: 14),
        Expanded(
          child: Text(con.route == clientRoute ? T('Client') : (def == null ? '' : T(def.title)),
              overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.text)),
        ),
        Tooltip(
          message: con.dark ? T('LightMode') : T('DarkMode'),
          child: CtSwitch(
            value: con.dark,
            offColor: c.borderStrong,
            onChanged: (_) => con.toggleDark(),
            activeText: '☾',
            inactiveText: '☀',
          ),
        ),
        const SizedBox(width: 16),
        CtIconButton(Icons.settings_outlined, tooltip: T('ClientSettings'), onPressed: con.host.openClientSettings, size: 32),
        if (con.signedIn) ...[
          const SizedBox(width: 16),
          PopupMenuButton<String>(
            tooltip: '',
            offset: const Offset(0, 44),
            onSelected: (v) async {
              switch (v) {
                case 'help':
                  con.go('Help');
                case 'profile':
                  con.go('MyInfo');
                case 'password':
                  showChangePassword(context);
                case 'logout':
                  con.signOut();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'help', child: Text(T('UserGuide'))),
              PopupMenuItem(value: 'profile', child: Text(T('ProfileAndTwoFactor'))),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'password', child: Text(T('ChangePassword'))),
              PopupMenuItem(value: 'logout', child: Text(T('Logout'))),
            ],
            child: Row(children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 10, right: 6),
                child: Text(con.displayName, style: TextStyle(fontWeight: FontWeight.w500, color: c.text)),
              ),
              Icon(Icons.keyboard_arrow_down, size: 16, color: c.text2),
            ]),
          ),
        ] else ...[
          const SizedBox(width: 16),
          CtButton(T('Login'), tone: Tone.primary, onPressed: () => con.go('Login')),
        ],
      ]),
    );
  }
}
