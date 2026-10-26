import '../duties/duty.dart';

enum WalletKind { earning, settlement, reversal, adjustment }

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.kind,
    required this.amount,
    this.signedAmount,
    this.tripId,
    this.createdAt,
    this.dateLabel = '',
    this.reason = '',
    this.reference = '',
  });
  final String id;
  final WalletKind kind;
  final num amount;
  final num? signedAmount;
  final String? tripId;
  final DateTime? createdAt;
  final String dateLabel, reason, reference;
  String get label => switch (kind) {
    WalletKind.earning => 'Duty earnings',
    WalletKind.settlement => 'Offline settlement',
    WalletKind.reversal => 'Reversal',
    WalletKind.adjustment => 'Adjustment',
  };
  factory WalletTransaction.fromJson(Map<String, dynamic> j) {
    final kind = switch (j['kind']) {
      'trip_credit' => WalletKind.earning,
      'offline_settlement' => WalletKind.settlement,
      'reversal' => WalletKind.reversal,
      _ => WalletKind.adjustment,
    };
    final amount = readMoney(j['amount']);
    if (amount == null || !amount.isFinite) {
      throw const FormatException('Invalid ledger amount');
    }
    // Older responses have no signed ledger effect. A reversal's direction is never guessed.
    final suppliedSigned = readMoney(j['signedAmount']);
    if (j['signedAmount'] != null && suppliedSigned == null) {
      throw const FormatException('Invalid signed ledger amount');
    }
    final signed =
        suppliedSigned ??
        switch (kind) {
          WalletKind.earning => amount,
          WalletKind.settlement => -amount,
          _ => null,
        };
    final date = j['date']?.toString() ?? '';
    return WalletTransaction(
      id: j['id']?.toString() ?? '${j['trip'] ?? ''}-$date',
      kind: kind,
      amount: amount,
      signedAmount: signed,
      tripId: j['trip']?.toString(),
      createdAt: DateTime.tryParse(date)?.toLocal(),
      dateLabel: date,
      reason: j['reason']?.toString() ?? '',
      reference: j['reference']?.toString() ?? '',
    );
  }
}

class DriverWallet {
  const DriverWallet({
    required this.balance,
    required this.transactions,
    this.meaning = '',
    this.nextCursor,
  });
  final num balance;
  final List<WalletTransaction> transactions;
  final String meaning;
  String get balanceLabel => switch (meaning) {
    'outstanding_payable' => 'Outstanding payable',
    'cumulative_earnings' => 'Cumulative earnings',
    _ => 'Wallet balance',
  };
  final Map<String, String>? nextCursor;
  factory DriverWallet.fromJson(Map<String, dynamic> j) {
    final balance = readMoney(j['balance']);
    if (balance == null || !balance.isFinite || j['transactions'] is! List) {
      throw const FormatException('Invalid wallet response');
    }
    final c = j['nextCursor'];
    return DriverWallet(
      balance: balance,
      transactions: (j['transactions'] as List)
          .map(
            (x) =>
                WalletTransaction.fromJson(Map<String, dynamic>.from(x as Map)),
          )
          .toList(),
      meaning: j['meaning']?.toString() ?? '',
      nextCursor: c is Map
          ? c.map((k, v) => MapEntry(k.toString(), v.toString()))
          : null,
    );
  }
}
