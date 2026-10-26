import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand.dart';
import 'design.dart';
import 'identity_auth.dart';
import 'onboarding.dart';

part 'features/onboarding/application_sections.dart';

class DriverOnboardingScreen extends StatefulWidget {
  const DriverOnboardingScreen({
    super.key,
    required this.service,
    required this.session,
    required this.fullName,
    required this.city,
    required this.onClose,
    this.pickImage,
    this.openBrowser,
  });
  final DriverOnboarding service;
  final IdentitySession session;
  final String fullName, city;
  final Future<void> Function() onClose;
  final Future<Uint8List?> Function(String kind, ImageSource source)? pickImage;
  final Future<bool> Function(Uri uri)? openBrowser;

  @override
  State<DriverOnboardingScreen> createState() => _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState extends State<DriverOnboardingScreen>
    with WidgetsBindingObserver {
  final _licenceForm = GlobalKey<FormState>();
  final _identityForm = GlobalKey<FormState>();
  final _licence = TextEditingController();
  final _name = TextEditingController(), _city = TextEditingController();
  final _aadhaar = TextEditingController();
  final _scroll = ScrollController();
  DriverApplication? _application;
  DateTime? _birthDate, _expiry;
  String _vehicleClass = 'LMV';
  Uint8List? _selfie;
  int _step = 0;
  bool _busy = false,
      _consent = false,
      _digiPending = false,
      _showAadhaar = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _name.text = widget.fullName;
    _city.text = widget.city;
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _licence.dispose();
    _name.dispose();
    _city.dispose();
    _aadhaar.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _digiPending && !_busy) {
      _refresh();
    }
    // Do not leave a revealed identity number on the app switcher's next frame.
    if (state == AppLifecycleState.inactive && _showAadhaar && mounted) {
      setState(() => _showAadhaar = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is DriverAuthException
              ? e.message
              : 'We could not complete that step. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    final application = await widget.service.open(
      widget.session.accessToken,
      name: widget.fullName,
      city: widget.city,
    );
    if (mounted) {
      setState(() {
        _application = application;
        _licence.text = application.data['licence_number']?.toString() ?? '';
        _birthDate = DateTime.tryParse(
          application.data['birth_date']?.toString() ?? '',
        );
        _expiry = DateTime.tryParse(
          application.data['licence_expiry']?.toString() ?? '',
        );
        _vehicleClass = application.data['vehicle_class']?.toString() ?? 'LMV';
      });
    }
  });

  Future<void> _refresh() => _run(() async {
    final application = await widget.service.status(widget.session.accessToken);
    if (mounted) {
      setState(() {
        _application = application;
        _digiPending = application.digiLockerStatus == 'pending';
      });
    }
  });

  Future<void> _saveAndContinue(int step) => _run(() async {
    final saved = await widget.service.saveDraft(widget.session.accessToken, {
      'full_name': _name.text.trim(),
      'city': _city.text.trim(),
      'licence_number': _licence.text.trim().toUpperCase(),
      if (_birthDate != null)
        'birth_date': _birthDate!.toIso8601String().split('T').first,
      if (_expiry != null)
        'licence_expiry': _expiry!.toIso8601String().split('T').first,
      'vehicle_class': _vehicleClass,
    });
    if (mounted) {
      setState(() => _application = saved);
      _go(step);
    }
  });

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your application?'),
        content: const Text(
          'Your application details will be removed and private uploads queued for deletion. You can register again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep application'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete application'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await widget.service.deleteApplication(widget.session.accessToken);
      await widget.onClose();
    });
  }

  void updateView(VoidCallback action) => setState(action);

  void _go(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = step;
      _error = null;
      _showAadhaar = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _pick(String kind, ImageSource source) => _run(() async {
    Uint8List? bytes;
    try {
      if (widget.pickImage != null) {
        bytes = await widget.pickImage!(kind, source);
      } else {
        final image = await ImagePicker().pickImage(
          source: source,
          preferredCameraDevice: kind == 'selfie'
              ? CameraDevice.front
              : CameraDevice.rear,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
          requestFullMetadata: false,
        );
        if (image != null) {
          if (await image.length() > maxDriverImageBytes) {
            throw const DriverAuthException(
              'Choose an image smaller than 5 MB.',
            );
          }
          bytes = await image.readAsBytes();
        }
      }
    } on PlatformException {
      throw const DriverAuthException(
        'Camera or photo access is unavailable. Allow access in your device settings and try again.',
      );
    }
    if (bytes == null) return;
    final application = await widget.service.upload(
      widget.session.accessToken,
      kind,
      bytes,
    );
    if (mounted) {
      setState(() {
        _application = application;
        if (kind == 'selfie') _selfie = bytes;
      });
    }
  });

  Future<void> _chooseDocument(String kind) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from photos'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source != null && mounted) await _pick(kind, source);
  }

  Future<void> _connectDigiLocker() async {
    final consent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share your driving licence?'),
        content: const Text(
          'DigiLocker will ask for permission to share an issued driving licence with HireD for review. Sign in on the government website. You can cancel and upload licence photos instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue to DigiLocker'),
          ),
        ],
      ),
    );
    if (consent != true || !mounted) return;
    await _run(() async {
      final uri = await widget.service.startDigiLocker(
        widget.session.accessToken,
      );
      final opened =
          await (widget.openBrowser?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!opened) {
        throw const DriverAuthException(
          'Could not open DigiLocker. Please try again.',
        );
      }
      if (mounted) setState(() => _digiPending = true);
    });
  }

  Future<void> _date(bool birth) async {
    final now = DateUtils.dateOnly(DateTime.now());
    final first = birth ? DateTime(1900) : now;
    final last = birth
        ? now.subtract(const Duration(days: 1))
        : DateTime(now.year + 40);
    var initial = birth
        ? (_birthDate ?? DateTime(now.year - 25, now.month, now.day))
        : (_expiry ?? now.add(const Duration(days: 365)));
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (selected != null && mounted) {
      setState(() {
        if (birth) {
          _birthDate = selected;
        } else {
          _expiry = selected;
        }
      });
    }
  }

  bool _validateLicence() {
    if (!(_licenceForm.currentState?.validate() ?? false)) return false;
    if (_birthDate == null || _expiry == null) {
      setState(
        () => _error = 'Add your date of birth and licence expiry date.',
      );
      return false;
    }
    if (_application?.hasDigiLockerDocument != true &&
        (_application?.frontUploaded != true ||
            _application?.backUploaded != true)) {
      setState(
        () => _error =
            'Add both licence photos, or share your licence through DigiLocker.',
      );
      return false;
    }
    return true;
  }

  bool _validateIdentity() {
    if (!(_identityForm.currentState?.validate() ?? false)) return false;
    if (_application?.aadhaarUploaded != true ||
        _application?.selfieUploaded != true) {
      setState(
        () => _error =
            'Add your Aadhaar card photo and take a selfie to continue.',
      );
      return false;
    }
    if (_application?.panUploaded != true ||
        _application?.pccUploaded != true) {
      setState(
        () =>
            _error = 'Add your PAN and police clearance documents to continue.',
      );
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_consent) {
      setState(
        () => _error =
            'Please agree to the document review and profile photo use.',
      );
      return;
    }
    // Recheck required details even if the review screen is restored externally.
    if (!validLicenceNumber(_licence.text) ||
        _birthDate == null ||
        _expiry == null) {
      _go(0);
      return;
    }
    if (!validAadhaarNumber(_aadhaar.text)) {
      _go(1);
      return;
    }
    await _run(() async {
      final result = await widget.service.submit(
        widget.session.accessToken,
        licenceNumber: _licence.text,
        aadhaarNumber: _aadhaar.text,
        birthDate: _birthDate!,
        licenceExpiry: _expiry!,
        vehicleClass: _vehicleClass,
      );
      if (mounted) {
        setState(() {
          _application = result;
          _selfie = null;
          _aadhaar.clear();
          _showAadhaar = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final submitted = _application != null && !_application!.editable;
    final titles = [
      'Your driving licence.',
      'A little more about you.',
      'Everything look right?',
    ];
    final subtitles = [
      'Add your licence details and a clear photo of each side.',
      'Add your Aadhaar and a selfie so HireD can review your identity.',
      'Check your details before sending your application to HireD.',
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy && !submitted && _step > 0) _go(_step - 1);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const HireDLogo(width: 100),
          actions: [
            TextButton(
              onPressed: _busy ? null : widget.onClose,
              child: const Text('Exit'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 20),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (submitted) ...[
                    _receipt(),
                    TextButton(
                      onPressed: _busy ? null : _refresh,
                      child: const Text('Refresh application status'),
                    ),
                    if (_application?.status != 'approved')
                      TextButton(
                        onPressed: _busy ? null : _delete,
                        child: const Text('Delete application'),
                      ),
                    if (_error != null) HireDNotice(_error!, error: true),
                  ] else if (_application == null) ...[
                    const SizedBox(height: 48),
                    const Text(
                      'Preparing your application…',
                      textAlign: TextAlign.center,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 20),
                      HireDNotice(_error!, error: true),
                      TextButton(
                        onPressed: _busy ? null : _load,
                        child: const Text('Try again'),
                      ),
                    ],
                  ] else ...[
                    if (_application?.status == 'corrections_requested')
                      HireDNotice(
                        _application?.reviewReason ??
                            'Please correct the requested details and submit again.',
                      ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: HireDBadge(
                        'Mobile verified',
                        color: HireDStyle.success,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const HireDSteps(
                      labels: ['Details', 'Mobile', 'Documents'],
                      current: 2,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Documents · ${_step + 1} of 3 · ${const ['Licence', 'Identity', 'Review'][_step]}',
                      style: const TextStyle(
                        color: HireDStyle.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      titles[_step],
                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.7,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      subtitles[_step],
                      style: const TextStyle(
                        color: HireDStyle.muted,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 26),
                    if (_step == 0) _licenceStep(),
                    if (_step == 1) _identityStep(),
                    if (_step == 2) _reviewStep(),
                    if (_error != null) ...[
                      const SizedBox(height: 18),
                      HireDNotice(
                        _error!,
                        key: const Key('onboarding-error'),
                        error: true,
                      ),
                    ],
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: Key(
                          _step == 2
                              ? 'submit-driver-application'
                              : 'onboarding-next',
                        ),
                        onPressed: _busy
                            ? null
                            : () {
                                FocusScope.of(context).unfocus();
                                if (_step == 0 && _validateLicence()) {
                                  _saveAndContinue(1);
                                } else if (_step == 1 && _validateIdentity()) {
                                  _go(2);
                                } else if (_step == 2) {
                                  _submit();
                                }
                              },
                        child: Text(
                          _busy
                              ? 'Saving…'
                              : _step == 2
                              ? 'Submit application'
                              : _step == 0
                              ? 'Continue to identity'
                              : 'Review application',
                        ),
                      ),
                    ),
                    if (_step > 0)
                      Center(
                        child: TextButton(
                          onPressed: _busy ? null : () => _go(_step - 1),
                          child: const Text('Go back'),
                        ),
                      ),
                    TextButton(
                      onPressed: _busy ? null : _delete,
                      child: const Text('Delete application'),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Photos upload privately. Continue saves your details so you can return later. Enter your Aadhaar number only when submitting.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: HireDStyle.muted,
                        fontSize: 11,
                        height: 1.6,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
