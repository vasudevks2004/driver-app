import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../api.dart';
import '../../design.dart';
import '../workspace/controller.dart';
import '../workspace/ui.dart';

class DriverProfilePage extends StatelessWidget {
  const DriverProfilePage({
    super.key,
    required this.state,
    required this.signOut,
    this.avatar,
  });
  final DriverWorkspace state;
  final VoidCallback signOut;
  final Uint8List? avatar;
  Future<void> _upload(BuildContext context, String kind) async {
    final chosen = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: false,
    );
    final file = chosen?.files.single;
    if (file?.path == null) return;
    if (file!.size > driverUploadLimit) {
      await state.perform(() async {
        throw const ApiException('Choose a file up to 5 MB.', 400);
      });
      return;
    }
    String? expires;
    if (kind == 'license' && context.mounted) {
      final now = DateUtils.dateOnly(DateTime.now());
      final date = await showDatePicker(
        context: context,
        helpText: 'Licence expiry',
        firstDate: now,
        lastDate: DateTime(now.year + 40),
        initialDate: now.add(const Duration(days: 365)),
      );
      if (date == null) return;
      expires = DateFormat('yyyy-MM-dd').format(date);
    }
    await state.perform(() async {
      if (!state.isDemo) {
        await state.auth.upload(
          '/drivers/me/documents/$kind',
          file.path!,
          expiresOn: expires,
        );
      }
      await state.loadProfile();
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: workspacePadding,
    children: [
      pageHeading('Your profile', 'Your details. Your schedule.'),
      ResourceStatus(
        resource: state.profile,
        retry: () => state.loadProfile(),
        label: 'profile',
      ),
      HireDCard(
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: HireDStyle.tint,
              backgroundImage: avatar == null ? null : MemoryImage(avatar!),
              child: avatar == null
                  ? const Icon(
                      Icons.person_outline,
                      color: HireDStyle.primary,
                      size: 30,
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.name,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    state.isDemo
                        ? 'Demo driver profile'
                        : 'HireD driver partner',
                    style: const TextStyle(
                      color: HireDStyle.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 28, bottom: 16),
        child: Text(
          'Availability',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      HireDCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Planning a day off?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Next 14 days · tap a date to mark it unavailable. Tap again to make it available.',
              style: TextStyle(
                fontSize: 12,
                color: HireDStyle.muted,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: MediaQuery.textScalerOf(context).scale(100),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 14,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final date = DateTime.now().add(Duration(days: index)),
                      key = DateFormat('yyyy-MM-dd').format(date);
                  final blocked = state.unavailable.contains(key);
                  return Semantics(
                    button: true,
                    selected: blocked,
                    label:
                        '${DateFormat('d MMMM').format(date)}, ${blocked ? 'unavailable' : 'available'}',
                    child: ExcludeSemantics(
                      child: Material(
                        color: blocked
                            ? const Color(0xFFFFF1EE)
                            : HireDStyle.canvas,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: HireDStyle.line),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: state.busy
                              ? null
                              : () => state.perform(() async {
                                  final dates = state.unavailable;
                                  if (blocked) {
                                    dates.remove(key);
                                  } else {
                                    dates.add(key);
                                  }
                                  await state.setAvailability(
                                    state.online,
                                    dates,
                                  );
                                }),
                          child: SizedBox(
                            width: 64,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  DateFormat('EEE').format(date),
                                  style: const TextStyle(
                                    color: HireDStyle.muted,
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
                                        : HireDStyle.ink,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  blocked ? 'Off' : 'Available',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: HireDStyle.muted,
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
      const Padding(
        padding: EdgeInsets.only(top: 28, bottom: 16),
        child: Text(
          'Your documents',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      HireDCard(
        child: Column(
          children: [
            for (final entry in {
              'license': 'Driving licence',
              'aadhaar': 'Aadhaar card',
              'pan': 'PAN card',
              'pcc': 'Police clearance',
            }.entries) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                minVerticalPadding: 12,
                leading: Icon(
                  entry.key == 'license'
                      ? Icons.badge_outlined
                      : Icons.description_outlined,
                  color: HireDStyle.primary,
                ),
                title: Text(
                  entry.value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  state.documents[entry.key] == true
                      ? 'Uploaded · tap to replace'
                      : 'No current document uploaded',
                  style: const TextStyle(fontSize: 11, color: HireDStyle.muted),
                ),
                trailing: IconButton(
                  tooltip: 'Upload ${entry.value.toLowerCase()}',
                  onPressed: state.busy
                      ? null
                      : () => _upload(context, entry.key),
                  icon: Icon(
                    state.documents[entry.key] == true
                        ? Icons.swap_horiz_rounded
                        : Icons.add_rounded,
                    color: HireDStyle.primary,
                  ),
                ),
              ),
              if (entry.key != 'pcc') const Divider(height: 1),
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
      OutlinedButton(
        onPressed: state.busy ? null : signOut,
        child: Text(state.isDemo ? 'Exit demo' : 'Sign out'),
      ),
    ],
  );
}
