import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand.dart';
import 'identity_auth.dart';
import 'onboarding.dart';

class DriverOnboardingScreen extends StatefulWidget {
  const DriverOnboardingScreen({super.key, required this.service, required this.session,
    required this.fullName, required this.city, required this.onClose, this.pickImage, this.openBrowser});
  final DriverOnboarding service;
  final IdentitySession session;
  final String fullName;
  final String city;
  final Future<void> Function() onClose;
  final Future<Uint8List?> Function(String kind, ImageSource source)? pickImage;
  final Future<bool> Function(Uri uri)? openBrowser;

  @override
  State<DriverOnboardingScreen> createState() => _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState extends State<DriverOnboardingScreen> with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _licence = TextEditingController();
  DriverApplication? _application;
  DateTime? _birthDate;
  DateTime? _expiry;
  String _vehicleClass = 'LMV';
  Uint8List? _selfie;
  bool _busy = false;
  bool _consent = false;
  bool _digiPending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _licence.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _digiPending && !_busy) _refresh();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try { await action(); }
    catch (e) { if (mounted) setState(() => _error = e is DriverAuthException ? e.message : 'We could not complete that step. Please retry.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _load() => _run(() async {
    final application = await widget.service.open(widget.session.accessToken, name: widget.fullName, city: widget.city);
    if (mounted) setState(() => _application = application);
  });

  Future<void> _refresh() => _run(() async {
    final application = await widget.service.status(widget.session.accessToken);
    if (mounted) setState(() { _application = application; _digiPending = application.digiLockerStatus == 'pending'; });
  });

  Future<void> _pick(String kind, ImageSource source) => _run(() async {
    Uint8List? bytes;
    if (widget.pickImage != null) {
      bytes = await widget.pickImage!(kind, source);
    } else {
      try {
        final image = await ImagePicker().pickImage(source: source,
          preferredCameraDevice: kind == 'selfie' ? CameraDevice.front : CameraDevice.rear,
          maxWidth: 1600, maxHeight: 1600, imageQuality: 85, requestFullMetadata: false);
        if (image != null) {
          if (await image.length() > maxDriverImageBytes) throw const DriverAuthException('Choose an image smaller than 6 MB.');
          bytes = await image.readAsBytes();
        }
      } on PlatformException {
        throw const DriverAuthException('Camera or photo access is unavailable. Allow access in your device settings and try again.');
      }
    }
    if (bytes == null) return;
    final application = await widget.service.upload(widget.session.accessToken, kind, bytes);
    if (mounted) setState(() { _application = application; if (kind == 'selfie') _selfie = bytes; });
  });

  Future<void> _chooseDocument(String kind) async {
    final source = await showModalBottomSheet<ImageSource>(context: context,
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(context, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from photos'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
      ])));
    if (source != null && mounted) await _pick(kind, source);
  }

  Future<void> _connectDigiLocker() async {
    final consent = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Share your driving licence?'),
      content: const Text('DigiLocker will ask for your permission to share an issued driving licence with HireD for driver onboarding. You sign in on the government website. You can cancel and upload licence photos instead.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue to DigiLocker'))],
    ));
    if (consent != true || !mounted) return;
    await _run(() async {
      final uri = await widget.service.startDigiLocker(widget.session.accessToken);
      final opened = await (widget.openBrowser?.call(uri) ?? launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!opened) throw const DriverAuthException('Could not open DigiLocker. Please try again.');
      if (mounted) setState(() => _digiPending = true);
    });
  }

  Future<void> _date(bool birth) async {
    final now = DateUtils.dateOnly(DateTime.now());
    final selected = await showDatePicker(context: context,
      initialDate: birth ? (_birthDate ?? DateTime(now.year - 25, now.month, now.day)) : (_expiry ?? now.add(const Duration(days: 365))),
      firstDate: birth ? DateTime(1900) : now,
      lastDate: birth ? now.subtract(const Duration(days: 1)) : DateTime(now.year + 40));
    if (selected != null && mounted) setState(() { if (birth) { _birthDate = selected; } else { _expiry = selected; } });
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final application = _application;
    if (_birthDate == null || _expiry == null) {
      setState(() => _error = 'Add your date of birth and licence expiry date.'); return;
    }
    if (application == null || !application.selfieUploaded ||
        (!application.hasDigiLockerDocument && (!application.frontUploaded || !application.backUploaded))) {
      setState(() => _error = 'Add your selfie and both licence photos, or share your licence through DigiLocker.'); return;
    }
    if (!_consent) { setState(() => _error = 'Please agree to the document review and profile photo use.'); return; }
    await _run(() async {
      final result = await widget.service.submit(widget.session.accessToken,
        licenceNumber: _licence.text, birthDate: _birthDate!, licenceExpiry: _expiry!, vehicleClass: _vehicleClass);
      if (mounted) setState(() { _application = result; _selfie = null; });
    });
  }

  Widget _photoTile(String title, String subtitle, bool uploaded, VoidCallback action, {Key? key}) => Card(
    elevation: 0, margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(key: key, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: Icon(uploaded ? Icons.check_circle : Icons.add_photo_alternate_outlined,
        color: uploaded ? Colors.teal : const Color(0xFF5055F7)),
      title: Text(title), subtitle: Text(uploaded ? 'Uploaded · tap to replace' : subtitle),
      trailing: const Icon(Icons.chevron_right), onTap: _busy ? null : action));

  Widget _dateField(String title, DateTime? value, VoidCallback action) => OutlinedButton.icon(
    onPressed: _busy ? null : action, icon: const Icon(Icons.calendar_today_outlined, size: 18),
    label: Align(alignment: Alignment.centerLeft, child: Text(value == null ? title : '$title: ${DateFormat('dd MMM yyyy').format(value)}')),
    style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)));

  @override
  Widget build(BuildContext context) {
    final app = _application;
    final received = app?.hasDigiLockerDocument ?? false;
    final submitted = app?.submitted ?? false;
    return PopScope(canPop: false, child: Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const HireDLogo(width: 115),
        actions: [TextButton(onPressed: _busy ? null : widget.onClose, child: const Text('Sign out'))]),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 16),
          if (submitted) ...[
            const Icon(Icons.task_alt, color: Colors.teal, size: 66), const SizedBox(height: 20),
            Text('Application submitted.', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            const Text('HireD will review your licence and selfie before activating your driver profile. You can sign in once your profile is approved.'),
            const SizedBox(height: 16), SelectableText('Application reference: ${app!.id}'),
            const SizedBox(height: 24), FilledButton(onPressed: _busy ? null : widget.onClose, child: const Text('Back to sign in')),
          ] else Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Complete your driver profile.', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 9),
            Text('${widget.fullName} · ${widget.city}', style: const TextStyle(color: Color(0xFF687083))),
            const SizedBox(height: 8),
            const Text('Your mobile is verified. Add your licence and a clear selfie for your driver avatar.'),
            const SizedBox(height: 22),
            Center(child: CircleAvatar(radius: 45,
              backgroundImage: _selfie == null ? null : MemoryImage(_selfie!),
              child: _selfie == null ? Icon(app?.selfieUploaded == true ? Icons.check : Icons.person_outline, size: 44) : null)),
            const SizedBox(height: 12),
            _photoTile('Selfie for your avatar', 'Take a clear photo of your face', app?.selfieUploaded ?? false,
              () => _pick('selfie', ImageSource.camera), key: const Key('onboarding-selfie')),
            const Text('Used for your driver profile photo and manual review.', style: TextStyle(fontSize: 12, color: Color(0xFF687083))),
            const SizedBox(height: 22),
            TextFormField(key: const Key('licence-number'), controller: _licence, enabled: !_busy,
              textCapitalization: TextCapitalization.characters, maxLength: 30,
              decoration: const InputDecoration(labelText: 'Driving licence number', hintText: 'As printed on your licence', prefixIcon: Icon(Icons.badge_outlined)),
              validator: (v) => validLicenceNumber(v ?? '') ? null : 'Enter a valid driving licence number'),
            const SizedBox(height: 12), _dateField('Date of birth', _birthDate, () => _date(true)),
            const SizedBox(height: 12), _dateField('Licence expiry', _expiry, () => _date(false)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(value: _vehicleClass, isExpanded: true,
              decoration: const InputDecoration(labelText: 'Vehicle class on your licence'),
              items: const [DropdownMenuItem(value: 'LMV', child: Text('LMV — light motor vehicle')),
                DropdownMenuItem(value: 'TRANSPORT', child: Text('Transport / commercial vehicle')),
                DropdownMenuItem(value: 'BOTH', child: Text('LMV and transport'))],
              onChanged: _busy ? null : (v) => setState(() => _vehicleClass = v!)),
            const SizedBox(height: 24),
            Card(elevation: 0, color: const Color(0xFFEEEFFF), child: Padding(padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [Icon(Icons.account_balance_outlined), SizedBox(width: 10), Text('DigiLocker', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))]),
                const SizedBox(height: 10),
                Text(received ? 'Issued licence received. HireD review is pending.' : 'Share your issued driving licence securely, or upload photos below.'),
                if (_digiPending) const Padding(padding: EdgeInsets.only(top: 10), child: Text('Finish in your browser, return here, then check the connection.')),
                if (app?.digiLockerStatus == 'failed') const Padding(padding: EdgeInsets.only(top: 10), child: Text('The connection did not finish. Try again or upload licence photos.')),
                const SizedBox(height: 12),
                OutlinedButton.icon(key: const Key('connect-digilocker'), onPressed: _busy || app == null ? null : _connectDigiLocker,
                  icon: Icon(received ? Icons.check_circle_outline : Icons.lock_outline),
                  label: Text(received ? 'Reconnect DigiLocker' : 'Connect DigiLocker')),
                if (_digiPending) TextButton(onPressed: _busy ? null : _refresh, child: const Text('Check DigiLocker connection')),
              ]))),
            const SizedBox(height: 14),
            _photoTile('Licence · front', received ? 'Optional when shared through DigiLocker' : 'JPG or PNG · up to 6 MB', app?.frontUploaded ?? false,
              () => _chooseDocument('licence_front'), key: const Key('onboarding-licence-front')),
            _photoTile('Licence · back', received ? 'Optional when shared through DigiLocker' : 'JPG or PNG · up to 6 MB', app?.backUploaded ?? false,
              () => _chooseDocument('licence_back'), key: const Key('onboarding-licence-back')),
            CheckboxListTile(key: const Key('onboarding-consent'), contentPadding: EdgeInsets.zero,
              value: _consent, controlAffinity: ListTileControlAffinity.leading,
              onChanged: _busy ? null : (v) => setState(() => _consent = v ?? false),
              title: const Text('I agree to HireD using these documents for driver review and my selfie as my driver profile photo.', style: TextStyle(fontSize: 13))),
            const Text('Documents are private. Submitting an application does not activate your driver account.', style: TextStyle(fontSize: 12, color: Color(0xFF687083))),
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: FilledButton(key: const Key('submit-driver-application'),
              onPressed: _busy || app == null ? null : _submit, child: const Text('Submit driver application'))),
          ])),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 18), child: Semantics(liveRegion: true,
            child: Text(_error!, key: const Key('onboarding-error'), style: const TextStyle(color: Colors.red)))),
          if (app == null && !_busy) TextButton(onPressed: _load, child: const Text('Retry loading application')),
          const SizedBox(height: 24),
        ])),
      ),
    ));
  }
}
