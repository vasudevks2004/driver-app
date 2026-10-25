import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api.dart';
import '../../design.dart';
import '../../driver_widgets.dart';
import '../workspace/controller.dart';
import '../workspace/ui.dart';
import 'duty.dart';

class DutyDetailPage extends StatefulWidget {
  const DutyDetailPage({super.key, required this.state});
  final DriverWorkspace state;
  @override
  State<DutyDetailPage> createState() => _DutyDetailPageState();
}

class _DutyDetailPageState extends State<DutyDetailPage> {
  final description = TextEditingController(),
      amount = TextEditingController(),
      code = TextEditingController();
  DriverWorkspace get state => widget.state;
  @override
  void dispose() {
    description.dispose();
    amount.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> _updated(String id) async {
    await state.select(id, open: false);
    await Future.wait([state.loadDuties(), state.loadWallet()]);
  }

  void _demo(DriverDuty d, Map<String, dynamic> changes) =>
      state.updateDemoDuty(DriverDuty.fromJson({...d.toJson(), ...changes}));
  Future<void> _selfie(DriverDuty duty) async {
    await state.perform(() async {
      final XFile? photo;
      try {
        photo = await ImagePicker().pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.front,
          imageQuality: 80,
          maxWidth: 1600,
          maxHeight: 1600,
          requestFullMetadata: false,
        );
      } on PlatformException {
        throw const ApiException(
          'Camera access is unavailable. Allow access in device settings and try again.',
          400,
        );
      }
      if (photo == null) return;
      if (await photo.length() > driverUploadLimit)
        throw const ApiException('Choose a photo up to 5 MB.', 400);
      if (state.isDemo) {
        _demo(duty, {'selfie': true});
        return;
      }
      await state.auth.upload('/trips/${duty.id}/selfie', photo.path);
      await _updated(duty.id);
    });
  }

  Future<void> _expense(DriverDuty duty, {bool none = false}) async {
    final title = none ? 'No expenses' : description.text.trim(),
        value = none ? '0' : amount.text.trim();
    await state.perform(() async {
      if (title.isEmpty ||
          title.length > 300 ||
          !RegExp(r'^\d{1,12}(\.\d{1,2})?$').hasMatch(value) ||
          num.tryParse(value) == null)
        throw const ApiException(
          'Enter a description and a valid amount with up to two decimal places.',
          400,
        );
      if (state.isDemo) {
        _demo(duty, {
          'expensesSubmitted': true,
          'noExpenses': none,
          'expenses': none
              ? []
              : [
                  ...duty.expenses.map((x) => x.toJson()),
                  {'description': title, 'amount': num.parse(value)},
                ],
        });
      } else {
        try {
          await state.repository.expense(duty.id, title, value);
        } on ReconciledOperation catch (error) {
          if (error.previousCommitted) {
            description.clear();
            amount.clear();
            await _updated(duty.id);
          }
          rethrow;
        }
        await _updated(duty.id);
      }
      description.clear();
      amount.clear();
    });
  }

  Future<void> _launch(Uri uri) async {
    await state.perform(() async {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication))
        throw const ApiException(
          'Could not open that action on this device.',
          400,
        );
    });
  }

  Widget _card(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: HireDCard(child: child),
  );
  Widget _action(
    String label,
    VoidCallback action, {
    bool enabled = true,
    bool outlined = false,
  }) => SizedBox(
    width: double.infinity,
    child: outlined
        ? OutlinedButton(
            onPressed: state.busy || !enabled ? null : action,
            child: Text(label),
          )
        : FilledButton(
            onPressed: state.busy || !enabled ? null : action,
            child: Text(label),
          ),
  );
  @override
  Widget build(BuildContext context) {
    final duty = state.selected.value;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: workspacePadding,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        ResourceStatus(
          resource: state.selected,
          retry: () => state.refresh(),
          label: 'duty',
        ),
        if (duty != null) ...[
          pageHeading(
            'Duty #${shortReference(duty.id)}',
            'Your assignment details and next steps.',
          ),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HireDBadge(
                  dutyStatus(duty.toJson()),
                  color: duty.complete
                      ? HireDStyle.success
                      : HireDStyle.primary,
                ),
                const SizedBox(height: 24),
                DutyRoute(pickup: duty.pickup, destination: duty.destination),
                const Divider(height: 32),
                Text(
                  duty.company,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (duty.service.isNotEmpty)
                  Text(
                    duty.service,
                    style: const TextStyle(
                      color: HireDStyle.muted,
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  dutySchedule(duty.toJson()),
                  style: const TextStyle(color: HireDStyle.muted, fontSize: 12),
                ),
                if (duty.instructions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    duty.instructions,
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'The partner provides the vehicle.',
                  style: TextStyle(fontSize: 12, color: HireDStyle.muted),
                ),
              ],
            ),
          ),
          if (duty.active) ...[
            _action(
              'Directions to pickup',
              () => _launch(
                Uri.https('www.google.com', '/maps/dir/', {
                  'api': '1',
                  'destination':
                      duty.pickupLat != null && duty.pickupLng != null
                      ? '${duty.pickupLat},${duty.pickupLng}'
                      : duty.pickup,
                  'travelmode': 'driving',
                }),
              ),
              outlined: true,
            ),
            const SizedBox(height: 10),
            if (duty.contactPhone != null &&
                RegExp(r'^[+0-9 ()-]{7,25}$').hasMatch(duty.contactPhone!)) ...[
              _action(
                'Call ${duty.contactName?.isNotEmpty == true ? duty.contactName : 'partner'}',
                () => _launch(
                  Uri(
                    scheme: 'tel',
                    path: duty.contactPhone!.replaceAll(RegExp(r'[^+0-9]'), ''),
                  ),
                ),
                outlined: true,
              ),
              const SizedBox(height: 16),
            ],
          ],
          if (duty.active) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '1. Your duty selfie',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    duty.selfie
                        ? 'Selfie uploaded for this assignment.'
                        : 'Take a selfie for this assignment before starting.',
                    style: const TextStyle(
                      color: HireDStyle.muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _action(
                    duty.selfie ? 'Retake selfie' : 'Take selfie',
                    () => _selfie(duty),
                    outlined: true,
                  ),
                ],
              ),
            ),
          ],
          if (duty.status == DutyStatus.assigned) ...[
            if (!duty.selfie)
              const HireDNotice(
                'Upload your duty selfie to enable Start duty.',
              ),
            const SizedBox(height: 12),
            _action(
              'Start driver duty',
              () => state.perform(() async {
                if (state.isDemo) {
                  _demo(duty, {'status': 'Ongoing'});
                } else {
                  await state.repository.start(duty.id);
                  await _updated(duty.id);
                }
              }),
              enabled: duty.selfie,
            ),
          ],
          if (duty.status == DutyStatus.ongoing) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '2. Add expenses',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final expense in duty.expenses)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Expanded(child: Text(expense.description)),
                          const SizedBox(width: 8),
                          Text(driverMoney(expense.amount)),
                        ],
                      ),
                    ),
                  if (duty.noExpenses)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: HireDBadge(
                        'No expenses recorded',
                        color: HireDStyle.success,
                      ),
                    ),
                  TextField(
                    controller: description,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Description (toll, parking…)',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Amount in ₹'),
                  ),
                  const SizedBox(height: 14),
                  _action('Log expense', () => _expense(duty)),
                  if (duty.expenses.isEmpty) ...[
                    const SizedBox(height: 10),
                    _action(
                      'No expenses for this duty',
                      () => _expense(duty, none: true),
                      outlined: true,
                    ),
                  ],
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '3. Complete your duty',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.isDemo
                        ? 'Demo completion code: 482901'
                        : 'Get the six-digit completion code from the business partner.',
                    style: const TextStyle(
                      color: HireDStyle.muted,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                  if (!duty.selfie || !duty.expensesSubmitted)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: HireDNotice(
                        'Upload your duty selfie and record expenses, or choose No expenses, before completing this duty.',
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('completion-code'),
                    controller: code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Six-digit partner code',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _action(
                    'Verify & complete duty',
                    () => state.perform(() async {
                      if (!RegExp(r'^[0-9]{6}$').hasMatch(code.text))
                        throw const ApiException(
                          'Enter the six-digit partner code.',
                          400,
                        );
                      if (state.isDemo) {
                        if (code.text != '482901')
                          throw const ApiException(
                            'Use the six-digit demo code shown above.',
                            400,
                          );
                        _demo(duty, {'status': 'Closed'});
                      } else {
                        await state.repository.close(duty.id, code.text);
                        await _updated(duty.id);
                      }
                      code.clear();
                      state.navigate(2);
                    }),
                    enabled: duty.selfie && duty.expensesSubmitted,
                  ),
                ],
              ),
            ),
          ],
          if (duty.complete)
            _card(
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: HireDStyle.success,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Duty completed. Confirmed earnings are shown in your wallet.',
                      style: TextStyle(
                        color: HireDStyle.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (duty.status == DutyStatus.unavailable)
            const HireDNotice(
              'This duty cannot be changed. Refresh or contact HireD operations.',
            ),
        ],
        const SizedBox(height: 16),
        _action('Back to duties', () => state.navigate(1), outlined: true),
      ],
    );
  }
}
