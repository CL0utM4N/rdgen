import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/basic.dart';
import '../widgets/form.dart';

const _sections = [
  ('start', 'Signing in and your account', '''## 1. Signing in and your account

### Two-factor authentication

1. Go to **My Account → Profile** and click **Set up two-factor**.
2. Scan the QR code with Microsoft Authenticator, Google Authenticator or 1Password, then type the 6 digit code it shows.
3. Save the 10 **recovery codes** somewhere safe, such as your password manager. Each one signs you in once if you lose your phone.

Once it's on, signing in asks for a code. If you lose your phone, sign in with a recovery code, or ask an admin to use **Users → More → Reset two-factor**.

### Sessions

- The console signs you out after 30 minutes of inactivity, and after 12 hours regardless.
- The RustDesk sign-in lasts 30 days while you keep using it.
- Admins can change these under **Settings → Security**.

### One sign-in for the console and the client

The console is built into the RustDesk app. Signing in here also signs the app in, so your address book and the devices your role can see appear under **Client**, and your connections are logged against your name.

You'll get an email if your account signs in from an IP address it hasn't used before. If it wasn't you, change your password straight away.'''),
  ('devices', 'Finding and connecting to devices', '''## 2. Finding and connecting to devices

- **Client** in the menu is the RustDesk home page: this PC's ID and password, the connect box, and your recent, favourite and address book devices.
- **Devices → All Devices** lists every device you can see. A green dot means it's online now.
- **Connect** starts a remote session straight away. Under **More** you can **Transfer files**, **Edit** a device (alias, note, group, client policy), add it to an address book, or delete it.
- The gear icon above the table chooses which columns show. Scroll sideways to see them all.
- **My Devices** lists the devices signed in with your account.
- **Address books** are the saved device lists that show under **Client**. Shared address books can be given to other users.'''),
  ('deploy', 'Adding a customer\'s devices', '''## 3. Adding a customer's devices

Every device belongs to a **device group**, usually one per customer. Create the group first under **Devices → Device Groups → Add**. Then add devices using whichever option fits:

### A. Install and enrol script (quickest, works with Breeze RMM)

1. **One-off setup:** go to **Users & Access → API Keys → New API Key**. Name it "Breeze enrolment", choose a user who can manage your customer groups, pick **Only these → Manage devices**, and copy the key. It's only shown once, so store it as a secret variable in Breeze.
2. On **Device Groups**, click **Enrol** on the customer's group and leave **Install and enrol** selected.
3. Optionally pick a **client policy** and an **owner**, then copy the Windows (PowerShell) script.
4. Run it on the customer's PCs from Breeze, as SYSTEM. It downloads the standard RustDesk client, installs it silently, points it at our server and puts it in the group. It prints `Installed and enrolled <ID>`.

Running it again on a PC that already has RustDesk re-points it and re-enrols it, which also moves standard installs onto our server. For Linux, use the Linux tab. Macs need someone to open RustDesk once and allow screen recording first, and the macOS tab explains how.

**What's the API key for?** The last line of the script asks our server to put the device in the group. The key proves the request came from us, so nobody else can add their own machines to our customer groups. If a key leaks, revoke it on the API Keys page.

### B. A branded client from the Client Builder

**Support & Deployment → Client Builder** builds a ComTech-branded client with our server, and optionally a device group, built in. Download the installer, or email the download links to the customer. Devices that install it land in the group automatically, with that group's client policy, and no API key is needed.

- **Builds are instant.** With **Instant** on, the installers are made on our server from the **base client** for that platform, shown at the top of the page: Windows in seconds, Mac, Linux and Android in a minute or two. They carry the customer's device group and settings, and where the platform allows, name, icon and logo. Settings a platform can't change are greyed out with the reason.
- Mac installers come as a .zip: open it and drag the app to Applications. Linux gets .deb, .rpm, Arch and AppImage packages (Flatpak needs Instant off). Android gets an .apk for each processor type; phones with an older Comtech Android build need it removed and the new one installed once.
- **Update installed Windows and Linux clients** (under **Settings** on that card) lets Windows and Linux clients from instant builds update themselves once a newer base client is built.
- The base client is built on GitHub once per RustDesk release, taking about an hour. When RustDesk releases a new version, the page shows **Update available** and admins get an email. With automatic updates on, the new base builds by itself. **Rebuild** on an instant build remakes it from the newest base.
- If a new RustDesk version changes the code our changes rely on, the base build stops early and says so. Instant builds keep using the previous base until it's fixed.
- 32-bit Windows, and anything with Instant off, builds on GitHub, taking 20 to 40 minutes.

### C. A client that's already installed

In the Enrol dialog, choose **Enrol an installed client**. This script only puts the device in the group. If it's a Client Builder build, set **Client app name** to that build's name.

### Device approvals

When **Devices → Device Approvals → Require approval for new devices** is on, a device our server has never seen can't be reached until it's approved. New devices wait on that page. Click **Approve** (optionally choosing a group) or **Reject**. Devices added with the enrol scripts or `rustdesk --deploy` are approved automatically. Devices that already worked when approval was turned on keep working.'''),
  ('support', 'One-off support sessions', '''## 4. One-off support sessions

Use a support session for a customer who isn't set up yet, such as a new customer or someone calling for help.

1. **Support & Deployment → Support Sessions → New Support Session**. Choose which Client Builder build to send (you need at least one build), enter the customer's name and email, and choose the group their device should join (the default is "Customers").
2. The customer gets an email, from your own mailbox, with a link. Their page offers the right download for their computer.
3. They run the app and type the ID it shows into the page. You get an email saying they're ready, and the session shows **Connect**.
4. If they've opened the app, the page usually spots it and asks "Is this your device?" so they don't have to type the ID.
5. **With an instant Windows build as the support app**, each session's download is its own copy that knows the session: as soon as the customer opens it, the session is ready and you get the email. Nothing to type, and their device lands in the session's group.
6. Close the session when you're finished.'''),
  ('policies', 'Client policies', '''## 5. Client policies

**Devices → Client Policies** pushes RustDesk settings to devices within seconds. Examples are "click to accept only", "one-time passwords only", disabling file transfer, an IP whitelist, idle disconnect, or recording sessions automatically.

- Each device uses its own policy if it has one, otherwise its device group's, otherwise the **default** policy.
- Set a group's policy on **Device Groups → Edit**, and a single device's on **All Devices → More → Edit**.
- Anything left as **Not set** stays as each device has it.'''),
  ('users', 'Users, roles and API keys', '''## 6. Users, roles and API keys

- **Users**: add staff, reset passwords, and set each person's **Email** to their Microsoft 365 address. Emails to customers are sent from that mailbox.
- **User Groups & Roles**: each user group is a role. Tick what it can do (view or manage devices, client builder, logs, and so on). Tick **Limit to specific customers** to restrict it to certain device groups. **Full administrator** can do everything.
- **API Keys**: let other systems (the POS, Breeze scripts) use this server. A key acts as a user and can be limited further with **Only these**. Keys can be edited or revoked at any time. The API Keys page has a **How to use API keys** guide listing the endpoints each permission unlocks, with examples.
- **Login Sessions**: everyone who's currently signed in. Delete a session to sign someone out.
- **Single Sign-On**: optionally let staff sign in with a Microsoft or other identity provider account.'''),
  ('audit', 'Security and audit', '''## 7. Security and audit

- **Security Alerts**: warnings raised by devices themselves, such as repeated wrong passwords, or connections blocked by a whitelist.
- **Admin Activity**: every change anyone made in the console or with an API key, with who, when and from where. Passwords and keys are never recorded, and entries can't be deleted.
- **Connection Log**: who connected to what, and when. Sessions in progress show **Active** with a **Disconnect** button. Notes typed in the RustDesk app at the end of a session appear here.
- **Session Recordings**: recordings uploaded by devices whose policy has "Record incoming sessions automatically" on (Client Builder builds only). Play or download them here. Old ones are deleted after the retention period.
- **File Transfer Log**, **Login Log** and **Shared Links** show file transfers, sign-ins and shared web client links.
- **Usage report**: support time per customer, split by technician, for any dates. **Download CSV** for billing.

If your role is limited to some customers, these logs only show their devices.

### Alerts

- Each new security alert is emailed to the alert addresses in **Settings → Security**. Repeats from the same device are held back for 30 minutes.
- For devices that must stay up, such as a customer's server, edit the device in **All devices** and set **Offline alert** to a number of minutes. You'll get an email when it has been offline that long, and another when it's back.
- **Devices → Client versions** shows which RustDesk versions are in use and which devices are behind the latest release.'''),
  ('settings', 'Settings', '''## 8. Settings (admins)

- **Email Settings**: connect Microsoft 365 (tenant ID, client ID, secret) so the console can email from each person's mailbox. Use **Send test email** to check it.
- **System health**: the ID and relay servers, disk space, the website's certificate, last night's backup, the build runner, base clients, email and the data key, checked every 5 minutes. Anything that turns yellow or red, or recovers, is emailed to the alert recipients.
- **Security**: require two-factor (for admins or everyone), set session timeouts, the minimum password length, and new-IP sign-in alerts. Also sets who gets alert emails and which mailbox sends them, and how many nightly backups are kept.
- **Signed-in connections** (under Security): with **Enforce**, the server only connects technicians who are signed in to their account in the RustDesk app, and a technician limited to some customers can only reach those customers' devices. Start with **Log only** and check **Security Alerts** for anything that would have been refused.
- **Webhooks**: tell another system, such as the POS, when a customer is ready for support, a session starts or ends, a device needs approval, goes offline or raises an alarm. Use **Send test** to check the receiving end. The API guide lists every event.
- **Backups**: an encrypted copy of the database is made every night at 2 am. **Test restore** proves a backup opens. **Copy link** gives a download link that works for 24 hours, for keeping a copy off the server. You need the data key from Bitwarden to restore one.
- **Server Commands**: advanced commands sent to the RustDesk ID and relay servers.'''),
  ('faq', 'Troubleshooting', '''## 9. Troubleshooting

#### The enrol script says "Enrolment failed"
The reason follows the message. Usually the key is wrong or revoked, the group or policy name doesn't exist, or the key's user can't manage that group.

#### A new device never shows as online
Check **Device Approvals**. It may be waiting there.

#### I'm getting "No access"
Your role doesn't include that page or customer. Ask an admin to check **User Groups & Roles**. For an API key, check both the key's permissions and its user's role.

#### I've lost my phone
Sign in with a recovery code, or ask an admin to reset your two-factor, then set it up again on your Profile.

#### A customer didn't get the support email
Make sure your user has your Microsoft 365 email address set, and try **Settings → Email Settings → Send test email**.'''),
];

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  final keys = {for (final s in _sections) s.$1: GlobalKey()};
  String active = 'start';

  void _go(String id) {
    final ctx = keys[id]!.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    setState(() => active = id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const CtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Using ComTech IT Remote', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          SizedBox(height: 8),
          Muted(
            'The console runs our own RustDesk server, and it is built into the RustDesk app. It\'s where we keep track of customer devices, '
            'send out the support app, and control who can connect to what. Every section below matches a page in the menu on the left. '
            'You\'ll only see the pages your role allows.',
            size: 14,
          ),
        ]),
      ),
      for (final s in _sections) ...[
        const SizedBox(height: 16),
        CtCard(key: keys[s.$1], child: MarkdownView(s.$3)),
      ],
    ]);
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 900) return content;
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 220,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 8),
              child: Text('USER GUIDE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.9, color: c.sidebarSection)),
            ),
            for (final s in _sections)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _go(s.$1),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: active == s.$1 ? c.primary : c.border, width: 2)),
                    ),
                    child: Text(s.$2, style: TextStyle(fontSize: 13, color: active == s.$1 ? c.primary : c.text2)),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 24),
        Expanded(child: content),
      ]);
    });
  }
}
