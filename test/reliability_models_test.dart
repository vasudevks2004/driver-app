import 'package:flutter_test/flutter_test.dart';
import 'package:hired_driver/features/duties/duty.dart';
import 'package:hired_driver/features/earnings/earnings.dart';
import 'package:hired_driver/core/pending_operations.dart';
import 'package:hired_driver/features/workspace/controller.dart';
import 'package:hired_driver/development/preview_services.dart';
import 'package:hired_driver/auth.dart';
import 'package:hired_driver/core/expense_validation.dart';

class _FailingAuth extends PreviewDriverAuth {
  _FailingAuth(super.application);
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async => throw StateError('Offline test');
}

void main() {
  test('non-finite numeric and string values cannot enter money models', () {
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
      'NaN',
      'Infinity',
      '-Infinity',
    ]) {
      expect(readMoney(value), isNull);
      expect(
        () => DutyExpense.fromJson({'description': 'Parking', 'amount': value}),
        throwsFormatException,
      );
      expect(
        () => DriverWallet.fromJson({'balance': value, 'transactions': []}),
        throwsFormatException,
      );
      expect(
        () => WalletTransaction.fromJson({
          'kind': 'trip_credit',
          'amount': 100,
          'signedAmount': value,
        }),
        throwsFormatException,
      );
    }
    expect(readMoney('125.50'), 125.5);
  });
  test('expense amounts follow the server precision and range', () {
    for (final input in [
      'NaN',
      'Infinity',
      '-Infinity',
      '-1',
      '1e3',
      '1.001',
      '10000000000',
      '0',
      '0.00',
      '',
      ' 10 ',
    ]) {
      expect(isValidExpenseAmount(input), isFalse, reason: input);
    }
    for (final input in ['0.01', '25', '100.50', '9999999999.99']) {
      expect(isValidExpenseAmount(input), isTrue, reason: input);
    }
    expect(isValidExpenseAmount('0', allowZero: true), isTrue);
    expect(isValidExpenseAmount('NaN', allowZero: true), isFalse);
  });
  test(
    'wallet signed effects come from the ledger, including either reversal direction',
    () {
      for (final input in [
        {'kind': 'trip_credit', 'amount': 100, 'signedAmount': 100},
        {'kind': 'offline_settlement', 'amount': 60, 'signedAmount': -60},
        {'kind': 'reversal', 'amount': 60, 'signedAmount': 60},
        {'kind': 'reversal', 'amount': 100, 'signedAmount': -100},
      ]) {
        expect(
          WalletTransaction.fromJson(input).signedAmount,
          input['signedAmount'],
        );
      }
      expect(
        WalletTransaction.fromJson({
          'kind': 'reversal',
          'amount': 100,
        }).signedAmount,
        isNull,
      );
    },
  );
  test(
    'no-expenses survives deserialization and unknown duty states stay unavailable',
    () {
      final duty = DriverDuty.fromJson({
        'id': 'trip-test',
        'status': 'Ongoing',
        'selfie': true,
        'expenses': [],
        'expensesSubmitted': true,
        'noExpenses': true,
      });
      expect(duty.expensesSubmitted, isTrue);
      expect(duty.noExpenses, isTrue);
      expect(duty.expenses, isEmpty);
      expect(
        DriverDuty.fromJson({'id': 'unknown', 'status': 'reassigned'}).status,
        DutyStatus.unavailable,
      );
      expect(
        DriverDuty.fromJson({
          'id': 'closed',
          'status': 'Closed',
          'contactPhone': '9876543210',
        }).contactPhone,
        isNull,
      );
    },
  );
  test(
    'pending operation keys survive recreation, bind account and payload, and store no request bodies',
    () async {
      final storage = MemoryOperationStorage(),
          first = PendingOperations(storage: MemoryOperationStorage());
      final operations = PendingOperations(storage: storage),
          hash = operationFingerprint('POST', '/trips/a/close', {
            'otp': '654321',
          });
      final key = await operations.begin('https://api.test', 'driver-a', hash);
      expect(
        await PendingOperations(
          storage: storage,
        ).begin('https://api.test', 'driver-a', hash),
        key,
      );
      expect(
        await operations.begin('https://api.test', 'driver-b', hash),
        isNot(key),
      );
      expect(
        await operations.begin(
          'https://api.test',
          'driver-a',
          operationFingerprint('POST', '/trips/a/close', {'otp': '000000'}),
        ),
        isNot(key),
      );
      await operations.acknowledge('https://api.test', 'driver-a', hash);
      expect(
        await operations.begin('https://api.test', 'driver-a', hash),
        isNot(key),
      );
      expect(await first.begin('server', 'actor', hash), isNotEmpty);
    },
  );
  test(
    'unresolved changes block another payload in the same operation group',
    () async {
      final store = MemoryOperationStorage(),
          pending = PendingOperations(storage: store);
      final key = await pending.begin(
        'api',
        'driver',
        'first',
        group: 'expense',
      );
      expect(
        (await PendingOperations(
          storage: store,
        ).unresolved('api', 'driver', group: 'expense'))['first'],
        key,
      );
      await expectLater(
        pending.begin('api', 'driver', 'edited', group: 'expense'),
        throwsStateError,
      );
      expect(
        await pending.begin('api', 'driver', 'first', group: 'expense'),
        key,
      );
      await pending.acknowledge('api', 'driver', 'first');
      expect(
        await pending.begin('api', 'driver', 'edited', group: 'expense'),
        isNot(key),
      );
    },
  );
  test('concurrent matching actions share one pending key', () async {
    final pending = PendingOperations(storage: MemoryOperationStorage());
    final keys = await Future.wait(
      List.generate(
        10,
        (_) => pending.begin('server', 'driver', 'fingerprint'),
      ),
    );
    expect(keys.toSet().length, 1);
  });
  test(
    'failed initial loads remain unavailable rather than becoming confirmed zero balances or empty duties',
    () async {
      final application = PreviewOnboarding(),
          auth = _FailingAuth(PreviewOnboarding());
      final state = DriverWorkspace(auth);
      auth.current = DriverSession(
        token: 'development-only-driver',
        refreshToken: 'preview',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        profile: {'id': 'driver-a', 'role': 'driver', 'name': 'Test'},
      );
      state.activate(auth.current!);
      await state.refresh();
      expect(state.active.value, isNull);
      expect(state.active.error, isNotNull);
      expect(state.earnings.value, isNull);
      expect(state.earnings.error, isNotNull);
      state.dispose();
      auth.dispose();
      application.dispose();
      auth.application.dispose();
    },
  );
}
