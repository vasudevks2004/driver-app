import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'auth.dart';
import 'auth_screen.dart';

const primary = Color(0xFF5055F7);
const bg = Color(0xFFF7F8FC);
const ink = Color(0xFF202331);
const muted = Color(0xFF7B8190);
const border = Color(0xFFE8EAF0);
const green = Color(0xFF109869);
const apiUrl = String.fromEnvironment('API_URL', defaultValue: '');

void main() => runApp(const HireDApp());

class HireDApp extends StatelessWidget {
  const HireDApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HireD Driver', debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: primary),
      textTheme: GoogleFonts.interTextTheme(),
      appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: ink),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
      ),
    ),
    home: const DriverHome(),
  );
}

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});
  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  late final DriverAuth auth = DriverAuth(apiUrl);
  String? token;
  bool demo = false, online = false, busy = false, restoring = true;
  bool mustChangePassword = false;
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();
  bool passwordVisible = false;
  int page = 0;
  String? selectedId;
  String driverName = 'Alex Morgan';
  final password = TextEditingController();
  final expenseTitle = TextEditingController();
  final expenseAmount = TextEditingController();
  final otp = TextEditingController();
  final unavailable = <String>{};
  final docs = <String, bool>{
    'license': false, 'aadhaar': false, 'pan': false, 'pcc': false
  };
  List<Map<String, dynamic>> trips = [
    {
      'id': 'TRP-1028', 'company': 'Meridian Logistics',
      'pickup': 'Kakkanad, Kochi', 'drop': 'Edappally, Kochi',
      'date': 'Today · 10:30 AM', 'status': 'Assigned',
      'amount': 5000.0, 'driverSharePct': 30.0,
      'expenses': <Map<String, dynamic>>[], 'selfie': false
    },
    {
      'id': 'TRP-1025', 'company': 'Aster Corporate',
      'pickup': 'Infopark, Kochi', 'drop': 'Vyttila, Kochi',
      'date': 'Yesterday · 2:00 PM', 'status': 'Closed',
      'amount': 3000.0, 'driverSharePct': 30.0,
      'expenses': <Map<String, dynamic>>[], 'selfie': true
    }
  ];
  double balance = 900;
  List<Map<String, dynamic>> credits = [
    {'trip': 'TRP-1025', 'amount': 900.0, 'date': 'Yesterday'}
  ];

  String money(num amount) =>
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
          .format(amount);

  @override
  void initState() {
    super.initState();
    restoreSession();
  }

  @override
  void dispose() {
    auth.dispose(); password.dispose(); expenseTitle.dispose();
    expenseAmount.dispose(); otp.dispose(); newPassword.dispose(); confirmPassword.dispose();
    super.dispose();
  }

  void activateSession(DriverSession session) {
    setState(() {
      token = session.token;
      demo = false;
      mustChangePassword = session.mustChangePassword;
      driverName = (session.profile['name'] ?? 'Driver').toString();
      online = session.profile['online'] == true;
      trips = [];
      balance = 0;
      credits = [];
      unavailable
        ..clear()
        ..addAll((session.profile['unavailableDates'] as List? ?? []).map((x) => x.toString()));
      docs.updateAll((key, value) => session.profile['documents']?[key] == true);
      page = 0;
    });
  }

  Future<void> restoreSession() async {
    try {
      final saved = await auth.restore();
      if (!mounted) return;
      if (saved != null) {
        activateSession(saved);
        if (!saved.mustChangePassword) await refresh();
      }
    } catch (error) {
      // Connectivity issues are different from invalid credentials.
      // Keep the dashboard locked and let the driver retry verification.
      showError(error);
    } finally {
      if (mounted) setState(() => restoring = false);
    }
  }

  void showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString()))
    );
  }

  Future<void> runTask(Future<void> Function() task) async {
    if (busy) return;
    setState(() => busy = true);
    try { await task(); } catch (error) { showError(error); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> refresh() async {
    if (demo || token == null || mustChangePassword) return;
    try {
      final profile = await auth.request('/drivers/me') as Map;
      final assignments = await auth.request('/drivers/me/trips');
      final wallet = await auth.request('/drivers/me/wallet') as Map;
      if (!mounted) return;
      setState(() {
        driverName = (profile['name'] ?? 'Driver').toString();
        online = profile['online'] == true;
        unavailable
          ..clear()
          ..addAll((profile['unavailableDates'] as List? ?? []).map((x) => x.toString()));
        trips = List<Map<String, dynamic>>.from(
          assignments is List ? assignments : (assignments['trips'] ?? []));
        balance = (wallet['balance'] as num?)?.toDouble() ?? 0;
        credits = List<Map<String, dynamic>>.from(wallet['transactions'] ?? []);
      });
    } catch (error) { showError(error); }
  }

  Future<void> updatePassword() => runTask(() async {
    final updated = newPassword.text;
    if (updated != confirmPassword.text) throw StateError('Passwords do not match.');
    if (utf8.encode(updated).length < 12 || utf8.encode(updated).length > 72) {
      throw StateError('Use a password between 12 and 72 bytes.');
    }
    if (password.text.isEmpty) throw StateError('Enter your temporary password.');
    final session = await auth.changePassword(password.text, updated);
    password.clear();
    newPassword.clear();
    confirmPassword.clear();
    if (!mounted) return;
    activateSession(session);
    if (!session.mustChangePassword) await refresh();
  });

  Future<void> logout() => runTask(() async {
    final revoked = await auth.logout();
    if (!mounted) return;
    setState(() {
      token = null; demo = false; mustChangePassword = false;
      page = 0; driverName = 'Driver'; trips = []; credits = [];
      balance = 0; online = false; unavailable.clear();
      docs.updateAll((key, value) => false);
    });
    if (!revoked) showError('Signed out on this device. Server revocation could not be confirmed.');
  });

  Widget loginScreen() => DriverAuthScreen(
    auth: auth,
    onAuthenticated: (session) async {
      if (!mounted) return;
      activateSession(session);
      if (!session.mustChangePassword) await refresh();
    },
    onDemo: allowDemo ? () => setState(() {
      demo = true;
      token = null;
      page = 0;
      driverName = 'Alex Morgan';
    }) : null,
  );

  Widget changePasswordScreen() => Scaffold(
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(26), children: [
        Center(child: SvgPicture.asset('assets/hired-logo.svg',
          width: 140, height: 70)),
        const SizedBox(height: 24),
        heading('Secure your account', 'Change the temporary password supplied by HireD admin.'),
        TextField(controller: password, obscureText: true,
          decoration: const InputDecoration(labelText: 'Temporary password')),
        const SizedBox(height: 12),
        TextField(controller: newPassword, obscureText: true,
          decoration: const InputDecoration(labelText: 'New password (12+ characters)')),
        const SizedBox(height: 12),
        TextField(controller: confirmPassword, obscureText: true,
          decoration: const InputDecoration(labelText: 'Confirm new password')),
        const SizedBox(height: 18),
        button(busy ? 'Updating password…' : 'Update password', updatePassword),
        const SizedBox(height: 12),
        button('Sign out', logout, light: true),
      ]),
    ))),
  );

  Widget panel(Widget child, {Color color = Colors.white}) => Container(
    width: double.infinity, margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color == primary ? primary : border)),
    child: child,
  );

  Widget heading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800,
        fontSize: 25, color: ink)),
      const SizedBox(height: 6),
      Text(subtitle, style: const TextStyle(color: muted, fontSize: 12)),
    ]),
  );

  Widget section(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Text(text, style: const TextStyle(color: ink,
      fontSize: 16, fontWeight: FontWeight.w800)),
  );

  Widget button(String label, VoidCallback onPressed, {bool light = false}) =>
    SizedBox(width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: light ? const Color(0xFFEEEFFF) : primary,
          foregroundColor: light ? primary : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );

  Widget tripCard(Map<String, dynamic> trip) => InkWell(
    onTap: () => setState(() {
      selectedId = trip['id'].toString(); page = 4;
    }),
    child: panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('#${trip['id']}', style: const TextStyle(fontWeight: FontWeight.w800)),
        Text('${trip['status']}', style: TextStyle(
          color: trip['status'] == 'Closed' ? green : primary,
          fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 10),
      Text('${trip['company'] ?? trip['companyName'] ?? 'Partner'} · ${trip['date'] ?? trip['scheduledAt'] ?? ''}',
        style: const TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 13),
      Text('●  ${trip['pickup'] ?? trip['pickupAddress'] ?? 'Pickup'}'),
      const SizedBox(height: 8),
      Text('●  ${trip['drop'] ?? trip['dropAddress'] ?? 'Destination'}',
        style: const TextStyle(color: muted)),
      const SizedBox(height: 14),
      const Text('View assignment →', style: TextStyle(
        color: primary, fontWeight: FontWeight.w800)),
    ])),
  );

  Widget dashboard() {
    final active = trips.where((trip) => trip['status'] != 'Closed').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      heading('Hello, ${driverName.split(' ').first} 👋',
        'Your driver duties at a glance'),
      panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your availability', style: TextStyle(color: Colors.white70)),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(online ? 'You’re online' : 'You’re offline', style:
              const TextStyle(color: Colors.white, fontSize: 23,
                fontWeight: FontWeight.w800)),
            const Text('Ready for driver assignments',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          ])),
          Switch(value: online, activeThumbColor: Colors.white,
            onChanged: (value) => runTask(() async {
              if (!demo) await auth.request('/drivers/me/availability',
                method: 'PATCH', body: {'online': value,
                  'unavailableDates': unavailable.toList()});
              setState(() => online = value);
            })),
        ]),
      ]), color: primary),
      Row(children: [
        Expanded(child: panel(Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [const Text('Active duties', style: TextStyle(color: muted)),
            const SizedBox(height: 8), Text('${active.length}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 26))]))),
        const SizedBox(width: 10),
        Expanded(child: panel(Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [const Text('Wallet balance', style: TextStyle(color: muted)),
            const SizedBox(height: 8), Text(money(balance),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22))]))),
      ]),
      section('Assigned driver duties'),
      if (active.isEmpty) panel(const Text('No assignments yet.')),
      ...active.take(3).map(tripCard),
      button('View all assignments', () => setState(() => page = 1), light: true),
    ]);
  }

  Widget assignments() {
    final active = trips.where((t) => t['status'] != 'Closed');
    final previous = trips.where((t) => t['status'] == 'Closed');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      heading('My assignments', 'HireD provides drivers, not vehicles'),
      section('Assigned & ongoing'),
      if (active.isEmpty) panel(const Text('No current assignments')),
      ...active.map(tripCard),
      section('Completed duties'),
      if (previous.isEmpty) panel(const Text('No previous completed duties')),
      ...previous.map(tripCard),
    ]);
  }

  Widget detail() {
    final matches = trips.where((t) => t['id'].toString() == selectedId).toList();
    if (matches.isEmpty) return const Text('Assignment not available.');
    final t = matches.first;
    final status = t['status']?.toString() ?? 'Unknown';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      heading('Duty #${t['id']}', 'Assigned driving duty'),
      panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(status, style: const TextStyle(color: primary,
          fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        const Text('PICKUP', style: TextStyle(color: muted, fontSize: 11)),
        Text('${t['pickup'] ?? t['pickupAddress'] ?? '—'}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 13),
        const Text('DESTINATION', style: TextStyle(color: muted, fontSize: 11)),
        Text('${t['drop'] ?? t['dropAddress'] ?? '—'}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 13),
        Text('${t['company'] ?? t['companyName'] ?? 'Partner'} · ${t['date'] ?? t['scheduledAt'] ?? ''}',
          style: const TextStyle(color: muted)),
        const SizedBox(height: 10),
        const Text('The partner/customer provides the vehicle.',
          style: TextStyle(fontSize: 12, color: muted)),
      ])),
      if (status == 'Assigned')
        button('Start driver duty', () => runTask(() async {
          if (!demo) await auth.request('/trips/${t['id']}/start', method: 'POST');
          setState(() => t['status'] = 'Ongoing');
        })),
      if (status == 'Ongoing') ...[
        section('Identity selfie'),
        panel(Column(children: [
          Text(t['selfie'] == true ? 'Selfie captured' : 'Capture a selfie for this duty',
            style: const TextStyle(color: muted)),
          const SizedBox(height: 12),
          button('Take selfie', () => runTask(() async {
            final photo = await ImagePicker().pickImage(
              source: ImageSource.camera, imageQuality: 70);
            if (photo == null) return;
            if (!demo) await auth.upload('/trips/${t['id']}/selfie', photo.path);
            setState(() => t['selfie'] = true);
          }), light: true),
        ])),
        section('Trip expenses'),
        panel(Column(children: [
          ...List<Map<String, dynamic>>.from(t['expenses'] ?? []).map((e) =>
            ListTile(dense: true, title: Text('${e['description']}'),
              trailing: Text(money((e['amount'] as num?) ?? 0)))),
          TextField(controller: expenseTitle,
            decoration: const InputDecoration(labelText: 'Description (toll, parking…)')),
          const SizedBox(height: 10),
          TextField(controller: expenseAmount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount in ₹')),
          const SizedBox(height: 12),
          button('Log expense', () => runTask(() async {
            final amount = double.tryParse(expenseAmount.text);
            final title = expenseTitle.text.trim();
            if (title.isEmpty || amount == null || amount < 0) {
              throw StateError('Enter a description and non-negative amount');
            }
            if (!demo) await auth.request('/trips/${t['id']}/expenses',
              method: 'POST', body: {'description': title, 'amount': amount});
            setState(() {
              (t['expenses'] as List).add({'description': title, 'amount': amount});
            });
            expenseTitle.clear(); expenseAmount.clear();
          })),
        ])),
        section('Close duty with OTP'),
        panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Get the OTP from the B2B partner. Record expenses first; '
            'if none, log “No expenses” with ₹0.',
            style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(controller: otp, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Numeric OTP')),
          const SizedBox(height: 12),
          button('Verify OTP & close duty', () => runTask(() async {
            if ((t['expenses'] as List).isEmpty) {
              throw StateError('Log expenses before closing, including ₹0 if none');
            }
            if (!RegExp(r'^\d{4,8}$').hasMatch(otp.text)) {
              throw StateError('Enter a valid numeric OTP');
            }
            if (demo) {
              if (otp.text != '4826') throw StateError('Wrong OTP; demo code is 4826');
              final credit = ((t['amount'] as num) *
                  ((t['driverSharePct'] as num) / 100)).toDouble();
              setState(() {
                t['status'] = 'Closed'; balance += credit;
                credits.insert(0, {'trip': t['id'], 'amount': credit, 'date': 'Today'});
                page = 2;
              });
            } else {
              await auth.request('/trips/${t['id']}/close',
                method: 'POST', body: {'otp': otp.text});
              await refresh();
              setState(() => page = 2);
            }
            otp.clear();
          })),
        ])),
      ],
      if (status == 'Closed') panel(const Text(
        '✓ Duty completed. Earnings are shown in your wallet.',
        style: TextStyle(color: green, fontWeight: FontWeight.w700))),
      button('Back to assignments', () => setState(() => page = 1), light: true),
    ]);
  }

  Widget wallet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    heading('My wallet', 'Driver earnings from completed duties'),
    panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Available balance', style: TextStyle(color: Colors.white70)),
      const SizedBox(height: 10),
      Text(money(balance), style: const TextStyle(
        color: Colors.white, fontSize: 35, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      const Text('Display only · No in-app withdrawals',
        style: TextStyle(color: Colors.white70, fontSize: 12)),
    ]), color: primary),
    section('Per-duty credits'),
    if (credits.isEmpty) panel(const Text('No credits yet')),
    ...credits.map((c) => panel(Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Duty #${c['trip'] ?? c['tripId'] ?? c['trip_id'] ?? '—'}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('${c['date'] ?? c['createdAt'] ?? ''}',
          style: const TextStyle(color: muted, fontSize: 12)),
      ]),
      Text('+${money((c['amount'] as num?) ?? 0)}',
        style: const TextStyle(color: green, fontWeight: FontWeight.w800)),
    ]))),
  ]);

  Widget profile() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    heading('My profile', 'Availability and onboarding documents'),
    panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(driverName, style: const TextStyle(
        fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      Text(demo ? 'DRV-002 · Demo account' : 'Authenticated driver',
        style: const TextStyle(color: muted)),
    ])),
    section('Availability calendar'),
    panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Tap a date to mark it available or unavailable.',
        style: TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: List.generate(14, (i) {
        final date = DateTime.now().add(Duration(days: i));
        final key = DateFormat('yyyy-MM-dd').format(date);
        final blocked = unavailable.contains(key);
        return InkWell(onTap: () => runTask(() async {
          final next = {...unavailable};
          if (blocked) { next.remove(key); } else { next.add(key); }
          if (!demo) await auth.request('/drivers/me/availability',
            method: 'PATCH', body: {'online': online, 'unavailableDates': next.toList()});
          setState(() { unavailable..clear()..addAll(next); });
        }), child: Container(width: 64, padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: blocked ? const Color(0xFFFFE9EC) : const Color(0xFFEEEFFF),
            borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text(DateFormat('EEE').format(date),
              style: const TextStyle(color: muted, fontSize: 11)),
            Text('${date.day}', style: TextStyle(fontSize: 17,
              fontWeight: FontWeight.w800,
              color: blocked ? Colors.red : primary)),
          ])));
      })),
    ])),
    section('Driver documents'),
    ...{
      'license': 'Driving License',
      'aadhaar': 'Aadhaar Card',
      'pan': 'PAN Card',
      'pcc': 'Police Clearance Certificate (PCC)',
    }.entries.map((entry) => panel(Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(docs[entry.key] == true ? 'Uploaded' : 'Not uploaded',
            style: const TextStyle(fontSize: 12, color: muted)),
        ])),
      IconButton(onPressed: () => runTask(() async {
        final chosen = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf']);
        final path = chosen?.files.single.path;
        if (path == null) return;
        if (!demo) await auth.upload('/drivers/me/documents/${entry.key}', path);
        setState(() => docs[entry.key] = true);
      }), icon: const Icon(Icons.upload_file, color: primary)),
    ]))),
    button(demo ? 'Exit demo' : 'Sign out', demo ? () => setState(() { demo = false; page = 0; }) : logout,
      light: true),
  ]);

  @override
  Widget build(BuildContext context) {
    if (restoring) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!demo && token == null) return loginScreen();
    if (!demo && mustChangePassword) return changePasswordScreen();
    return Scaffold(
    appBar: AppBar(
      title: Row(children: [
        SvgPicture.asset('assets/hired-logo.svg', width: 92, height: 42,
          fit: BoxFit.contain),
        const Spacer(),
        if (demo) const Text('DEMO MODE', style: TextStyle(
          fontSize: 10, color: primary, fontWeight: FontWeight.w800)),
        IconButton(onPressed: () => runTask(refresh),
          icon: const Icon(Icons.refresh, color: primary)),
      ]),
    ),
    body: Column(children: [
      if (busy) const LinearProgressIndicator(color: primary, minHeight: 2),
      Expanded(child: ListView(padding: const EdgeInsets.all(20), children: [
        if (page == 0) dashboard(),
        if (page == 1) assignments(),
        if (page == 2) wallet(),
        if (page == 3) profile(),
        if (page == 4) detail(),
      ])),
      if (page != 4) NavigationBar(
        selectedIndex: page,
        onDestinationSelected: (i) => setState(() => page = i),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFEEEFFF),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.route_outlined), label: 'Duties'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Wallet'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    ]),
  );
  }
}
