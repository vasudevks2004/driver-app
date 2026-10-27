DateTime? _date(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '')?.toLocal();
num? readMoney(Object? value) {
  final parsed = value is num ? value : num.tryParse(value?.toString() ?? '');
  return parsed != null && parsed.isFinite ? parsed : null;
}

enum DutyStatus { assigned, ongoing, closed, unavailable }

class DutyExpense {
  const DutyExpense({required this.description, required this.amount, this.id});
  final String? id;
  final String description;
  final num amount;
  factory DutyExpense.fromJson(Map<String, dynamic> json) {
    final amount = readMoney(json['amount']);
    if (amount == null || amount < 0) {
      throw const FormatException('Invalid expense amount');
    }
    return DutyExpense(
      id: json['id']?.toString(),
      description: json['description']?.toString() ?? '',
      amount: amount,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'amount': amount,
  };
}

class DriverDuty {
  const DriverDuty({
    required this.id,
    required this.company,
    required this.pickup,
    required this.destination,
    required this.status,
    this.scheduledAt,
    this.scheduleLabel = '',
    this.createdAt,
    this.selfie = false,
    this.expensesSubmitted = false,
    this.noExpenses = false,
    this.expenses = const [],
    this.contactName,
    this.contactPhone,
    this.pickupLat,
    this.pickupLng,
    this.dropLat,
    this.dropLng,
    this.service = '',
    this.instructions = '',
  });
  final String id,
      company,
      pickup,
      destination,
      scheduleLabel,
      service,
      instructions;
  final DutyStatus status;
  final DateTime? scheduledAt, createdAt;
  final bool selfie, expensesSubmitted, noExpenses;
  final List<DutyExpense> expenses;
  final String? contactName, contactPhone;
  final num? pickupLat, pickupLng, dropLat, dropLng;
  bool get complete => status == DutyStatus.closed;
  bool get active =>
      status == DutyStatus.assigned || status == DutyStatus.ongoing;
  String get statusLabel => switch (status) {
    DutyStatus.assigned => 'Assigned',
    DutyStatus.ongoing => 'Ongoing',
    DutyStatus.closed => 'Closed',
    _ => 'Unavailable',
  };
  factory DriverDuty.fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Invalid duty identity');
    }
    final status = switch (j['status']?.toString().toLowerCase()) {
      'assigned' => DutyStatus.assigned,
      'ongoing' => DutyStatus.ongoing,
      'closed' || 'completed' => DutyStatus.closed,
      _ => DutyStatus.unavailable,
    };
    final expenses = (j['expenses'] as List? ?? [])
        .map((e) => DutyExpense.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return DriverDuty(
      id: id,
      company: (j['company'] ?? j['companyName'] ?? 'HireD partner').toString(),
      pickup: (j['pickup'] ?? j['pickupAddress'] ?? 'Pickup to be confirmed')
          .toString(),
      destination:
          (j['drop'] ?? j['dropAddress'] ?? 'Destination to be confirmed')
              .toString(),
      status: status,
      scheduledAt: _date(j['scheduledAt']),
      scheduleLabel: (j['date'] ?? '').toString(),
      createdAt: _date(j['createdAt']),
      selfie: j['selfie'] == true,
      expensesSubmitted: j['expensesSubmitted'] == true || expenses.isNotEmpty,
      noExpenses: j['noExpenses'] == true,
      expenses: expenses,
      contactName: status == DutyStatus.closed
          ? null
          : j['contactName']?.toString(),
      contactPhone: status == DutyStatus.closed
          ? null
          : j['contactPhone']?.toString(),
      pickupLat: readMoney(j['pickupLat']),
      pickupLng: readMoney(j['pickupLng']),
      dropLat: readMoney(j['dropLat']),
      dropLng: readMoney(j['dropLng']),
      service: j['service']?.toString() ?? '',
      instructions: j['instructions']?.toString() ?? '',
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'company': company,
    'pickup': pickup,
    'drop': destination,
    'status': statusLabel,
    'date': scheduleLabel.isEmpty
        ? scheduledAt?.toIso8601String()
        : scheduleLabel,
    'selfie': selfie,
    'expenses': expenses.map((e) => e.toJson()).toList(),
    'expensesSubmitted': expensesSubmitted,
    'noExpenses': noExpenses,
  };
}

class DutyPage {
  const DutyPage(
    this.items, {
    this.nextCursor,
    this.activeCount = 0,
    this.completedCount = 0,
  });
  final List<DriverDuty> items;
  final Map<String, String>? nextCursor;
  final int activeCount, completedCount;
  factory DutyPage.fromJson(dynamic data) {
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{'trips': data};
    if (map['trips'] is! List) {
      throw const FormatException('Invalid duties response');
    }
    final items = (map['trips'] as List)
        .map((x) => DriverDuty.fromJson(Map<String, dynamic>.from(x as Map)))
        .toList();
    final cursor = map['nextCursor'];
    return DutyPage(
      items,
      nextCursor: cursor is Map
          ? cursor.map((k, v) => MapEntry(k.toString(), v.toString()))
          : null,
      activeCount:
          (map['activeCount'] as num?)?.toInt() ??
          items.where((d) => d.active).length,
      completedCount:
          (map['completedCount'] as num?)?.toInt() ??
          items.where((d) => d.complete).length,
    );
  }
}
