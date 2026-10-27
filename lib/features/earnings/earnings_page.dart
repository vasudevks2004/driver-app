import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../design.dart';
import '../workspace/controller.dart';
import '../workspace/ui.dart';

class EarningsPage extends StatelessWidget {
  const EarningsPage({super.key, required this.state});
  final DriverWorkspace state;
  @override
  Widget build(BuildContext context) {
    final resource = state.earnings, wallet = resource.value;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                pageHeading(
                  'Your earnings',
                  'A clear view of your confirmed ledger.',
                ),
                ResourceStatus(
                  resource: resource,
                  retry: () => state.loadWallet(),
                  label: 'earnings',
                ),
                if (wallet != null)
                  HireDCard(
                    color: HireDStyle.primary,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.account_balance_wallet_outlined,
                              color: Colors.white,
                              size: 21,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                wallet.balanceLabel,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Text(
                          driverMoney(wallet.balance),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Divider(color: Color(0xFF787CF0)),
                        const SizedBox(height: 12),
                        const Text(
                          'Settlements are managed by HireD.',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 28, bottom: 16),
                  child: Text(
                    'Earnings history',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                if (wallet != null && wallet.transactions.isEmpty)
                  const HireDEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Your earnings start here.',
                    description:
                        'Confirmed earnings and settlements will appear here.',
                  ),
              ],
            ),
          ),
        ),
        if (wallet != null)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.builder(
              itemCount: wallet.transactions.length,
              itemBuilder: (context, index) {
                final item = wallet.transactions[index],
                    effect = item.signedAmount;
                final incoming = effect != null && effect >= 0;
                final color = incoming ? HireDStyle.success : HireDStyle.ink;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: HireDCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: incoming
                                ? const Color(0xFFEDF8F2)
                                : HireDStyle.canvas,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            incoming
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded,
                            color: color,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              if (item.tripId != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Duty #${shortReference(item.tripId!)}',
                                  style: const TextStyle(
                                    color: HireDStyle.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 5),
                              Text(
                                item.createdAt == null
                                    ? item.dateLabel
                                    : DateFormat(
                                        'd MMM · h:mm a',
                                      ).format(item.createdAt!),
                                style: const TextStyle(
                                  color: HireDStyle.muted,
                                  fontSize: 12,
                                ),
                              ),
                              if (item.reference.isNotEmpty)
                                Text(
                                  item.reference,
                                  style: const TextStyle(
                                    color: HireDStyle.muted,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            effect == null
                                ? 'Effect unavailable'
                                : '${effect < 0 ? '−' : '+'}${driverMoney(effect.abs())}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: color,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        if (wallet?.nextCursor != null)
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverToBoxAdapter(
              child: OutlinedButton(
                onPressed: resource.loading
                    ? null
                    : () => state.loadWallet(more: true),
                child: const Text('Load more transactions'),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
