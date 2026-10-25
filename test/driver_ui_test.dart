import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hired_driver/auth.dart';
import 'package:hired_driver/auth_screen.dart';
import 'package:hired_driver/design.dart';
import 'package:hired_driver/development/preview_services.dart';
import 'package:hired_driver/main.dart';
import 'package:hired_driver/identity_auth.dart';
import 'package:hired_driver/onboarding_screen.dart';

final _trips = <Map<String, dynamic>>[
  {
    'id': '11111111-1111-4111-8111-111111111111',
    'company': 'Meridian Logistics',
    'pickup': 'Kakkanad, Kochi',
    'drop': 'Edappally, Kochi',
    'date': 'Today · 10:30 AM',
    'status': 'Assigned',
    'expenses': <Map<String, dynamic>>[],
    'selfie': false,
  },
  {
    'id': '22222222-2222-4222-8222-222222222222',
    'company': 'Aster Corporate',
    'pickup': 'Infopark, Kochi',
    'drop': 'Vyttila, Kochi',
    'date': 'Yesterday · 2:00 PM',
    'status': 'Closed',
    'expenses': <Map<String, dynamic>>[],
    'selfie': true,
  },
];

class _WorkspaceAuth extends PreviewDriverAuth {
  _WorkspaceAuth(super.application);
  @override
  Future<DriverSession?> restore() async => current = DriverSession(
    token: 'development-only-driver',
    refreshToken: 'local-preview',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    profile: {
      'name': 'Vasudev',
      'online': true,
      'documents': {'license': true, 'aadhaar': true},
    },
  );
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(path);
    final route = uri.path;
    if (route == '/drivers/me') return {'name': 'Vasudev', 'online': true};
    if (route == '/drivers/me/trips')
      return {
        'trips': _trips
            .where(
              (t) => uri.queryParameters['status'] == 'completed'
                  ? t['status'] == 'Closed'
                  : t['status'] != 'Closed',
            )
            .map((t) => {...t})
            .toList(),
        'activeCount': 1,
        'completedCount': 1,
      };
    if (route.startsWith('/drivers/me/trips/'))
      return {..._trips.firstWhere((t) => t['id'] == route.split('/').last)};
    if (route == '/drivers/me/wallet')
      return {
        'balance': 2400,
        'transactions': [
          {
            'trip': _trips.last['id'],
            'amount': 900,
            'kind': 'trip_credit',
            'signedAmount': 900,
            'date': '24 Oct · 4:10 PM',
          },
          {
            'trip': 'TRP-1024',
            'amount': 1500,
            'kind': 'trip_credit',
            'signedAmount': 1500,
            'date': '23 Oct · 5:30 PM',
          },
        ],
      };
    return super.request(path, method: method, body: body);
  }
}

void main() {
  late PreviewOnboarding onboarding;
  late _WorkspaceAuth auth;
  setUp(() {
    onboarding = PreviewOnboarding();
    auth = _WorkspaceAuth(onboarding);
  });
  tearDown(() {
    auth.dispose();
    onboarding.dispose();
  });

  testWidgets(
    'four tabs, duty filters and long references work on a narrow phone with larger text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: HireDStyle.theme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: DriverHome(authOverride: auth, onboardingOverride: onboarding),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in ['Duties', 'Earnings', 'Profile', 'Home']) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
      }
      await tester.tap(find.text('Duties').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completed (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Aster Corporate'), findsOneWidget);
      expect(find.text('Meridian Logistics'), findsNothing);
      await tester.ensureVisible(find.text('View duty'));
      await tester.tap(find.text('View duty'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Duty completed.'), findsOneWidget);
      expect(find.byTooltip('Back to duties'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  // Optional real Flutter raster previews for visual review, never real accounts.
  testWidgets('capture the actual redesigned screens', (tester) async {
    if (Platform.environment['HIRED_UI_PREVIEWS'] != '1') return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final flutterRoot = Platform.environment['HIRED_FLUTTER_ROOT'];
    if (flutterRoot != null) {
      await tester.runAsync(() async {
        final bytes = await File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        ).readAsBytes();
        final loader = FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
        final icons = await File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes();
        final iconLoader = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(icons)));
        await iconLoader.load();
      });
    }
    final boundary = GlobalKey();
    Widget shell(Widget child) => RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        theme: HireDStyle.theme(),
        debugShowCheckedModeBanner: false,
        home: child,
      ),
    );
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // Repaint the entire root so retained layers are included after tab changes.
      render.markNeedsPaint();
      await tester.pump();
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        final output = File('build/ui-previews/$name.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes);
        image.dispose();
      });
    }

    await tester.pumpWidget(
      shell(
        DriverAuthScreen(
          auth: auth,
          onboarding: onboarding,
          onAuthenticated: (_) async {},
        ),
      ),
    );
    await capture('login');
    await tester.ensureVisible(find.byKey(const Key('open-register')));
    await tester.tap(find.byKey(const Key('open-register')));
    await capture('register');
    await tester.pumpWidget(
      shell(
        DriverOnboardingScreen(
          service: onboarding,
          session: const IdentitySession(
            'development-only-applicant',
            'preview',
            300,
          ),
          fullName: 'Vasudev',
          city: 'Kochi',
          onClose: () async {},
          pickImage: (_, _) async => base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aRZkAAAAASUVORK5CYII=',
          ),
        ),
      ),
    );
    await capture('licence');
    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await tester.enterText(
      find.byKey(const Key('licence-number')),
      'KL0720201234567',
    );
    await tap(find.text('Date of birth'));
    await tap(find.text('OK'));
    await tap(find.text('Licence expiry'));
    await tap(find.text('OK'));
    for (final side in ['front', 'back']) {
      await tap(find.byKey(Key('onboarding-licence-$side')));
      await tap(find.text('Choose from photos'));
    }
    await tap(find.byKey(const Key('onboarding-next')));
    await capture('identity');

    await tester.pumpWidget(
      shell(DriverHome(authOverride: auth, onboardingOverride: onboarding)),
    );
    await capture('home');
    for (final label in ['Duties', 'Earnings', 'Profile']) {
      await tester.tap(find.text(label).last);
      await capture(label.toLowerCase());
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
