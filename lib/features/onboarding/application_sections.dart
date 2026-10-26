part of '../../onboarding_screen.dart';

extension _ApplicationSections on _DriverOnboardingScreenState {
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
            initialValue: _vehicleClass,
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
                : (value) => updateView(() => _vehicleClass = value!),
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
                  : () => updateView(() => _showAadhaar = !_showAadhaar),
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
            : (value) => updateView(() => _consent = value ?? false),
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
}
