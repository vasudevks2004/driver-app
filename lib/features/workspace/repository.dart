import '../../auth.dart';
import '../duties/duty.dart';
import '../earnings/earnings.dart';

class DriverRepository {
  DriverRepository(this.auth);
  final DriverAuth auth;
  Future<Map<String, dynamic>> profile() async =>
      Map<String, dynamic>.from(await auth.request('/drivers/me') as Map);
  Future<DutyPage> duties({
    bool completed = false,
    Map<String, String>? cursor,
  }) async {
    final query = Uri(
      queryParameters: {
        'v': '2',
        'limit': '20',
        'status': completed ? 'completed' : 'active',
        ...?cursor,
      },
    ).query;
    return DutyPage.fromJson(await auth.request('/drivers/me/trips?$query'));
  }

  Future<DriverWallet> wallet({Map<String, String>? cursor}) async {
    final query = Uri(
      queryParameters: {'v': '2', 'limit': '20', ...?cursor},
    ).query;
    return DriverWallet.fromJson(
      Map<String, dynamic>.from(
        await auth.request('/drivers/me/wallet?$query') as Map,
      ),
    );
  }

  Future<DriverDuty> duty(String id) async => DriverDuty.fromJson(
    Map<String, dynamic>.from(
      await auth.request('/drivers/me/trips/${Uri.encodeComponent(id)}') as Map,
    ),
  );
  Future<void> start(String id) async {
    await auth.request('/trips/$id/start', method: 'POST', body: {});
  }

  Future<void> expense(String id, String description, String amount) async {
    await auth.request(
      '/trips/$id/expenses',
      method: 'POST',
      body: {'description': description, 'amount': amount},
    );
  }

  Future<void> close(String id, String code) async {
    await auth.request('/trips/$id/close', method: 'POST', body: {'otp': code});
  }

  Future<void> availability(bool online, Set<String> unavailable) async {
    await auth.request(
      '/drivers/me/availability',
      method: 'PATCH',
      body: {
        'online': online,
        'unavailableDates': unavailable.toList()..sort(),
      },
    );
  }
}
