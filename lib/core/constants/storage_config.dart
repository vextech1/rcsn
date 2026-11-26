/// Where files are stored: the Cloudflare Worker in `worker/`, which guards a
/// private R2 bucket.
///
/// Set at build time:
///   flutter build apk --dart-define=STORAGE_URL=https://rcsn-files.<you>.workers.dev
class StorageConfig {
  StorageConfig._();

  static const String baseUrl = String.fromEnvironment('STORAGE_URL');
}
