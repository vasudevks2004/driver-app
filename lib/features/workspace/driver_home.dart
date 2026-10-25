import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../auth.dart';
import '../../identity_auth.dart';
import '../../auth_screen.dart';
import '../../brand.dart';
import '../../design.dart';
import '../../onboarding.dart';
import '../duties/duties_page.dart';
import '../duties/duty_detail.dart';
import '../earnings/earnings_page.dart';
import '../profile/profile_page.dart';
import 'controller.dart';
import 'dashboard.dart';

const driverApiUrl = String.fromEnvironment('API_URL', defaultValue: '');

class DriverHome extends StatefulWidget {
  const DriverHome({super.key, this.authOverride, this.onboardingOverride});
  final DriverAuth? authOverride;
  final DriverOnboarding? onboardingOverride;
  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> with WidgetsBindingObserver {
  late final auth = widget.authOverride ?? DriverAuth(driverApiUrl);
  late final workspace = DriverWorkspace(auth);
  bool restoring = true;
  String? restoreError;
  Uint8List? avatar;
  final oldPassword = TextEditingController(),
      newPassword = TextEditingController(),
      confirm = TextEditingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    workspace.dispose();
    auth.dispose();
    oldPassword.dispose();
    newPassword.dispose();
    confirm.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      workspace.foreground(state == AppLifecycleState.resumed);
  Future<void> _restore() async {
    if (mounted)
      setState(() {
        restoring = true;
        restoreError = null;
      });
    try {
      final session = await auth.restore();
      if (mounted && session != null) await _activate(session);
    } catch (_) {
      if (mounted)
        setState(
          () => restoreError =
              'Your saved session could not be verified. Check your connection and retry.',
        );
    } finally {
      if (mounted) setState(() => restoring = false);
    }
  }

  Future<void> _activate(DriverSession session) async {
    workspace.activate(session);
    if (mounted) setState(() => avatar = null);
    unawaited(_avatar(session));
    if (!session.mustChangePassword) await workspace.refresh();
  }

  Future<void> _avatar(DriverSession session) async {
    final service =
        widget.onboardingOverride ?? DriverOnboarding(auth.identity.config);
    try {
      final image = await service.avatar(session.token);
      if (mounted && auth.current?.token == session.token)
        setState(() => avatar = image);
    } catch (_) {
    } finally {
      if (widget.onboardingOverride == null) service.dispose();
    }
  }

  Future<void> _logout() async {
    if (workspace.isDemo) {
      workspace.reset();
      return;
    }
    await workspace.perform(() async {
      await auth.logout();
      workspace.reset();
      if (mounted) setState(() => avatar = null);
    });
  }

  Widget _passwordScreen() => Scaffold(
    appBar: AppBar(title: const HireDLogo(width: 100)),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Secure your account',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        const Text('Change the temporary password supplied by HireD admin.'),
        const SizedBox(height: 24),
        TextField(
          controller: oldPassword,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Temporary password'),
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
          controller: confirm,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Confirm new password'),
        ),
        if (workspace.actionError != null) ...[
          const SizedBox(height: 16),
          HireDNotice(workspace.actionError!, error: true),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: workspace.busy
              ? null
              : () => workspace.perform(() async {
                  if (oldPassword.text.isEmpty ||
                      newPassword.text != confirm.text ||
                      utf8.encode(newPassword.text).length < 12 ||
                      utf8.encode(newPassword.text).length > 72)
                    throw const DriverAuthException(
                      'Enter the temporary password and matching new passwords of 12–72 bytes.',
                    );
                  final session = await auth.changePassword(
                    oldPassword.text,
                    newPassword.text,
                  );
                  oldPassword.clear();
                  newPassword.clear();
                  confirm.clear();
                  await _activate(session);
                }),
          child: Text(
            workspace.busy ? 'Updating password…' : 'Update password',
          ),
        ),
        TextButton(
          onPressed: workspace.busy ? null : _logout,
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: workspace,
    builder: (context, _) {
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
      if (restoreError != null)
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const HireDLogo(width: 130),
                    const SizedBox(height: 24),
                    HireDNotice(restoreError!, error: true),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _restore,
                      child: const Text('Retry session verification'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await auth.logout();
                        if (mounted) setState(() => restoreError = null);
                      },
                      child: const Text('Sign out on this device'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      if (!workspace.isDemo && auth.current == null)
        return DriverAuthScreen(
          auth: auth,
          onboarding: widget.onboardingOverride,
          onAuthenticated: _activate,
          onDemo: kDebugMode && allowDemo ? () => workspace.demo() : null,
        );
      if (!workspace.isDemo && auth.current!.mustChangePassword)
        return _passwordScreen();
      return PopScope(
        canPop: workspace.page != 4,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) workspace.navigate(1);
        },
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: workspace.page == 4
                ? IconButton(
                    tooltip: 'Back to duties',
                    onPressed: () => workspace.navigate(1),
                    icon: const Icon(Icons.arrow_back_rounded),
                  )
                : null,
            title: const HireDLogo(width: 96),
            actions: [
              if (workspace.isDemo) const HireDBadge('DEMO'),
              IconButton(
                tooltip: 'Refresh duties and earnings',
                onPressed: workspace.busy ? null : () => workspace.refresh(),
                icon: const Icon(Icons.refresh_rounded, size: 22),
              ),
              IconButton(
                tooltip: 'Your profile',
                onPressed: () => workspace.navigate(3),
                icon: CircleAvatar(
                  radius: 17,
                  backgroundColor: HireDStyle.tint,
                  backgroundImage: avatar == null ? null : MemoryImage(avatar!),
                  child: avatar == null
                      ? const Icon(
                          Icons.person_outline,
                          color: HireDStyle.primary,
                          size: 20,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: Column(
            children: [
              if (workspace.busy) const LinearProgressIndicator(minHeight: 2),
              if (workspace.notice != null)
                Material(
                  color: HireDStyle.tint,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.notifications_none,
                      color: HireDStyle.primary,
                    ),
                    title: Text(
                      workspace.notice!,
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: IconButton(
                      tooltip: 'Dismiss assignment update',
                      onPressed: workspace.clearNotice,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                    onTap: () => workspace.navigate(1),
                  ),
                ),
              if (workspace.actionError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: HireDNotice(workspace.actionError!, error: true),
                ),
              Expanded(
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: RefreshIndicator(
                    onRefresh: workspace.refresh,
                    child: KeyedSubtree(
                      key: ValueKey('driver-page-${workspace.page}'),
                      child: switch (workspace.page) {
                        0 => DriverDashboard(state: workspace),
                        1 => DutiesPage(state: workspace),
                        2 => EarningsPage(state: workspace),
                        3 => DriverProfilePage(
                          state: workspace,
                          avatar: avatar,
                          signOut: _logout,
                        ),
                        _ => DutyDetailPage(state: workspace),
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: workspace.page == 4
              ? null
              : DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: HireDStyle.line)),
                  ),
                  child: NavigationBar(
                    selectedIndex: workspace.page,
                    onDestinationSelected: workspace.navigate,
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
                        selectedIcon: Icon(
                          Icons.account_balance_wallet_rounded,
                        ),
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
    },
  );
}
