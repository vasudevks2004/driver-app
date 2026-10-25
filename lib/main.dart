import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'auth.dart';
import 'auth_screen.dart';
import 'brand.dart';
import 'design.dart';
import 'driver_widgets.dart';
import 'onboarding.dart';

const primary = HireDStyle.primary;
const bg = HireDStyle.canvas;
const ink = HireDStyle.ink;
const muted = HireDStyle.muted;
const border = HireDStyle.line;
const green = HireDStyle.success;
const apiUrl = String.fromEnvironment('API_URL', defaultValue: '');

void main() => runApp(const HireDApp());

class HireDApp extends StatelessWidget {
  const HireDApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HireD Driver',
    debugShowCheckedModeBanner: false,
    theme: HireDStyle.theme(),
    home: const DriverHome(),
  );
}

class DriverHome extends StatefulWidget {
  const DriverHome({super.key, this.authOverride, this.onboardingOverride});
  final DriverAuth? authOverride;
  final DriverOnboarding? onboardingOverride;
  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  late final DriverAuth auth = widget.authOverride ?? DriverAuth(apiUrl);
  String? token;
  Uint8List? _avatar;
  bool demo = false, online = false, busy = false, restoring = true;
  bool mustChangePassword = false;
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();
  bool passwordVisible = false;
  int page = 0;
  bool _showCompleted = false;
  String? selectedId;
  String driverName = 'Alex Morgan';
  final password = TextEditingController();
  final expenseTitle = TextEditingController();
  final expenseAmount = TextEditingController();
  final otp = TextEditingController();
  final unavailable = <String>{};
  final docs = <String, bool>{
    'license': false,
    'aadhaar': false,
    'pan': false,
    'pcc': false,
  };
  List<Map<String, dynamic>> trips = [
    {
      'id': 'TRP-1028',
      'company': 'Meridian Logistics',
      'pickup': 'Kakkanad, Kochi',
      'drop': 'Edappally, Kochi',
      'date': 'Today · 10:30 AM',
      'status': 'Assigned',
      'amount': 5000.0,
      'driverSharePct': 30.0,
      'expenses': <Map<String, dynamic>>[],
      'selfie': false,
    },
    {
      'id': 'TRP-1025',
      'company': 'Aster Corporate',
      'pickup': 'Infopark, Kochi',
      'drop': 'Vyttila, Kochi',
      'date': 'Yesterday · 2:00 PM',
      'status': 'Closed',
      'amount': 3000.0,
      'driverSharePct': 30.0,
      'expenses': <Map<String, dynamic>>[],
      'selfie': true,
    },
  ];
  double balance = 900;
  List<Map<String, dynamic>> credits = [
    {'trip': 'TRP-1025', 'amount': 900.0, 'date': 'Yesterday'},
  ];

  String money(num amount) => NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  ).format(amount);

  @override
  void initState() {
    super.initState();
    restoreSession();
  }

  @override
  void dispose() {
    auth.dispose();
    password.dispose();
    expenseTitle.dispose();
    expenseAmount.dispose();
    otp.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  void activateSession(DriverSession session) {
    setState(() {
      token = session.token;
      _avatar = null;
      demo = false;
      mustChangePassword = session.mustChangePassword;
      driverName = (session.profile['name'] ?? 'Driver').toString();
      online = session.profile['online'] == true;
      trips = [];
      balance = 0;
      credits = [];
      unavailable
        ..clear()
        ..addAll(
          (session.profile['unavailableDates'] as List? ?? []).map(
            (x) => x.toString(),
          ),
        );
      docs.updateAll(
        (key, value) => session.profile['documents']?[key] == true,
      );
      page = 0;
    });
  }

  Future<void> loadAvatar(DriverSession session) async {
    final service =
        widget.onboardingOverride ?? DriverOnboarding(auth.identity.config);
    try {
      final avatar = await service.avatar(session.token);
      if (mounted && token == session.token) setState(() => _avatar = avatar);
    } catch (_) {
      // A missing profile photo must not block driver access.
    } finally {
      if (widget.onboardingOverride == null) service.dispose();
    }
  }

  Future<void> restoreSession() async {
    try {
      final saved = await auth.restore();
      if (!mounted) return;
      if (saved != null) {
        activateSession(saved);
        unawaited(loadAvatar(saved));
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  Future<void> runTask(Future<void> Function() task) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await task();
    } catch (error) {
      showError(error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
          ..addAll(
            (profile['unavailableDates'] as List? ?? []).map(
              (x) => x.toString(),
            ),
          );
        trips = List<Map<String, dynamic>>.from(
          assignments is List ? assignments : (assignments['trips'] ?? []),
        );
        balance = (wallet['balance'] as num?)?.toDouble() ?? 0;
        credits = List<Map<String, dynamic>>.from(wallet['transactions'] ?? []);
      });
    } catch (error) {
      showError(error);
    }
  }

  Future<void> updatePassword() => runTask(() async {
    final updated = newPassword.text;
    if (updated != confirmPassword.text)
      throw StateError('Passwords do not match.');
    if (utf8.encode(updated).length < 12 || utf8.encode(updated).length > 72) {
      throw StateError('Use a password between 12 and 72 bytes.');
    }
    if (password.text.isEmpty)
      throw StateError('Enter your temporary password.');
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
      token = null;
      demo = false;
      mustChangePassword = false;
      page = 0;
      driverName = 'Driver';
      trips = [];
      credits = [];
      balance = 0;
      online = false;
      unavailable.clear();
      docs.updateAll((key, value) => false);
    });
    if (!revoked)
      showError(
        'Signed out on this device. Server revocation could not be confirmed.',
      );
  });

  Widget loginScreen() => DriverAuthScreen(
    auth: auth,
    onboarding: widget.onboardingOverride,
    onAuthenticated: (session) async {
      if (!mounted) return;
      activateSession(session);
      unawaited(loadAvatar(session));
      if (!session.mustChangePassword) await refresh();
    },
    onDemo: allowDemo
        ? () => setState(() {
            demo = true;
            token = null;
            page = 0;
            driverName = 'Alex Morgan';
            _avatar = null;
          })
        : null,
  );

  Widget changePasswordScreen() => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(26),
            children: [
              Center(child: const HireDLogo(width: 160)),
              const SizedBox(height: 24),
              heading(
                'Secure your account',
                'Change the temporary password supplied by HireD admin.',
              ),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Temporary password',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPassword,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password (12+ characters)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPassword,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                ),
              ),
              const SizedBox(height: 18),
              button(
                busy ? 'Updating password…' : 'Update password',
                updatePassword,
              ),
              const SizedBox(height: 12),
              button('Sign out', logout, light: true),
            ],
          ),
        ),
      ),
    ),
  );

  Widget panel(Widget child, {Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: HireDCard(color: color, child: child),
  );

  Widget heading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 28,
            letterSpacing: -.7,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(color: muted, fontSize: 13, height: 1.6),
        ),
      ],
    ),
  );

  Widget section(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 16),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -.2,
      ),
    ),
  );

  Widget button(
    String label,
    VoidCallback onPressed, {
    bool light = false,
  }) => SizedBox(
    width: double.infinity,
    child: light
        ? OutlinedButton(onPressed: busy ? null : onPressed, child: Text(label))
        : FilledButton(onPressed: busy ? null : onPressed, child: Text(label)),
  );

  Widget tripCard(Map<String, dynamic> trip, {bool featured = false}) =>
      DutyCard(
        duty: trip,
        featured: featured,
        onOpen: () => setState(() {
          selectedId = trip['id'].toString();
          page = 4;
        }),
      );

  Widget _stat(
    String label,
    String value,
    IconData icon,
    VoidCallback action,
  ) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: action,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: primary, size: 21),
            const SizedBox(height: 16),
            Text(label, style: const TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 5),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget dashboard() {
    final active = trips.where((trip) => !dutyIsComplete(trip)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('EEEE, d MMMM').format(DateTime.now()),
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        heading(
          'Hello, ${driverName.split(' ').first}',
          'Let’s make it a good day on the road.',
        ),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: online ? const Color(0xFFEDF8F2) : HireDStyle.tint,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.power_settings_new_rounded,
                      color: online ? green : primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          online ? 'You’re online' : 'You’re offline',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          online
                              ? 'Available for assignments'
                              : 'Go online when you’re ready',
                          style: const TextStyle(
                            color: muted,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: online,
                    onChanged: busy
                        ? null
                        : (value) => runTask(() async {
                            if (!demo)
                              await auth.request(
                                '/drivers/me/availability',
                                method: 'PATCH',
                                body: {
                                  'online': value,
                                  'unavailableDates': unavailable.toList(),
                                },
                              );
                            if (mounted) setState(() => online = value);
                          }),
                  ),
                ],
              ),
            ],
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _stat(
                'Active duties',
                '${active.length}',
                Icons.route_outlined,
                () => setState(() {
                  page = 1;
                  _showCompleted = false;
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _stat(
                'Wallet balance',
                money(balance),
                Icons.account_balance_wallet_outlined,
                () => setState(() => page = 2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: section('Your next duty')),
            TextButton(
              onPressed: () => setState(() {
                page = 1;
                _showCompleted = false;
              }),
              child: const Text('View all'),
            ),
          ],
        ),
        if (active.isEmpty)
          const HireDEmptyState(
            icon: Icons.route_outlined,
            title: 'You’re all caught up.',
            description:
                'Your next assigned duty will appear here. Keep your availability up to date.',
          )
        else
          tripCard(active.first, featured: true),
        const SizedBox(height: 20),
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => page = 3),
          child: const HireDCard(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.calendar_month_outlined, color: primary, size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Plan your availability',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Mark days you’re taking off.',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: muted, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget assignments() {
    final active = trips.where((t) => !dutyIsComplete(t)).toList();
    final previous = trips.where(dutyIsComplete).toList();
    final visible = _showCompleted ? previous : active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading('Your duties', 'Everything you need for the road ahead.'),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: false,
                label: Text('Active (${active.length})'),
              ),
              ButtonSegment(
                value: true,
                label: Text('Completed (${previous.length})'),
              ),
            ],
            selected: {_showCompleted},
            onSelectionChanged: (values) =>
                setState(() => _showCompleted = values.first),
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(vertical: 14),
              ),
              side: WidgetStatePropertyAll(BorderSide(color: border)),
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (visible.isEmpty)
          HireDEmptyState(
            icon: _showCompleted
                ? Icons.task_alt_rounded
                : Icons.route_outlined,
            title: _showCompleted
                ? 'Your first completion is ahead.'
                : 'No active duties yet.',
            description: _showCompleted
                ? 'Completed duties stay here for your records.'
                : 'New assignments will appear here. Check back after HireD assigns a duty.',
          ),
        ...visible.map((trip) => tripCard(trip)),
      ],
    );
  }

  Widget detail() {
    final matches = trips
        .where((t) => t['id'].toString() == selectedId)
        .toList();
    if (matches.isEmpty) return const Text('Assignment not available.');
    final t = matches.first;
    final status = t['status']?.toString().toLowerCase() ?? 'unknown';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          'Duty #${dutyReference(t['reference'] ?? t['id'])}',
          'Your assignment details and next steps.',
        ),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HireDBadge(
                dutyStatus(t),
                color: dutyIsComplete(t) ? green : primary,
              ),
              const SizedBox(height: 24),
              DutyRoute(
                pickup: '${t['pickup'] ?? t['pickupAddress'] ?? '—'}',
                destination: '${t['drop'] ?? t['dropAddress'] ?? '—'}',
              ),
              const Divider(height: 32),
              Text(
                '${t['company'] ?? t['companyName'] ?? 'Partner'}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                dutySchedule(t),
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              const Text(
                'The partner/customer provides the vehicle.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
        if (status == 'assigned')
          button(
            'Start driver duty',
            () => runTask(() async {
              if (!demo)
                await auth.request('/trips/${t['id']}/start', method: 'POST');
              setState(() => t['status'] = 'Ongoing');
            }),
          ),
        if (status == 'ongoing') ...[
          section('1. Your duty selfie'),
          panel(
            Column(
              children: [
                Text(
                  t['selfie'] == true
                      ? 'Selfie captured'
                      : 'Capture a selfie for this duty',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 12),
                button(
                  'Take selfie',
                  () => runTask(() async {
                    final photo = await ImagePicker().pickImage(
                      source: ImageSource.camera,
                      imageQuality: 70,
                    );
                    if (photo == null) return;
                    if (!demo)
                      await auth.upload('/trips/${t['id']}/selfie', photo.path);
                    setState(() => t['selfie'] = true);
                  }),
                  light: true,
                ),
              ],
            ),
          ),
          section('2. Add expenses'),
          panel(
            Column(
              children: [
                ...List<Map<String, dynamic>>.from(t['expenses'] ?? []).map(
                  (e) => ListTile(
                    dense: true,
                    title: Text('${e['description']}'),
                    trailing: Text(money((e['amount'] as num?) ?? 0)),
                  ),
                ),
                TextField(
                  controller: expenseTitle,
                  decoration: const InputDecoration(
                    labelText: 'Description (toll, parking…)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: expenseAmount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Amount in ₹'),
                ),
                const SizedBox(height: 12),
                button(
                  'Log expense',
                  () => runTask(() async {
                    final amount = double.tryParse(expenseAmount.text);
                    final title = expenseTitle.text.trim();
                    if (title.isEmpty || amount == null || amount < 0) {
                      throw StateError(
                        'Enter a description and non-negative amount',
                      );
                    }
                    if (!demo)
                      await auth.request(
                        '/trips/${t['id']}/expenses',
                        method: 'POST',
                        body: {'description': title, 'amount': amount},
                      );
                    setState(() {
                      (t['expenses'] as List).add({
                        'description': title,
                        'amount': amount,
                      });
                    });
                    expenseTitle.clear();
                    expenseAmount.clear();
                  }),
                ),
              ],
            ),
          ),
          section('3. Complete your duty'),
          panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Get the OTP from the B2B partner. Record expenses first; '
                  'if none, log “No expenses” with ₹0.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Partner completion code',
                  ),
                ),
                const SizedBox(height: 12),
                button(
                  'Verify & complete duty',
                  () => runTask(() async {
                    if ((t['expenses'] as List).isEmpty) {
                      throw StateError(
                        'Log expenses before closing, including ₹0 if none',
                      );
                    }
                    if (!RegExp(r'^\d{4,8}$').hasMatch(otp.text)) {
                      throw StateError('Enter a valid numeric OTP');
                    }
                    if (demo) {
                      if (otp.text != '4826')
                        throw StateError('Wrong OTP; demo code is 4826');
                      final credit =
                          ((t['amount'] as num) *
                                  ((t['driverSharePct'] as num) / 100))
                              .toDouble();
                      setState(() {
                        t['status'] = 'Closed';
                        balance += credit;
                        credits.insert(0, {
                          'trip': t['id'],
                          'amount': credit,
                          'date': 'Today',
                        });
                        page = 2;
                      });
                    } else {
                      await auth.request(
                        '/trips/${t['id']}/close',
                        method: 'POST',
                        body: {'otp': otp.text},
                      );
                      await refresh();
                      setState(() => page = 2);
                    }
                    otp.clear();
                  }),
                ),
              ],
            ),
          ),
        ],
        if (status == 'closed' || status == 'completed')
          panel(
            const Text(
              '✓ Duty completed. Earnings are shown in your wallet.',
              style: TextStyle(color: green, fontWeight: FontWeight.w700),
            ),
          ),
        button('Back to duties', () => setState(() => page = 1), light: true),
      ],
    );
  }

  Widget wallet() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading('Your earnings', 'A clear view of your completed duties.'),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Colors.white70,
                  size: 21,
                ),
                SizedBox(width: 10),
                Text(
                  'Wallet balance',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              money(balance),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 20),
            const Divider(color: Color(0xFF787CF0)),
            const SizedBox(height: 12),
            const Text(
              'Settlements are managed by HireD.',
              style: TextStyle(color: Colors.white, fontSize: 12, height: 1.5),
            ),
          ],
        ),
        color: primary,
      ),
      section('Earnings history'),
      if (credits.isEmpty)
        const HireDEmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Your earnings start here.',
          description:
              'Credits from completed duties will appear here. Your balance updates after a duty is closed.',
        ),
      ...credits.map(
        (c) => panel(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF8F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.south_west_rounded,
                  color: green,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Duty #${dutyReference(c['trip'] ?? c['tripId'] ?? c['trip_id'])}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${c['date'] ?? c['createdAt'] ?? ''}',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '+${money((c['amount'] as num?) ?? 0)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: green,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget profile() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading('Your profile', 'Your details. Your schedule.'),
      panel(
        Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: HireDStyle.tint,
              backgroundImage: _avatar == null ? null : MemoryImage(_avatar!),
              child: _avatar == null
                  ? const Icon(Icons.person_outline, size: 30, color: primary)
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    driverName,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    demo ? 'Demo driver profile' : 'HireD driver partner',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      section('Availability'),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Planning a day off?',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap a date to mark it unavailable. Tap again to make it available.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.6),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 14,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final date = DateTime.now().add(Duration(days: i));
                  final key = DateFormat('yyyy-MM-dd').format(date);
                  final blocked = unavailable.contains(key);
                  return Semantics(
                    button: true,
                    selected: blocked,
                    label:
                        '${DateFormat('d MMMM').format(date)}, ${blocked ? 'unavailable' : 'available'}',
                    child: ExcludeSemantics(
                      child: Material(
                        color: blocked ? const Color(0xFFFFF1EE) : bg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: blocked ? const Color(0xFFF4B4AC) : border,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: busy
                              ? null
                              : () => runTask(() async {
                                  final next = {...unavailable};
                                  if (blocked) {
                                    next.remove(key);
                                  } else {
                                    next.add(key);
                                  }
                                  if (!demo)
                                    await auth.request(
                                      '/drivers/me/availability',
                                      method: 'PATCH',
                                      body: {
                                        'online': online,
                                        'unavailableDates': next.toList(),
                                      },
                                    );
                                  if (mounted)
                                    setState(() {
                                      unavailable
                                        ..clear()
                                        ..addAll(next);
                                    });
                                }),
                          child: SizedBox(
                            width: 60,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  DateFormat('EEE').format(date),
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  '${date.day}',
                                  style: TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w700,
                                    color: blocked
                                        ? const Color(0xFFB42318)
                                        : ink,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  blocked ? 'Off' : 'Available',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: blocked
                                        ? const Color(0xFFB42318)
                                        : muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      section('Your documents'),
      panel(
        Column(
          children: [
            ...{
              'license': 'Driving licence',
              'aadhaar': 'Aadhaar card',
              'pan': 'PAN card',
              'pcc': 'Police clearance',
            }.entries.map(
              (entry) => Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    minVerticalPadding: 12,
                    leading: Icon(
                      entry.key == 'license'
                          ? Icons.badge_outlined
                          : Icons.description_outlined,
                      color: primary,
                      size: 22,
                    ),
                    title: Text(
                      entry.value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      docs[entry.key] == true
                          ? 'Uploaded · tap to replace'
                          : 'No document uploaded',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                    trailing: IconButton(
                      tooltip: 'Upload ${entry.value.toLowerCase()}',
                      onPressed: busy
                          ? null
                          : () => runTask(() async {
                              final chosen = await FilePicker.platform
                                  .pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: [
                                      'jpg',
                                      'jpeg',
                                      'png',
                                      'pdf',
                                    ],
                                  );
                              final path = chosen?.files.single.path;
                              if (path == null) return;
                              if (!demo)
                                await auth.upload(
                                  '/drivers/me/documents/${entry.key}',
                                  path,
                                );
                              if (mounted)
                                setState(() => docs[entry.key] = true);
                            }),
                      icon: Icon(
                        docs[entry.key] == true
                            ? Icons.swap_horiz_rounded
                            : Icons.add_rounded,
                        color: primary,
                      ),
                    ),
                  ),
                  if (entry.key != 'pcc') const Divider(height: 1),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      button(
        demo ? 'Exit demo' : 'Sign out',
        demo
            ? () => setState(() {
                demo = false;
                page = 0;
              })
            : logout,
        light: true,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (restoring)
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HireDLogo(width: 160),
              SizedBox(height: 28),
              CircularProgressIndicator(),
            ],
          ),
        ),
      );
    if (!demo && token == null) return loginScreen();
    if (!demo && mustChangePassword) return changePasswordScreen();
    return PopScope(
      canPop: page != 4,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && page == 4) setState(() => page = 1);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: page == 4
              ? IconButton(
                  tooltip: 'Back to duties',
                  onPressed: () => setState(() => page = 1),
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              : null,
          title: const HireDLogo(width: 96),
          actions: [
            if (demo) const HireDBadge('DEMO'),
            IconButton(
              tooltip: 'Refresh duties and earnings',
              onPressed: busy ? null : () => runTask(refresh),
              icon: const Icon(Icons.refresh_rounded, size: 22),
            ),
            IconButton(
              tooltip: 'Your profile',
              onPressed: () => setState(() => page = 3),
              icon: CircleAvatar(
                radius: 17,
                backgroundColor: HireDStyle.tint,
                backgroundImage: _avatar == null ? null : MemoryImage(_avatar!),
                child: _avatar == null
                    ? const Icon(Icons.person_outline, color: primary, size: 20)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: Column(
          children: [
            if (busy)
              const LinearProgressIndicator(color: primary, minHeight: 2),
            Expanded(
              child: SafeArea(
                top: false,
                bottom: false,
                child: RefreshIndicator(
                  onRefresh: () => runTask(refresh),
                  child: ListView(
                    key: ValueKey('driver-page-$page'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 680),
                          child: switch (page) {
                            0 => dashboard(),
                            1 => assignments(),
                            2 => wallet(),
                            3 => profile(),
                            _ => detail(),
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: page == 4
            ? null
            : DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: border)),
                ),
                child: NavigationBar(
                  selectedIndex: page,
                  onDestinationSelected: (i) => setState(() => page = i),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.grid_view_outlined),
                      selectedIcon: Icon(Icons.grid_view_rounded),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.route_outlined),
                      selectedIcon: Icon(Icons.route_rounded),
                      label: 'Duties',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.account_balance_wallet_outlined),
                      selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                      label: 'Earnings',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.person_outline),
                      selectedIcon: Icon(Icons.person_rounded),
                      label: 'Profile',
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
