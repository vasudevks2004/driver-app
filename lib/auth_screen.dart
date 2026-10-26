import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'api.dart';
import 'auth.dart';
import 'auth_validation.dart';
import 'identity_auth.dart';
import 'brand.dart';
import 'design.dart';
import 'onboarding.dart';
import 'onboarding_screen.dart';

const _primary = HireDStyle.primary;
const _ink = HireDStyle.ink;
const _muted = HireDStyle.muted;
const _line = HireDStyle.line;

enum _AuthView { login, register, otp, activation, onboarding }

class DriverAuthScreen extends StatefulWidget {
  const DriverAuthScreen({
    super.key,
    required this.auth,
    required this.onAuthenticated,
    this.onDemo,
    this.onboarding,
  });

  final DriverAuth auth;
  final DriverOnboarding? onboarding;
  final Future<void> Function(DriverSession session) onAuthenticated;
  final VoidCallback? onDemo;

  @override
  State<DriverAuthScreen> createState() => _DriverAuthScreenState();
}

class _DriverAuthScreenState extends State<DriverAuthScreen> {
  final _form = GlobalKey<FormState>();
  late final _onboarding =
      widget.onboarding ?? DriverOnboarding(widget.auth.identity.config);
  IdentitySession? _applicantSession;
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _code = TextEditingController();
  _AuthView _view = _AuthView.login;
  bool _emailMode = false;
  bool _passwordVisible = false;
  bool _busy = false;
  bool _registering = false;
  bool _acknowledged = false;
  String _countryCode = '+91';
  String _sentTo = '';
  String? _registrationName;
  String? _registrationCity;
  String? _error;
  int _resendSeconds = 0;
  Timer? _timer;

  DriverAuthMethods _methods = const DriverAuthMethods(
    phone: false,
    google: false,
    email: true,
    known: false,
  );
  String? _methodsError;
  @override
  void initState() {
    super.initState();
    _checkMethods();
  }

  Future<void> _checkMethods() async {
    try {
      final methods = await widget.auth.methods();
      if (mounted) {
        setState(() {
          _methods = methods;
          _methodsError = null;
          if (!methods.phone && methods.email) _emailMode = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _methodsError =
              'Could not check sign-in availability. Check your connection and retry.',
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_applicantSession != null) {
      unawaited(
        widget.auth.identity
            .signOut(_applicantSession!.accessToken)
            .catchError((_) {}),
      );
    }
    if (widget.onboarding == null) _onboarding.dispose();
    for (final controller in [_phone, _email, _password, _name, _city, _code]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _navigate(_AuthView view) {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _view = view;
      _error = null;
      _password.clear();
      _code.clear();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on DriverActivationRequired {
      if (mounted) setState(() => _view = _AuthView.activation);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error) {
            DriverAuthException() => error.message,
            ApiException() => error.message,
            _ => 'Unable to sign in right now. Please try again.',
          },
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendSeconds = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendSeconds--);
      if (_resendSeconds <= 0) timer.cancel();
    });
  }

  Future<void> _sendOtp() async {
    if (!_form.currentState!.validate()) return;
    final registering = _view == _AuthView.register;
    if (registering && !_acknowledged) {
      setState(
        () => _error = 'Please confirm the driver review information below.',
      );
      return;
    }
    final phone = normalizePhone(_phone.text, countryCode: _countryCode)!;
    final name = registering ? _name.text.trim() : null;
    final city = registering ? _city.text.trim() : null;
    await _run(() async {
      await widget.auth.sendPhoneOtp(
        phone,
        register: registering,
        fullName: name,
        city: city,
      );
      if (!mounted) return;
      setState(() {
        _sentTo = phone;
        _registering = registering;
        _registrationName = name;
        _registrationCity = city;
        _code.clear();
        _view = _AuthView.otp;
      });
      _startResendTimer();
    });
  }

  Future<void> _verifyOtp() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      if (_registering) {
        final identity = await widget.auth.verifyRegistrationOtp(
          _sentTo,
          _code.text.trim(),
        );
        if (!mounted) {
          await widget.auth.identity.signOut(identity.accessToken);
          return;
        }
        _timer?.cancel();
        setState(() {
          _applicantSession = identity;
          _view = _AuthView.onboarding;
          _code.clear();
        });
        return;
      }
      final session = await widget.auth.verifyPhoneOtp(
        _sentTo,
        _code.text.trim(),
      );
      _code.clear();
      if (!mounted) return;
      await widget.onAuthenticated(session);
    });
  }

  Future<void> _resendOtp() => _run(() async {
    if (_resendSeconds > 0) return;
    await widget.auth.sendPhoneOtp(
      _sentTo,
      register: _registering,
      fullName: _registrationName,
      city: _registrationCity,
    );
    if (!mounted) return;
    _code.clear();
    _startResendTimer();
  });

  Future<void> _loginWithEmail() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      final session = await widget.auth.login(
        _email.text.trim(),
        _password.text,
      );
      _password.clear();
      if (!mounted) return;
      await widget.onAuthenticated(session);
    });
  }

  Future<void> _loginWithGoogle() => _run(() async {
    final session = await widget.auth.loginWithGoogle();
    if (session != null && mounted) await widget.onAuthenticated(session);
  });

  Widget _title(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -.8,
          color: _ink,
        ),
      ),
      const SizedBox(height: 9),
      Text(
        subtitle,
        style: const TextStyle(color: _muted, fontSize: 14, height: 1.6),
      ),
      const SizedBox(height: 27),
    ],
  );

  InputDecoration _decoration(String hint, IconData? icon) => InputDecoration(
    hintText: hint,
    prefixIcon: icon == null ? null : Icon(icon, size: 20, color: _muted),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _primary, width: 1.5),
    ),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: _ink,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
    ),
  );

  Widget _primaryButton(String title, VoidCallback action) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: _busy || !_methods.known ? null : action,
      style: FilledButton.styleFrom(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: _busy
          ? const SizedBox(
              width: 21,
              height: 21,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
    ),
  );

  Widget _googleButton() => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      key: const Key('google-sign-in'),
      onPressed: _busy ? null : _loginWithGoogle,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 54),
        side: const BorderSide(color: _line),
        foregroundColor: _ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset('assets/google-g.svg', width: 20, height: 20),
          const SizedBox(width: 12),
          const Flexible(
            child: Text(
              'Continue with Google',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _divider() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 23),
    child: Row(
      children: [
        Expanded(child: Divider(color: _line)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text('or', style: TextStyle(color: _muted, fontSize: 12)),
        ),
        Expanded(child: Divider(color: _line)),
      ],
    ),
  );

  Widget _phoneField() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label('Mobile number'),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 94,
            child: DropdownButtonFormField<String>(
              initialValue: _countryCode,
              isExpanded: true,
              decoration: _decoration('', null).copyWith(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 17,
                ),
              ),
              items: ['+91', '+971', '+1', '+44']
                  .map(
                    (code) => DropdownMenuItem(value: code, child: Text(code)),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _countryCode = value!),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              key: const Key('phone-number'),
              controller: _phone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+()\s-]')),
                LengthLimitingTextInputFormatter(24),
              ],
              decoration: _decoration('Mobile number', Icons.phone_outlined),
              validator: (value) =>
                  normalizePhone(value ?? '', countryCode: _countryCode) == null
                  ? 'Enter a valid mobile number'
                  : null,
              onFieldSubmitted: (_) => _sendOtp(),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _emailFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label('Email address'),
      TextFormField(
        key: const Key('email-address'),
        controller: _email,
        enabled: !_busy,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.email],
        autocorrect: false,
        decoration: _decoration('driver@example.com', Icons.alternate_email),
        validator: (value) =>
            isValidEmail(value ?? '') ? null : 'Enter a valid email address',
      ),
      const SizedBox(height: 18),
      _label('Password'),
      TextFormField(
        key: const Key('login-password'),
        controller: _password,
        enabled: !_busy,
        obscureText: !_passwordVisible,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.password],
        decoration: _decoration('Enter your password', Icons.lock_outline)
            .copyWith(
              suffixIcon: IconButton(
                tooltip: _passwordVisible ? 'Hide password' : 'Show password',
                onPressed: _busy
                    ? null
                    : () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                icon: Icon(
                  _passwordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: _muted,
                ),
              ),
            ),
        validator: (value) =>
            value == null || value.isEmpty ? 'Enter your password' : null,
        onFieldSubmitted: (_) => _loginWithEmail(),
      ),
    ],
  );

  Widget _login() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_methodsError != null) ...[
        HireDNotice(_methodsError!, error: true),
        TextButton(
          onPressed: _checkMethods,
          child: const Text('Retry sign-in methods'),
        ),
      ],
      _title(
        'Welcome back.',
        'Sign in to see your duties, availability and earnings.',
      ),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.phone_outlined, size: 17),
              label: Text('Phone'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.mail_outline, size: 17),
              label: Text('Email'),
            ),
          ],
          selected: {_emailMode},
          onSelectionChanged: _busy
              ? null
              : (value) => setState(() {
                  _emailMode = value.first;
                  _error = null;
                  _password.clear();
                  _form.currentState?.reset();
                }),
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(vertical: 14),
            ),
            side: const WidgetStatePropertyAll(BorderSide(color: _line)),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? HireDStyle.tint
                  : Colors.white,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.selected) ? _primary : _muted,
            ),
          ),
        ),
      ),
      const SizedBox(height: 23),
      if (_emailMode) _emailFields() else _phoneField(),
      const SizedBox(height: 12),
      if (!_emailMode)
        const Text(
          'We’ll send you a 6-digit verification code.',
          style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
        ),
      _errorBanner(),
      const SizedBox(height: 20),
      _primaryButton(
        _emailMode ? 'Sign in' : 'Send OTP',
        _emailMode ? _loginWithEmail : _sendOtp,
      ),
      if (_methods.google) ...[_divider(), _googleButton()],
      if (_methods.known && !_methods.phone)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text(
            'Phone sign-in and new driver registration are being set up. Use your HireD email account for now.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.6),
          ),
        ),
      const SizedBox(height: 21),
      Center(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'New to HireD?',
              style: TextStyle(color: _muted, fontSize: 13),
            ),
            TextButton(
              key: const Key('open-register'),
              onPressed: _busy || !_methods.phone
                  ? null
                  : () => _navigate(_AuthView.register),
              child: const Text('Register as a new driver'),
            ),
          ],
        ),
      ),
      if (widget.onDemo != null)
        Center(
          child: TextButton(
            onPressed: _busy ? null : widget.onDemo,
            child: const Text('Explore demo'),
          ),
        ),
    ],
  );

  Widget _register() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(
        'Drive with HireD.',
        'Register as a new driver. Start with your details, then verify your mobile.',
      ),
      const Padding(
        padding: EdgeInsets.only(bottom: 24),
        child: HireDSteps(
          labels: ['Details', 'Mobile', 'Documents'],
          current: 0,
        ),
      ),
      _label('Full name'),
      TextFormField(
        key: const Key('register-name'),
        controller: _name,
        enabled: !_busy,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.name],
        maxLength: 100,
        decoration: _decoration(
          'Your full name',
          Icons.person_outline,
        ).copyWith(counterText: ''),
        validator: (value) =>
            (value?.trim().length ?? 0) < 2 ? 'Enter your full name' : null,
      ),
      const SizedBox(height: 18),
      _phoneField(),
      const SizedBox(height: 18),
      _label('City'),
      TextFormField(
        key: const Key('register-city'),
        controller: _city,
        enabled: !_busy,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.addressCity],
        maxLength: 80,
        decoration: _decoration(
          'Your city',
          Icons.location_on_outlined,
        ).copyWith(counterText: ''),
        validator: (value) =>
            (value?.trim().length ?? 0) < 2 ? 'Enter your city' : null,
      ),
      const SizedBox(height: 18),
      const HireDNotice(
        'Have these ready: driving licence, Aadhaar number and card photo, PAN card, police clearance certificate (PCC), and a selfie.',
        icon: Icons.fact_check_outlined,
      ),
      const SizedBox(height: 14),
      CheckboxListTile(
        key: const Key('registration-acknowledgement'),
        value: _acknowledged,
        activeColor: _primary,
        onChanged: _busy
            ? null
            : (value) => setState(() => _acknowledged = value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: const Text(
          'I understand HireD reviews driver profiles before assigning duties.',
          style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
        ),
      ),
      _errorBanner(),
      const SizedBox(height: 14),
      _primaryButton('Verify mobile & continue', _sendOtp),
      const SizedBox(height: 16),
      Center(
        child: TextButton(
          onPressed: _busy ? null : () => _navigate(_AuthView.login),
          child: const Text('Already registered? Sign in'),
        ),
      ),
    ],
  );

  Widget _otpPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(17),
        margin: const EdgeInsets.only(bottom: 25),
        decoration: BoxDecoration(
          color: const Color(0xFFEEEFFF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.sms_outlined, color: _primary, size: 31),
      ),
      _title(
        'Verify your number.',
        widget.onboarding?.isPreview == true
            ? 'Enter the local test code 123456. No SMS was sent.'
            : 'Enter the 6-digit code sent to $_sentTo.',
      ),
      _label('Verification code'),
      TextFormField(
        key: const Key('phone-otp'),
        controller: _code,
        enabled: !_busy,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 8,
        ),
        textAlign: TextAlign.center,
        decoration: _decoration('000000', null),
        validator: (value) =>
            isValidOtp(value ?? '') ? null : 'Enter the 6-digit code',
        onFieldSubmitted: (_) => _verifyOtp(),
      ),
      _errorBanner(),
      const SizedBox(height: 24),
      _primaryButton(
        _registering ? 'Verify & continue' : 'Verify & sign in',
        _verifyOtp,
      ),
      const SizedBox(height: 15),
      Center(
        child: TextButton(
          key: const Key('resend-otp'),
          onPressed: _busy || _resendSeconds > 0 ? null : _resendOtp,
          child: Text(
            _resendSeconds > 0
                ? 'Resend code in ${_resendSeconds}s'
                : 'Resend code',
          ),
        ),
      ),
      Center(
        child: TextButton(
          onPressed: _busy
              ? null
              : () => _navigate(
                  _registering ? _AuthView.register : _AuthView.login,
                ),
          child: const Text('Change mobile number'),
        ),
      ),
    ],
  );

  Widget _activationPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.verified_user_outlined, color: _primary, size: 54),
      const SizedBox(height: 24),
      _title(
        'Identity verified.',
        'Your HireD driver profile needs to be activated before you can access duties.',
      ),
      const Text(
        'Contact your HireD administrator to review or link your driver profile. '
        'Use the same verified mobile number or Google account when you return.',
        style: TextStyle(color: _muted, height: 1.7, fontSize: 14),
      ),
      const SizedBox(height: 28),
      _primaryButton('Back to sign in', () => _navigate(_AuthView.login)),
    ],
  );

  Widget _errorBanner() => _error == null
      ? const SizedBox.shrink()
      : Container(
          key: const Key('auth-error'),
          width: double.infinity,
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFAD2537),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        );

  @override
  Widget build(BuildContext context) => _view == _AuthView.onboarding
      ? DriverOnboardingScreen(
          service: _onboarding,
          session: _applicantSession!,
          fullName: _registrationName!,
          city: _registrationCity!,
          onClose: () async {
            final session = _applicantSession;
            _applicantSession = null;
            if (session != null) {
              try {
                await widget.auth.identity.signOut(session.accessToken);
              } catch (_) {}
            }
            if (mounted) _navigate(_AuthView.login);
          },
        )
      : PopScope(
          canPop: _view == _AuthView.login && !_busy,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !_busy) {
              _navigate(
                _view == _AuthView.otp && _registering
                    ? _AuthView.register
                    : _AuthView.login,
              );
            }
          },
          child: Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      Row(
                        children: [
                          if (_view != _AuthView.login)
                            IconButton(
                              tooltip: 'Back to sign in',
                              onPressed: _busy
                                  ? null
                                  : () => _navigate(
                                      _view == _AuthView.otp && _registering
                                          ? _AuthView.register
                                          : _AuthView.login,
                                    ),
                              icon: const Icon(Icons.arrow_back, color: _ink),
                            ),
                          const HireDLogo(width: 112),
                          const Spacer(),
                          const HireDBadge('DRIVER'),
                        ],
                      ),
                      const SizedBox(height: 52),
                      Container(
                        padding: EdgeInsets.zero,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: AutofillGroup(
                          child: Form(
                            key: _form,
                            child: KeyedSubtree(
                              key: ValueKey('auth-${_view.name}-$_emailMode'),
                              child: switch (_view) {
                                _AuthView.login => _login(),
                                _AuthView.register => _register(),
                                _AuthView.otp => _otpPage(),
                                _AuthView.activation => _activationPage(),
                                _AuthView.onboarding => const SizedBox.shrink(),
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shield_outlined, color: _muted, size: 15),
                          SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              'Duties, availability and earnings. In one place.',
                              style: TextStyle(color: _muted, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
}
