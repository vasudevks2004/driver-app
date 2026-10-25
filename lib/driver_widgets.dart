import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'design.dart';

bool dutyIsComplete(Map<String, dynamic> duty) =>
    ['closed', 'completed'].contains(duty['status']?.toString().toLowerCase());
String dutyStatus(Map<String, dynamic> duty) => dutyIsComplete(duty)
    ? 'Completed'
    : duty['status']?.toString().toLowerCase() == 'ongoing'
    ? 'In progress'
    : 'Assigned';
String dutyReference(dynamic value) {
  final text = value?.toString() ?? '—';
  return text.length > 16
      ? text.substring(text.length - 8).toUpperCase()
      : text;
}

String dutySchedule(Map<String, dynamic> duty) {
  final value = (duty['date'] ?? duty['scheduledAt'] ?? '').toString();
  final date = DateTime.tryParse(value);
  return date == null
      ? value
      : DateFormat('d MMM · h:mm a').format(date.toLocal());
}

class DutyRoute extends StatelessWidget {
  const DutyRoute({super.key, required this.pickup, required this.destination});
  final String pickup, destination;
  Widget _point(IconData icon, String label, String address, Color color) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: HireDStyle.muted, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  address,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _point(Icons.radio_button_checked, 'PICKUP', pickup, HireDStyle.primary),
      const Padding(
        padding: EdgeInsets.only(left: 8, top: 6, bottom: 6),
        child: SizedBox(
          height: 12,
          child: VerticalDivider(width: 1, thickness: 1),
        ),
      ),
      _point(
        Icons.location_on_outlined,
        'DESTINATION',
        destination,
        HireDStyle.muted,
      ),
    ],
  );
}

class DutyCard extends StatelessWidget {
  const DutyCard({
    super.key,
    required this.duty,
    required this.onOpen,
    this.featured = false,
  });
  final Map<String, dynamic> duty;
  final VoidCallback onOpen;
  final bool featured;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: featured ? const Color(0xFFCCCEFA) : HireDStyle.line,
        ),
      ),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      (duty['company'] ??
                              duty['companyName'] ??
                              'HireD partner')
                          .toString(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: HireDBadge(
                        dutyStatus(duty),
                        color: dutyIsComplete(duty)
                            ? HireDStyle.success
                            : HireDStyle.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.schedule_outlined,
                    size: 15,
                    color: HireDStyle.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      dutySchedule(duty).isEmpty
                          ? 'Schedule to be confirmed'
                          : dutySchedule(duty),
                      style: const TextStyle(
                        color: HireDStyle.muted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              DutyRoute(
                pickup:
                    '${duty['pickup'] ?? duty['pickupAddress'] ?? 'Pickup to be confirmed'}',
                destination:
                    '${duty['drop'] ?? duty['dropAddress'] ?? 'Destination to be confirmed'}',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Duty #${dutyReference(duty['reference'] ?? duty['id'])}',
                      style: const TextStyle(
                        color: HireDStyle.muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const Text(
                    'View duty',
                    style: TextStyle(
                      color: HireDStyle.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 17,
                    color: HireDStyle.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
