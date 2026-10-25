// This file is imported only by main_dev.dart and tests, never by main.dart.
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../auth.dart';
import '../auth_config.dart';
import '../auth_validation.dart';
import '../identity_auth.dart';
import '../onboarding.dart';

const previewPhone = '+919876543210';
const previewOtp = '123456';
const _applicantToken = 'development-only-applicant';
const _driverToken = 'development-only-driver';

void requireDevelopmentBuild() {
  if (!kDebugMode)
    throw UnsupportedError(
      'The OTP preview is available only in debug builds.',
    );
}

/// Even an accidentally inherited transport method cannot contact a server.
class _PreviewHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      throw StateError('Network access is disabled in the local OTP preview.');
}

class PreviewIdentityAuth extends SupabaseIdentityAuth {
  PreviewIdentityAuth({DateTime Function()? clock})
    : clock = clock ?? DateTime.now,
      super(
        const DriverAuthConfig(supabaseUrl: '', publishableKey: ''),
        client: _PreviewHttpClient(),
      ) {
    requireDevelopmentBuild();
  }
  final DateTime Function() clock;
  DateTime? _issuedAt;
  bool _issued = false;

  @override
  Future<DriverAuthMethods> methods() async =>
      const DriverAuthMethods(phone: true, google: false, email: false);

  @override
  Future<void> sendPhoneOtp(
    String phone, {
    bool register = false,
    String? fullName,
    String? city,
  }) async {
    if (phone != previewPhone) {
      throw const DriverAuthException(
        'Use the test number 9876543210 with country code +91. No SMS will be sent.',
      );
    }
    if (register && (fullName?.trim().length ?? 0) < 2) {
      throw const DriverAuthException('Enter your full name.');
    }
    if (_issued &&
        _issuedAt != null &&
        clock().difference(_issuedAt!).inSeconds < 60) {
      throw const DriverAuthException(
        'Please wait 60 seconds before requesting another test code.',
      );
    }
    _issued = true;
    _issuedAt = clock();
  }

  @override
  Future<IdentitySession> verifyPhoneOtp(String phone, String code) async {
    if (!_issued ||
        phone != previewPhone ||
        !isValidOtp(code) ||
        code != previewOtp ||
        _issuedAt == null ||
        clock().difference(_issuedAt!).inMinutes >= 5) {
      throw const DriverAuthException(
        'The test code is incorrect or expired. Use 123456 after requesting a code.',
      );
    }
    _issued = false;
    return const IdentitySession(
      _applicantToken,
      'development-only-refresh',
      300,
    );
  }

  @override
  Future<IdentitySession?> signInWithGoogle() async =>
      throw const DriverAuthException(
        'Use Phone with the test number in this development preview.',
      );

  @override
  Future<void> signOut(String accessToken) async {
    _issued = false;
  }
}

/// In-memory application data. No Storage, database, Supabase Auth or SMS calls.
class PreviewOnboarding extends DriverOnboarding {
  PreviewOnboarding()
    : super(
        const DriverAuthConfig(supabaseUrl: '', publishableKey: ''),
        client: _PreviewHttpClient(),
      ) {
    requireDevelopmentBuild();
  }
  @override
  bool get isPreview => true;
  final Map<String, dynamic> _data = {
    'id': 'LOCAL-PREVIEW-001',
    'status': 'draft',
    'digilocker_status': 'not_connected',
  };
  Uint8List? _selfie;
  String get previewName => _data['full_name'] as String? ?? 'Preview Driver';
  Map<String, dynamic> get previewDocuments => {
    'license':
        _data['licence_front_uploaded'] == true &&
        _data['licence_back_uploaded'] == true,
    'aadhaar': _data['aadhaar_uploaded'] == true,
    'pan': _data['pan_uploaded'] == true,
    'pcc': _data['pcc_uploaded'] == true,
  };

  void _owner(String token) {
    if (token != _applicantToken)
      throw const DriverAuthException('This is a local preview session only.');
  }

  DriverApplication get _snapshot => DriverApplication({..._data});

  @override
  Future<DriverApplication> open(
    String token, {
    required String name,
    required String city,
  }) async {
    _owner(token);
    if (_data['status'] == 'draft')
      _data.addAll({'full_name': name, 'city': city});
    return _snapshot;
  }

  @override
  Future<DriverApplication> status(String token) async {
    _owner(token);
    return _snapshot;
  }

  @override
  Future<DriverApplication> saveDraft(
    String token,
    Map<String, dynamic> details,
  ) async {
    _owner(token);
    _data.addAll(details);
    return _snapshot;
  }

  @override
  Future<void> deleteApplication(String token) async {
    _owner(token);
    _data.clear();
    _data.addAll({'id': 'LOCAL-PREVIEW-001', 'status': 'draft'});
    _selfie = null;
  }

  @override
  Future<DriverApplication> upload(
    String token,
    String kind,
    Uint8List bytes,
  ) async {
    _owner(token);
    if (_data['status'] != 'draft')
      throw const DriverAuthException(
        'This preview application was already submitted.',
      );
    if (![
          'selfie',
          'licence_front',
          'licence_back',
          'aadhaar',
          'pan',
          'pcc',
        ].contains(kind) ||
        driverImageMime(bytes) == null ||
        bytes.length > maxDriverImageBytes) {
      throw const DriverAuthException(
        'Choose a JPG or PNG image smaller than 5 MB.',
      );
    }
    _data['${kind}_uploaded'] = true;
    if (kind == 'selfie') _selfie = Uint8List.fromList(bytes);
    return _snapshot;
  }

  @override
  Future<Uint8List?> avatar(String token) async {
    if (token != _driverToken) return null;
    return _selfie;
  }

  @override
  Future<Uri> startDigiLocker(String token) async {
    _owner(token);
    throw const DriverAuthException(
      'DigiLocker is not connected in the local preview. Add licence photos to test registration.',
    );
  }

  @override
  Future<DriverApplication> submit(
    String token, {
    required String licenceNumber,
    required String aadhaarNumber,
    required DateTime birthDate,
    required DateTime licenceExpiry,
    required String vehicleClass,
  }) async {
    _owner(token);
    if (!validLicenceNumber(licenceNumber) ||
        !validAadhaarNumber(aadhaarNumber) ||
        _data['aadhaar_uploaded'] != true ||
        _data['selfie_uploaded'] != true ||
        _data['licence_front_uploaded'] != true ||
        _data['licence_back_uploaded'] != true) {
      throw const DriverAuthException(
        'Add valid licence and Aadhaar details, both licence photos, an Aadhaar photo and a selfie.',
      );
    }
    _data['aadhaar_last4'] = normalizeAadhaarNumber(aadhaarNumber).substring(8);
    _data['status'] = 'submitted';
    return _snapshot;
  }

  @override
  void dispose() {
    _selfie = null;
    super.dispose();
  }
}

/// Uses the real screens with local data, and never reads/writes secure sessions.
class PreviewDriverAuth extends DriverAuth {
  PreviewDriverAuth(this.application, {PreviewIdentityAuth? identity})
    : super('', identity: identity ?? PreviewIdentityAuth()) {
    requireDevelopmentBuild();
  }
  final PreviewOnboarding application;
  bool _online = false;
  final List<String> _unavailableDates = [];

  Map<String, dynamic> get _profile => {
    'id': 'local-preview-driver',
    'role': 'driver',
    'name': application.previewName,
    'online': _online,
    'unavailableDates': [..._unavailableDates],
    'documents': application.previewDocuments,
  };

  @override
  Future<DriverSession?> restore() async => null;

  @override
  Future<void> sendPhoneOtp(
    String phone, {
    bool register = false,
    String? fullName,
    String? city,
  }) => identity.sendPhoneOtp(
    phone,
    register: register,
    fullName: fullName,
    city: city,
  );

  @override
  Future<IdentitySession> verifyRegistrationOtp(String phone, String code) =>
      identity.verifyPhoneOtp(phone, code);

  @override
  Future<DriverSession> verifyPhoneOtp(String phone, String code) async {
    await identity.verifyPhoneOtp(phone, code);
    return current = DriverSession(
      token: _driverToken,
      refreshToken: 'development-only-refresh',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      profile: _profile,
    );
  }

  @override
  Future<DriverSession?> loginWithGoogle() async =>
      throw const DriverAuthException(
        'Use Phone with the test number in this development preview.',
      );

  @override
  Future<DriverSession> login(String email, String password) async =>
      throw const DriverAuthException(
        'Use Phone with the test number in this development preview.',
      );

  @override
  Future<DriverSession> ensureFresh() async {
    if (current == null)
      throw const DriverAuthException('Sign in with the test number first.');
    return current!;
  }

  @override
  Future<DriverSession> refresh() => ensureFresh();

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    await ensureFresh();
    final uri = Uri.parse(path);
    final route = uri.path;
    if (route == '/drivers/me') return _profile;
    if (route == '/drivers/me/trips') return <Map<String, dynamic>>[];
    if (route == '/drivers/me/wallet')
      return {'balance': 0, 'transactions': <Map<String, dynamic>>[]};
    if (route == '/drivers/me/availability' && method == 'PATCH') {
      _online = body?['online'] == true;
      _unavailableDates
        ..clear()
        ..addAll(List<String>.from(body?['unavailableDates'] ?? []));
      return _profile;
    }
    throw const DriverAuthException(
      'This action is unavailable in the local preview.',
    );
  }

  @override
  Future<void> upload(String path, String filePath, {String? expiresOn}) async {
    await ensureFresh();
  }

  @override
  Future<DriverSession> changePassword(
    String currentPassword,
    String newPassword,
  ) async => throw const DriverAuthException(
    'There are no real credentials in this preview.',
  );

  @override
  Future<bool> logout() async {
    current = null;
    await identity.signOut(_driverToken);
    return true;
  }
}
