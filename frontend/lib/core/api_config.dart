/// Backend base URL. Override at build/run time with
/// `--dart-define=API_BASE_URL=https://your-host/api/v1`; defaults to the
/// local FastAPI dev server.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000/api/v1',
);

/// Same host as [apiBaseUrl], over ws(s):// instead of http(s)://, for the
/// live status WebSocket.
final apiWsBaseUrl = apiBaseUrl.replaceFirst(RegExp(r'^http'), 'ws');
