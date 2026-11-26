class AppConfig {
  static const supabaseUrl =
      String.fromEnvironment('SUPABASE_URL');

  static const supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static const fallbackTitle =
      String.fromEnvironment(
        'APP_TITLE',
        defaultValue: 'Loyalty Studio',
      );

  // Public VAPID key. This is intentionally safe to ship in the browser.
  static const webPushVapidPublicKey =
      String.fromEnvironment(
        'WEB_PUSH_VAPID_PUBLIC_KEY',
        defaultValue: '',
      );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty &&
      supabasePublishableKey.isNotEmpty;
}
