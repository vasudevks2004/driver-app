import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../auth.dart';
import '../../core/resource.dart';
import '../../core/assignment_feed.dart';
import '../duties/duty.dart';
import '../earnings/earnings.dart';
import 'repository.dart';

class DriverWorkspace extends ChangeNotifier {
  DriverWorkspace(this.auth, {AssignmentFeed? assignmentFeed})
    : repository = DriverRepository(auth),
      _feed = assignmentFeed ?? SupabaseAssignmentFeed(auth.identity.config) {
    _sessionSubscription = auth.sessionChanges.listen((session) {
      if (session == null) {
        unawaited(_feed.stop());
      } else if (_foreground && !isDemo) {
        unawaited(_feed.updateToken(session.token));
      }
    });
  }
  final DriverAuth auth;
  final DriverRepository repository;
  final AssignmentFeed _feed;
  StreamSubscription<DriverSession?>? _sessionSubscription;
  bool _assignmentRefreshPending = false, _assignmentRefreshing = false;
  String? assignmentMessage;
  Resource<Map<String, dynamic>> profile = const Resource();
  Resource<DutyPage> active = const Resource(), completed = const Resource();
  Resource<DriverWallet> earnings = const Resource();
  Resource<DriverDuty> selected = const Resource();
  bool busy = false, isDemo = false;
  String? actionError, notice;
  int page = 0;
  bool showCompleted = false;
  int _epoch = 0;
  bool _disposed = false;
  Timer? _timer;
  bool _foreground = true;
  String get name => profile.value?['name']?.toString() ?? 'Driver';
  bool get online => profile.value?['online'] == true;
  Set<String> get unavailable =>
      (profile.value?['unavailableDates'] as List? ?? [])
          .map((x) => x.toString())
          .toSet();
  Map<String, bool> get documents => Map<String, dynamic>.from(
    profile.value?['documents'] as Map? ?? {},
  ).map((k, v) => MapEntry(k, v == true));
  String _message(Object error) => error is FormatException
      ? 'HireD returned data that could not be confirmed. Retry or contact support.'
      : error.toString();
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void activate(DriverSession session) {
    _epoch++;
    busy = false;
    isDemo = false;
    page = 0;
    showCompleted = false;
    actionError = null;
    notice = null;
    profile = Resource(value: session.profile, updatedAt: DateTime.now());
    active = const Resource();
    completed = const Resource();
    earnings = const Resource();
    selected = const Resource();
    _changed();
    _startTimer();
    _connectFeed();
  }

  void reset() {
    busy = false;
    _epoch++;
    _timer?.cancel();
    unawaited(_feed.stop());
    _assignmentRefreshPending = false;
    assignmentMessage = null;
    profile = const Resource();
    active = const Resource();
    completed = const Resource();
    earnings = const Resource();
    selected = const Resource();
    isDemo = false;
    page = 0;
    notice = null;
    actionError = null;
    _changed();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_foreground && !busy && !active.loading && !isDemo) {
        unawaited(loadDuties());
      }
    });
  }

  void foreground(bool value) {
    final old = _foreground;
    _foreground = value;
    if (!value) unawaited(_feed.stop());
    if (value && !old && !isDemo && auth.current != null) {
      _connectFeed();
      unawaited(refresh());
    }
  }

  void _connectFeed() {
    final session = auth.current;
    if (session == null || isDemo || !_foreground || _disposed) return;
    final epoch = _epoch;
    unawaited(
      _feed.connect(
        session.token,
        () {
          if (epoch == _epoch && !_disposed) {
            _assignmentRefreshPending = true;
            unawaited(_drainAssignments());
          }
        },
        (connected) {
          if (epoch != _epoch || _disposed) return;
          assignmentMessage = connected
              ? null
              : 'Assignment updates are delayed. Refresh to check for changes.';
          _changed();
        },
      ),
    );
  }

  Future<void> _drainAssignments() async {
    if (!_assignmentRefreshPending ||
        _assignmentRefreshing ||
        busy ||
        active.loading ||
        !_foreground ||
        isDemo ||
        _disposed) {
      return;
    }
    _assignmentRefreshPending = false;
    _assignmentRefreshing = true;
    final epoch = _epoch;
    try {
      await loadDuties();
      if (epoch == _epoch && page == 4 && selected.value != null) {
        await select(selected.value!.id, open: false);
      }
    } finally {
      _assignmentRefreshing = false;
      if (_assignmentRefreshPending) unawaited(_drainAssignments());
    }
  }

  void navigate(int next) {
    page = next;
    actionError = null;
    if (next == 1 &&
        showCompleted &&
        !completed.available &&
        !completed.loading) {
      unawaited(loadDuties(completedOnly: true));
    }
    _changed();
  }

  void filter(bool value) {
    showCompleted = value;
    if (value && !completed.available && !completed.loading) {
      unawaited(loadDuties(completedOnly: true));
    }
    _changed();
  }

  Future<void> loadProfile() async {
    if (isDemo || profile.loading) return;
    final epoch = _epoch;
    profile = profile.fetching();
    _changed();
    try {
      final value = await repository.profile();
      if (epoch == _epoch && !_disposed) profile = profile.received(value);
    } catch (e) {
      if (epoch == _epoch && !_disposed) profile = profile.failed(_message(e));
    } finally {
      if (epoch == _epoch) _changed();
    }
  }

  Future<void> loadDuties({
    bool completedOnly = false,
    bool more = false,
  }) async {
    if (isDemo) return;
    final old = completedOnly ? completed : active;
    if (old.loading) return;
    final epoch = _epoch;
    final oldIds = old.value?.items.map((x) => x.id).toSet();
    if (completedOnly) {
      completed = old.fetching();
    } else {
      active = old.fetching();
    }
    _changed();
    try {
      final value = await repository.duties(
        completed: completedOnly,
        cursor: more ? old.value?.nextCursor : null,
      );
      if (epoch != _epoch || _disposed) return;
      final next = more && old.value != null
          ? DutyPage(
              [
                ...old.value!.items,
                ...value.items.where(
                  (n) => !old.value!.items.any((o) => o.id == n.id),
                ),
              ],
              nextCursor: value.nextCursor,
              activeCount: value.activeCount,
              completedCount: value.completedCount,
            )
          : value;
      if (completedOnly) {
        completed = old.received(next);
      } else {
        active = old.received(next);
        if (oldIds != null && value.items.any((x) => !oldIds.contains(x.id))) {
          notice =
              'Your assignments have changed. Open Duties for the latest details.';
        }
      }
    } catch (e) {
      if (epoch == _epoch && !_disposed) {
        if (completedOnly) {
          completed = old.failed(_message(e));
        } else {
          active = old.failed(_message(e));
        }
      }
    } finally {
      if (epoch == _epoch) {
        _changed();
        unawaited(_drainAssignments());
      }
    }
  }

  Future<void> loadWallet({bool more = false}) async {
    if (isDemo || earnings.loading) return;
    final old = earnings, epoch = _epoch;
    earnings = old.fetching();
    _changed();
    try {
      final value = await repository.wallet(
        cursor: more ? old.value?.nextCursor : null,
      );
      if (epoch != _epoch || _disposed) return;
      earnings = old.received(
        more && old.value != null
            ? DriverWallet(
                balance: value.balance,
                meaning: value.meaning,
                nextCursor: value.nextCursor,
                transactions: [
                  ...old.value!.transactions,
                  ...value.transactions.where(
                    (n) => !old.value!.transactions.any((o) => o.id == n.id),
                  ),
                ],
              )
            : value,
      );
    } catch (e) {
      if (epoch == _epoch && !_disposed) earnings = old.failed(_message(e));
    } finally {
      if (epoch == _epoch) _changed();
    }
  }

  Future<void> refresh() async {
    if (isDemo) return;
    await Future.wait([loadProfile(), loadDuties(), loadWallet()]);
    if (page == 4 && selected.value != null) {
      await select(selected.value!.id, open: false);
    }
  }

  Future<void> select(String id, {bool open = true}) async {
    if (open) {
      page = 4;
      selected = const Resource(loading: true);
    }
    _changed();
    if (isDemo) {
      selected = Resource(
        value: [
          ...active.value!.items,
          ...completed.value!.items,
        ].firstWhere((x) => x.id == id),
      );
      _changed();
      return;
    }
    final epoch = _epoch;
    try {
      final value = await repository.duty(id);
      if (epoch == _epoch && !_disposed) selected = selected.received(value);
    } catch (e) {
      if (epoch == _epoch && !_disposed) {
        selected = Resource(error: _message(e));
      }
    } finally {
      if (epoch == _epoch) _changed();
    }
  }

  Future<bool> perform(Future<void> Function() operation) async {
    if (busy) return false;
    busy = true;
    actionError = null;
    _changed();
    final epoch = _epoch;
    try {
      await operation();
      return epoch == _epoch;
    } catch (e) {
      if (epoch == _epoch) actionError = _message(e);
      return false;
    } finally {
      if (epoch == _epoch) {
        busy = false;
        _changed();
        unawaited(_drainAssignments());
      }
    }
  }

  Future<void> setAvailability(bool value, Set<String> dates) async {
    if (!isDemo) await repository.availability(value, dates);
    profile = profile.received({
      ...?profile.value,
      'online': value,
      'unavailableDates': dates.toList(),
    });
    _changed();
  }

  void clearNotice() {
    notice = null;
    _changed();
  }

  void demo() {
    reset();
    isDemo = true;
    profile = Resource(
      value: {
        'name': 'Alex Morgan',
        'online': false,
        'documents': <String, bool>{},
        'unavailableDates': <String>[],
      },
      updatedAt: DateTime.now(),
    );
    active = Resource(
      value: DutyPage([
        DriverDuty(
          id: 'TRP-1028',
          company: 'Meridian Logistics',
          pickup: 'Kakkanad, Kochi',
          destination: 'Edappally, Kochi',
          status: DutyStatus.assigned,
          scheduleLabel: 'Today · 10:30 AM',
        ),
      ]),
    );
    completed = const Resource(value: DutyPage([]));
    earnings = const Resource(
      value: DriverWallet(balance: 0, transactions: []),
    );
    _changed();
  }

  void updateDemoDuty(DriverDuty duty) {
    final items = active.value?.items ?? [];
    active = Resource(
      value: DutyPage(
        items
            .map((d) => d.id == duty.id ? duty : d)
            .where((d) => !d.complete)
            .toList(),
      ),
    );
    if (duty.complete) {
      completed = Resource(value: DutyPage([duty, ...?completed.value?.items]));
    }
    selected = Resource(value: duty);
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    _sessionSubscription?.cancel();
    unawaited(_feed.stop());
    super.dispose();
  }
}
