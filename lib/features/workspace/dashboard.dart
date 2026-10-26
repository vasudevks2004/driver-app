import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../design.dart';
import '../../driver_widgets.dart';
import 'controller.dart';
import 'ui.dart';

class DriverDashboard extends StatelessWidget {
  const DriverDashboard({super.key, required this.state});
  final DriverWorkspace state;
  Widget stat(String title, String value, IconData icon, VoidCallback action) =>
      Expanded(
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: HireDStyle.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: action,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: HireDStyle.primary, size: 21),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: const TextStyle(
                      color: HireDStyle.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  @override
  Widget build(BuildContext context) {
    final items = [...?state.active.value?.items]
      ..sort((a, b) {
        if (a.status != b.status) {
          return a.statusLabel == 'Ongoing'
              ? -1
              : b.statusLabel == 'Ongoing'
              ? 1
              : 0;
        }
        return (a.scheduledAt ?? DateTime(9999)).compareTo(
          b.scheduledAt ?? DateTime(9999),
        );
      });
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: workspacePadding,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEEE, d MMMM').format(DateTime.now()),
                  style: const TextStyle(color: HireDStyle.muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                pageHeading(
                  'Hello, ${state.name.split(' ').first}',
                  'Let’s make it a good day on the road.',
                ),
                ResourceStatus(
                  resource: state.profile,
                  retry: () => state.loadProfile(),
                  label: 'profile',
                ),
                HireDCard(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: state.online
                              ? const Color(0xFFEDF8F2)
                              : HireDStyle.tint,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.power_settings_new_rounded,
                          color: state.online
                              ? HireDStyle.success
                              : HireDStyle.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.online ? 'You’re online' : 'You’re offline',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              state.online
                                  ? 'Available for assignments'
                                  : 'Go online when you’re ready',
                              style: const TextStyle(
                                color: HireDStyle.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Semantics(
                        label: 'Available for driver assignments',
                        child: Switch.adaptive(
                          value: state.online,
                          onChanged: state.busy
                              ? null
                              : (value) => state.perform(
                                  () => state.setAvailability(
                                    value,
                                    state.unavailable,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    stat(
                      'Active duties',
                      state.active.available
                          ? '${state.active.value!.activeCount}'
                          : '—',
                      Icons.route_outlined,
                      () => state.navigate(1),
                    ),
                    const SizedBox(width: 12),
                    stat(
                      'Wallet balance',
                      state.earnings.available
                          ? driverMoney(state.earnings.value!.balance)
                          : '—',
                      Icons.account_balance_wallet_outlined,
                      () => state.navigate(2),
                    ),
                  ],
                ),
                if (state.earnings.error != null) ...[
                  const SizedBox(height: 12),
                  ResourceStatus(
                    resource: state.earnings,
                    retry: () => state.loadWallet(),
                    label: 'earnings',
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Your next duty',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => state.navigate(1),
                      child: const Text('View all'),
                    ),
                  ],
                ),
                ResourceStatus(
                  resource: state.active,
                  retry: () => state.loadDuties(),
                  label: 'duties',
                ),
                if (state.active.available) ...[
                  if (items.isEmpty)
                    const HireDEmptyState(
                      icon: Icons.route_outlined,
                      title: 'You’re all caught up.',
                      description:
                          'Your next assigned duty will appear here. Keep your availability up to date.',
                    )
                  else
                    DutyCard(
                      duty: items.first.toJson(),
                      featured: true,
                      onOpen: () => state.select(items.first.id),
                    ),
                ],
                const SizedBox(height: 20),
                InkWell(
                  onTap: () => state.navigate(3),
                  borderRadius: BorderRadius.circular(16),
                  child: const HireDCard(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_month_outlined,
                          color: HireDStyle.primary,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Plan your availability',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Mark days you’re taking off.',
                                style: TextStyle(
                                  color: HireDStyle.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: HireDStyle.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
