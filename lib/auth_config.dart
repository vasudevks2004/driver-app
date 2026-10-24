class DriverAuthConfig {
  const DriverAuthConfig({
    required this.supabaseUrl,
    required this.publishableKey,
    this.googleWebClientId = '',
    this.googleIosClientId = '',
  });

  const DriverAuthConfig.fromEnvironment()
      : supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
        publishableKey = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
        googleWebClientId = const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
        googleIosClientId = const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  final String supabaseUrl;
  final String publishableKey;
  final String googleWebClientId;
  final String googleIosClientId;

  bool get isConfigured => supabaseUrl.isNotEmpty && publishableKey.isNotEmpty;
}
