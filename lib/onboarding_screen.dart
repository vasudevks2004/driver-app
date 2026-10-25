import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand.dart';
import 'design.dart';
import 'identity_auth.dart';
import 'onboarding.dart';

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
    if (state == AppLifecycleState.resumed && _digiPending && !_busy)
      _refresh();
    // Do not leave a revealed identity number on the app switcher's next frame.
    if (state == AppLifecycleState.inactive && _showAadhaar && mounted)
      setState(() => _showAadhaar = false);
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
      if (mounted)
        setState(
          () => _error = e is DriverAuthException
              ? e.message
              : 'We could not complete that step. Please retry.',
        );
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
    if (mounted)
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
  });

  Future<void> _refresh() => _run(() async {
    final application = await widget.service.status(widget.session.accessToken);
    if (mounted)
      setState(() {
        _application = application;
        _digiPending = application.digiLockerStatus == 'pending';
      });
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
    if (widget.pickImage != null) {
      bytes = await widget.pickImage!(kind, source);
    } else {
      try {
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
          if (await image.length() > maxDriverImageBytes)
            throw const DriverAuthException(
              'Choose an image smaller than 5 MB.',
            );
          bytes = await image.readAsBytes();
        }
      } on PlatformException {
        throw const DriverAuthException(
          'Camera or photo access is unavailable. Allow access in your device settings and try again.',
        );
      }
    }
    if (bytes == null) return;
    final application = await widget.service.upload(
      widget.session.accessToken,
      kind,
      bytes,
    );
    if (mounted)
      setState(() {
        _application = application;
        if (kind == 'selfie') _selfie = bytes;
      });
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
      if (!opened)
        throw const DriverAuthException(
          'Could not open DigiLocker. Please try again.',
        );
      if (mounted) setState(() => _digiPending = true);
    });
  }

  Future<void> _date(bool birth) async {
    final now = DateUtils.dateOnly(DateTime.now());
    final selected = await showDatePicker(
      context: context,
      initialDate: birth
          ? (_birthDate ?? DateTime(now.year - 25, now.month, now.day))
          : (_expiry ?? now.add(const Duration(days: 365))),
      firstDate: birth ? DateTime(1900) : now,
      lastDate: birth
          ? now.subtract(const Duration(days: 1))
          : DateTime(now.year + 40),
    );
    if (selected != null && mounted)
      setState(() {
        if (birth) {
          _birthDate = selected;
        } else {
          _expiry = selected;
        }
      });
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
      if (mounted)
        setState(() {
          _application = result;
          _selfie = null;
          _aadhaar.clear();
          _showAadhaar = false;
        });
    });
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
    ),
  );

  Widget _photoTile(
    String title,
    String subtitle,
    bool uploaded,
    VoidCallback action, {
    required Key key,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: uploaded ? const Color(0xFFBCE1D2) : HireDStyle.line,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: key,
        minVerticalPadding: 14,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: uploaded ? const Color(0xFFEDF8F2) : HireDStyle.tint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            uploaded ? Icons.check_rounded : Icons.add_photo_alternate_outlined,
            color: uploaded ? HireDStyle.success : HireDStyle.primary,
            size: 22,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            uploaded ? 'Uploaded · tap to replace' : subtitle,
            style: const TextStyle(
              color: HireDStyle.muted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: HireDStyle.muted,
          size: 20,
        ),
        onTap: _busy || _application == null ? null : action,
      ),
    ),
  );

  Widget _dateField(String title, DateTime? value, VoidCallback action) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton.icon(
          onPressed: _busy ? null : action,
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              value == null
                  ? title
                  : '$title: ${DateFormat('dd MMM yyyy').format(value)}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 54),
            backgroundColor: Colors.white,
          ),
        ),
      );

  Widget _licenceStep() {
    final app = _application;
    final received = app?.hasDigiLockerDocument ?? false;
    return Form(
      key: _licenceForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Full name'),
          TextFormField(
            controller: _name,
            enabled: !_busy,
            maxLength: 100,
            decoration: const InputDecoration(counterText: ''),
            validator: (v) =>
                (v?.trim().length ?? 0) >= 2 ? null : 'Enter your full name',
          ),
          const SizedBox(height: 16),
          _label('City'),
          TextFormField(
            controller: _city,
            enabled: !_busy,
            maxLength: 80,
            decoration: const InputDecoration(counterText: ''),
            validator: (v) =>
                (v?.trim().length ?? 0) >= 2 ? null : 'Enter your city',
          ),
          const SizedBox(height: 16),
          _label('Driving licence number'),
          TextFormField(
            key: const Key('licence-number'),
            controller: _licence,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            maxLength: 30,
            decoration: const InputDecoration(
              hintText: 'As shown on your licence',
              counterText: '',
              prefixIcon: Icon(Icons.badge_outlined, size: 20),
            ),
            validator: (value) => validLicenceNumber(value ?? '')
                ? null
                : 'Enter a valid driving licence number',
          ),
          const SizedBox(height: 20),
          _dateField('Date of birth', _birthDate, () => _date(true)),
          _dateField('Licence expiry', _expiry, () => _date(false)),
          const SizedBox(height: 8),
          _label('Vehicle class'),
          DropdownButtonFormField<String>(
            value: _vehicleClass,
            isExpanded: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.directions_car_outlined, size: 20),
            ),
            items: const [
              DropdownMenuItem(
                value: 'LMV',
                child: Text('Light motor vehicle'),
              ),
              DropdownMenuItem(
                value: 'TRANSPORT',
                child: Text('Transport vehicle'),
              ),
              DropdownMenuItem(value: 'BOTH', child: Text('Both classes')),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _vehicleClass = value!),
          ),
          const SizedBox(height: 24),
          _label('Licence photos'),
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text(
              'Keep all four corners and the text clearly visible.',
              style: TextStyle(
                color: HireDStyle.muted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
          _photoTile(
            'Licence · front',
            'Take a photo or choose from photos',
            app?.frontUploaded ?? false,
            () => _chooseDocument('licence_front'),
            key: const Key('onboarding-licence-front'),
          ),
          _photoTile(
            'Licence · back',
            'JPG or PNG · up to 5 MB each',
            app?.backUploaded ?? false,
            () => _chooseDocument('licence_back'),
            key: const Key('onboarding-licence-back'),
          ),
          const SizedBox(height: 4),
          HireDCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.account_balance_outlined,
                      color: HireDStyle.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        received
                            ? 'Licence received from DigiLocker'
                            : 'Have your licence in DigiLocker?',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  received
                      ? 'Issued licence received. HireD review is pending.'
                      : 'Share an issued licence instead of uploading both licence photos.',
                  style: const TextStyle(
                    color: HireDStyle.muted,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
                if (!received)
                  TextButton(
                    key: const Key('connect-digilocker'),
                    onPressed: _busy || app == null ? null : _connectDigiLocker,
                    child: const Text('Connect DigiLocker'),
                  ),
                if (_digiPending || app?.digiLockerStatus == 'failed')
                  TextButton(
                    onPressed: _busy ? null : _refresh,
                    child: const Text('Check DigiLocker connection'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _identityStep() => Form(
    key: _identityForm,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Aadhaar number'),
        TextFormField(
          key: const Key('aadhaar-number'),
          controller: _aadhaar,
          enabled: !_busy,
          obscureText: !_showAadhaar,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: TextInputType.number,
          maxLength: 12,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(12),
          ],
          decoration: InputDecoration(
            hintText: 'Your 12-digit Aadhaar number',
            counterText: '',
            prefixIcon: const Icon(Icons.credit_card_outlined, size: 20),
            suffixIcon: IconButton(
              tooltip: _showAadhaar
                  ? 'Hide Aadhaar number'
                  : 'Show Aadhaar number',
              onPressed: _busy
                  ? null
                  : () => setState(() => _showAadhaar = !_showAadhaar),
              icon: Icon(
                _showAadhaar
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
              ),
            ),
          ),
          validator: (value) => validAadhaarNumber(value ?? '')
              ? null
              : 'Enter a valid 12-digit Aadhaar number',
        ),
        const SizedBox(height: 16),
        _photoTile(
          'Aadhaar card photo',
          'Front side · JPG or PNG · up to 5 MB',
          _application?.aadhaarUploaded ?? false,
          () => _chooseDocument('aadhaar'),
          key: const Key('onboarding-aadhaar'),
        ),
        const HireDNotice(
          'Your number is hidden on the review screen. A masked Aadhaar photo is welcome; keep your name, photo and last four digits readable.',
        ),
        const SizedBox(height: 16),
        _photoTile(
          'PAN card',
          'JPG or PNG · up to 5 MB',
          _application?.panUploaded ?? false,
          () => _chooseDocument('pan'),
          key: const Key('onboarding-pan'),
        ),
        _photoTile(
          'Police clearance',
          'Current PCC · JPG or PNG · up to 5 MB',
          _application?.pccUploaded ?? false,
          () => _chooseDocument('pcc'),
          key: const Key('onboarding-pcc'),
        ),
        const SizedBox(height: 28),
        _label('Your driver photo'),
        HireDCard(
          child: Column(
            children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: HireDStyle.tint,
                backgroundImage: _selfie == null ? null : MemoryImage(_selfie!),
                child: _selfie == null
                    ? Icon(
                        _application?.selfieUploaded == true
                            ? Icons.check_rounded
                            : Icons.person_outline,
                        color: HireDStyle.primary,
                        size: 36,
                      )
                    : null,
              ),
              const SizedBox(height: 14),
              Text(
                _application?.selfieUploaded == true
                    ? 'Looking good. Photo uploaded.'
                    : 'Put a face to your profile.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Face the camera in good light. This becomes your driver avatar.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: HireDStyle.muted,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                key: const Key('onboarding-selfie'),
                onPressed: _busy
                    ? null
                    : () => _pick('selfie', ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: Text(
                  _application?.selfieUploaded == true
                      ? 'Retake selfie'
                      : 'Take a selfie',
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _reviewRow(String label, String value, {bool checked = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (checked) ...[
              const Icon(
                Icons.check_circle_outline,
                size: 18,
                color: HireDStyle.success,
              ),
              const SizedBox(width: 9),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: HireDStyle.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _reviewStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      HireDCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Driver details',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _go(0),
                  child: const Text('Edit'),
                ),
              ],
            ),
            _reviewRow('Full name', _name.text),
            _reviewRow('City', _city.text),
            const Divider(height: 24),
            _reviewRow('Driving licence', _licence.text.toUpperCase()),
            _reviewRow(
              'Licence valid until',
              DateFormat('dd MMM yyyy').format(_expiry!),
            ),
            _reviewRow(
              'Aadhaar number',
              maskedAadhaar(normalizeAadhaarNumber(_aadhaar.text).substring(8)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      HireDCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Documents',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _go(1),
                  child: const Text('Edit'),
                ),
              ],
            ),
            _reviewRow(
              'Driving licence',
              _application?.hasDigiLockerDocument == true
                  ? 'Received from DigiLocker'
                  : 'Front and back uploaded',
              checked: true,
            ),
            _reviewRow('Aadhaar card', 'Photo uploaded', checked: true),
            _reviewRow(
              'PAN and police clearance',
              'Photos uploaded',
              checked: true,
            ),
            _reviewRow('Driver avatar', 'Selfie uploaded', checked: true),
          ],
        ),
      ),
      const SizedBox(height: 18),
      CheckboxListTile(
        key: const Key('onboarding-consent'),
        value: _consent,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: _busy
            ? null
            : (value) => setState(() => _consent = value ?? false),
        title: const Text(
          'I agree to HireD reviewing my licence, Aadhaar number and photo for driver onboarding, and using my selfie as my driver profile photo.',
          style: TextStyle(fontSize: 12, height: 1.6, color: HireDStyle.muted),
        ),
      ),
      const SizedBox(height: 12),
      const HireDNotice(
        'After you submit, HireD will review your details before activating your driver profile.',
        icon: Icons.fact_check_outlined,
      ),
    ],
  );

  Widget _receipt() => Column(
    children: [
      const SizedBox(height: 28),
      Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFFEDF8F2),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.task_alt_rounded,
          size: 52,
          color: HireDStyle.success,
        ),
      ),
      const SizedBox(height: 28),
      Text(
        widget.service.isPreview
            ? 'Preview complete.'
            : _application?.status == 'approved'
            ? 'You’re approved.'
            : _application?.status == 'rejected'
            ? 'Application reviewed.'
            : 'You’re on your way.',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -.6,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        widget.service.isPreview
            ? 'Nothing was sent to HireD. Return to sign-in to test the dashboard.'
            : _application?.status == 'approved'
            ? 'Your driver access is enabled. Sign in with the same verified mobile number.'
            : _application?.reviewReason ??
                  'Application submitted. HireD will review your documents before activating your profile. Check your status here after review.',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: HireDStyle.muted,
          fontSize: 14,
          height: 1.7,
        ),
      ),
      const SizedBox(height: 28),
      HireDCard(
        child: Column(
          children: [
            HireDBadge(
              _application?.status == 'approved'
                  ? 'Approved'
                  : _application?.status == 'rejected'
                  ? 'Not approved'
                  : 'Review pending',
              color: const Color(0xFF946200),
            ),
            const SizedBox(height: 16),
            const Text(
              'Application reference',
              style: TextStyle(color: HireDStyle.muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _application!.id,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            if (_application?.aadhaarLastFour != null) ...[
              const SizedBox(height: 16),
              Text(
                'Aadhaar ${maskedAadhaar(_application!.aadhaarLastFour!)}',
                style: const TextStyle(color: HireDStyle.muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 28),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _busy ? null : widget.onClose,
          child: const Text('Back to sign in'),
        ),
      ),
    ],
  );

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
                    HireDSteps(
                      labels: const ['Licence', 'Identity', 'Review'],
                      current: _step,
                    ),
                    const SizedBox(height: 30),
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
                                if (_step == 0 && _validateLicence())
                                  _saveAndContinue(1);
                                else if (_step == 1 && _validateIdentity())
                                  _go(2);
                                else if (_step == 2)
                                  _submit();
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
