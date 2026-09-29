import 'package:flutter/material.dart';

import 'console.dart';
import 'pages/address_books.dart';
import 'pages/audit.dart';
import 'pages/client_build.dart';
import 'pages/dashboard.dart';
import 'pages/devices.dart';
import 'pages/help.dart';
import 'pages/login.dart';
import 'pages/my.dart';
import 'pages/peers.dart';
import 'pages/server_cmd.dart';
import 'pages/settings.dart';
import 'pages/support.dart';
import 'pages/users.dart';

/// A page. [name] matches the web console's route names, which the server
/// uses to say which pages a role may open.
class RouteDef {
  final String name;
  final String title;
  final IconData icon;
  final WidgetBuilder? builder;
  final bool hide;
  const RouteDef(this.name, this.title, this.icon, this.builder, {this.hide = false});
}

class SectionDef {
  final String name;
  final String title;
  final List<RouteDef> children;

  /// Always shown as a single item, like Dashboard and Client.
  final bool single;
  const SectionDef(this.name, this.title, this.children, {this.single = false});
}

final sections = <SectionDef>[
  SectionDef('DashboardRoot', 'Dashboard', [RouteDef('Dashboard', 'Dashboard', Icons.speed_outlined, (_) => const DashboardPage())], single: true),
  const SectionDef('ClientRoot', 'Client', [RouteDef('Client', 'Client', Icons.screen_share_outlined, null)], single: true),
  SectionDef('My', 'MenuMyAccount', [
    RouteDef('MyInfo', 'MenuMyProfile', Icons.person_outline, (_) => const MyInfoPage()),
    RouteDef('MyPeer', 'MenuMyDevices', Icons.desktop_windows_outlined, (_) => const MyPeerPage()),
    RouteDef('MyAddressBookList', 'MenuMyAddressBook', Icons.menu_book_outlined, (_) => const AddressBookPage(mine: true)),
    RouteDef('MyAddressBookCollection', 'MenuMyAddressBookNames', Icons.collections_bookmark_outlined, (_) => const CollectionPage(mine: true)),
    RouteDef('MyTagList', 'MenuMyTags', Icons.bookmark_border, (_) => const TagPage(mine: true)),
    RouteDef('MyShareRecordList', 'MenuMySharedLinks', Icons.share_outlined, (_) => const ShareRecordPage(mine: true)),
    RouteDef('Help', 'UserGuide', Icons.help_outline, (_) => const HelpPage(), hide: true),
    RouteDef('MyLoginLog', 'MenuMyLoginHistory', Icons.list_alt, (_) => const LoginLogPage(mine: true)),
  ]),
  SectionDef('DevicesSection', 'MenuDevices', [
    RouteDef('Peer', 'MenuAllDevices', Icons.desktop_windows_outlined, (_) => const PeerPage()),
    RouteDef('DeviceGroup', 'MenuDeviceGroups', Icons.folder_copy_outlined, (_) => const DeviceGroupPage()),
    RouteDef('DeviceApproval', 'DeviceApprovals', Icons.check_circle_outline, (_) => const ApprovalsPage()),
    RouteDef('Strategy', 'ClientPolicies', Icons.tune, (_) => const StrategyPage()),
    RouteDef('VersionReport', 'VersionReport', Icons.pie_chart_outline, (_) => const VersionReportPage()),
  ]),
  SectionDef('SupportSection', 'MenuSupport', [
    RouteDef('SupportSession', 'SupportSessions', Icons.headset_mic_outlined, (_) => const SupportPage()),
    RouteDef('ClientBuild', 'ClientBuilder', Icons.inventory_2_outlined, (_) => const ClientBuildPage()),
  ]),
  SectionDef('AddressBooksSection', 'MenuAddressBooks', [
    RouteDef('UserAddressBook', 'MenuAllAddressBooks', Icons.menu_book_outlined, (_) => const AddressBookPage(mine: false)),
    RouteDef('UserAddressBookName', 'MenuAddressBookNames', Icons.collections_bookmark_outlined, (_) => const CollectionPage(mine: false)),
    RouteDef('UserTag', 'MenuAllTags', Icons.bookmark_border, (_) => const TagPage(mine: false)),
  ]),
  SectionDef('User', 'MenuUsersAccess', [
    RouteDef('UserList', 'MenuUsers', Icons.person_outline, (_) => const UserListPage()),
    RouteDef('UserAdd', 'UserAdd', Icons.person_add_outlined, (_) => const UserEditPage(), hide: true),
    RouteDef('UserEdit', 'UserEdit', Icons.edit_outlined, (_) => const UserEditPage(), hide: true),
    RouteDef('UserGroup', 'GroupManage', Icons.groups_outlined, (_) => const UserGroupPage()),
    RouteDef('ApiKeys', 'ApiKeys', Icons.vpn_key_outlined, (_) => const ApiKeysPage()),
    RouteDef('UserToken', 'MenuLoginSessions', Icons.confirmation_number_outlined, (_) => const UserTokenPage()),
    RouteDef('Oauth', 'MenuSingleSignOn', Icons.link, (_) => const OauthPage()),
  ]),
  SectionDef('AuditSection', 'MenuSecurityAudit', [
    RouteDef('AuditAlarm', 'SecurityAlerts', Icons.warning_amber_outlined, (_) => const AlarmPage()),
    RouteDef('AdminLog', 'AdminActivity', Icons.description_outlined, (_) => const AdminLogPage()),
    RouteDef('AuditConn', 'MenuConnectionLog', Icons.receipt_long_outlined, (_) => const ConnLogPage()),
    RouteDef('UsageReport', 'UsageReport', Icons.bar_chart, (_) => const UsageReportPage()),
    RouteDef('Recording', 'SessionRecordings', Icons.videocam_outlined, (_) => const RecordingsPage()),
    RouteDef('AuditFile', 'MenuFileTransferLog', Icons.folder_copy_outlined, (_) => const FileLogPage()),
    RouteDef('LoginLog', 'MenuLoginLog', Icons.list_alt, (_) => const LoginLogPage(mine: false)),
    RouteDef('ShareRecord', 'MenuSharedLinks', Icons.share_outlined, (_) => const ShareRecordPage(mine: false)),
  ]),
  SectionDef('SettingsSection', 'MenuSettings', [
    RouteDef('MailSettings', 'EmailSettings', Icons.mail_outline, (_) => const MailPage()),
    RouteDef('SecuritySettings', 'SecuritySettings', Icons.lock_outline, (_) => const SecurityPage()),
    RouteDef('SystemHealth', 'SystemHealth', Icons.monitor_heart_outlined, (_) => const HealthPage()),
    RouteDef('Webhooks', 'Webhooks', Icons.webhook, (_) => const WebhooksPage()),
    RouteDef('Backups', 'Backups', Icons.backup_outlined, (_) => const BackupsPage()),
    RouteDef('ServerCmd', 'ServerCmd', Icons.build_outlined, (_) => const ServerCmdPage()),
  ]),
];

const _login = RouteDef('Login', 'Login', Icons.login, _loginPage);
Widget _loginPage(BuildContext _) => const LoginPage();

RouteDef? routeByName(String name) {
  if (name == 'Login') return _login;
  for (final s in sections) {
    for (final r in s.children) {
      if (r.name == name) return r;
    }
  }
  return null;
}

/// The sections and pages this user's role can open.
List<SectionDef> visibleSections() {
  final con = Console.I;
  final out = <SectionDef>[];
  for (final s in sections) {
    if (s.name == 'ClientRoot') {
      out.add(s);
      continue;
    }
    // hidden pages (help, add, edit) come with their section
    final kids = s.children.where((r) => r.hide || con.canRoute(r.name)).toList();
    if (kids.any((r) => !r.hide)) out.add(SectionDef(s.name, s.title, kids, single: s.single));
  }
  return out;
}
