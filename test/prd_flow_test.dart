import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hired_driver/api.dart';
import 'package:hired_driver/auth.dart';
import 'package:hired_driver/core/assignment_feed.dart';
import 'package:hired_driver/development/preview_services.dart';
import 'package:hired_driver/features/duties/duty.dart';
import 'package:hired_driver/features/duties/duty_detail.dart';
import 'package:hired_driver/features/workspace/controller.dart';

class _Feed implements AssignmentFeed {
  void Function()? changed;
  int connections = 0, stops = 0;
  @override
  Future<void> connect(
    String token,
    void Function() callback,
    void Function(bool) status,
  ) async {
    connections++;
    changed = callback;
    status(true);
  }

  @override
  Future<void> updateToken(String token) async {}
  @override
  Future<void> stop() async {
    stops++;
  }
}

class _Auth extends PreviewDriverAuth {
  _Auth(super.application);
  int reads = 0;
  bool assigned = true;
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    if (path.startsWith('/drivers/me/trips?')) {
      reads++;
      return {
        'trips': assigned
            ? [
                {'id': 'duty', 'status': 'Assigned'},
              ]
            : [],
        'activeCount': assigned ? 1 : 0,
        'completedCount': 0,
      };
    }
    if (path == '/drivers/me/trips/duty') {
      if (!assigned) throw const ApiException('Assignment changed', 403);
      return {'id': 'duty', 'status': 'Assigned', 'contactPhone': '9876543210'};
    }
    return super.request(path, method: method, body: body);
  }
}

void main() {
  testWidgets('assigned duty requires a selfie before Start is enabled', (
    tester,
  ) async {
    final onboarding = PreviewOnboarding();
    final auth = _Auth(onboarding);
    final state = DriverWorkspace(auth);
    state.demo();
    await state.select('TRP-1028');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: state,
            builder: (_, __) => DutyDetailPage(state: state),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final start = find.widgetWithText(FilledButton, 'Start driver duty');
    await tester.scrollUntilVisible(find.text('Take selfie'), 300);
    expect(find.text('Take selfie'), findsOneWidget);
    await tester.scrollUntilVisible(start, 300);
    expect(tester.widget<FilledButton>(start).onPressed, isNull);
    state.updateDemoDuty(
      DriverDuty.fromJson({...state.selected.value!.toJson(), 'selfie': true}),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(state.selected.value!.status, DutyStatus.ongoing);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    auth.dispose();
    onboarding.dispose();
  });
  test(
    'assignment signal refreshes immediately and removes a reassigned duty',
    () async {
      final onboarding = PreviewOnboarding();
      final auth = _Auth(onboarding), feed = _Feed();
      final state = DriverWorkspace(auth, assignmentFeed: feed);
      auth.current = DriverSession(
        token: 'test-token',
        refreshToken: 'refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        profile: const {'id': 'driver', 'role': 'driver'},
      );
      state.activate(auth.current!);
      await state.loadDuties();
      await state.select('duty');
      auth.assigned = false;
      final before = auth.reads;
      feed.changed!();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(auth.reads, greaterThan(before));
      expect(state.active.value!.items, isEmpty);
      expect(state.selected.value, isNull);
      state.reset();
      final resetReads = auth.reads;
      feed.changed!();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(auth.reads, resetReads);
      state.dispose();
      auth.dispose();
      onboarding.dispose();
    },
  );
  test(
    'assignment bursts during a mutation reconcile once after it completes',
    () async {
      final onboarding = PreviewOnboarding();
      final auth = _Auth(onboarding), feed = _Feed(), gate = Completer<void>();
      final state = DriverWorkspace(auth, assignmentFeed: feed);
      auth.current = DriverSession(
        token: 'test-token',
        refreshToken: 'refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        profile: const {'id': 'driver', 'role': 'driver'},
      );
      state.activate(auth.current!);
      await state.loadDuties();
      final before = auth.reads;
      final action = state.perform(() => gate.future);
      for (var i = 0; i < 10; i++) {
        feed.changed!();
      }
      expect(auth.reads, before);
      gate.complete();
      await action;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(auth.reads, before + 1);
      state.foreground(false);
      feed.changed!();
      expect(auth.reads, before + 1);
      state.foreground(true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(feed.connections, 2);
      state.dispose();
      auth.dispose();
      onboarding.dispose();
    },
  );
}
