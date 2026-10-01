/// Build-time configuration. Override with
/// `--dart-define=API_BASE_URL=https://erp-api.zaamaitech.co.uk`.
class AppConfig {
  static const String defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://erp-api.zaamaitech.co.uk',
  );

  static const String appVersion = '1.0.0';
  static const String appName = 'Zaam EPOS';
  static const String supportUrl = 'https://erp.zaamaitech.co.uk';

  /// How often the till pulls stock levels and catalogue changes.
  static const Duration stockSyncInterval = Duration(seconds: 60);
  static const Duration catalogSyncInterval = Duration(minutes: 5);
  static const Duration outboxFlushInterval = Duration(seconds: 20);
  static const Duration connectivityInterval = Duration(seconds: 15);

  /// Normalises a user-entered server URL: trims, strips trailing `/` and `/api`.
  static String normaliseBaseUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return defaultApiBaseUrl;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/api')) url = url.substring(0, url.length - 4);
    return url;
  }
}
