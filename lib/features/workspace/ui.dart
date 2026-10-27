import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/resource.dart';
import '../../design.dart';

String driverMoney(num amount) => NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: amount % 1 == 0 ? 0 : 2,
).format(amount);
String shortReference(String value) =>
    value.length > 16 ? value.substring(value.length - 8).toUpperCase() : value;
Widget pageHeading(String title, String subtitle) => Padding(
  padding: const EdgeInsets.only(bottom: 24),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -.7,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        subtitle,
        style: const TextStyle(
          color: HireDStyle.muted,
          fontSize: 13,
          height: 1.6,
        ),
      ),
    ],
  ),
);

class ResourceStatus<T> extends StatelessWidget {
  const ResourceStatus({
    super.key,
    required this.resource,
    required this.retry,
    required this.label,
  });
  final Resource<T> resource;
  final VoidCallback retry;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (resource.loading)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: LinearProgressIndicator(minHeight: 2),
        ),
      if (resource.error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HireDNotice(
                '${resource.available ? 'Showing the last confirmed $label. ' : ''}${resource.error}',
                error: true,
              ),
              TextButton(
                onPressed: resource.loading ? null : retry,
                child: Text('Retry $label'),
              ),
            ],
          ),
        ),
      if (!resource.available && resource.error == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Loading $label…',
            style: const TextStyle(color: HireDStyle.muted),
          ),
        ),
    ],
  );
}

const workspacePadding = EdgeInsets.fromLTRB(20, 20, 20, 32);
