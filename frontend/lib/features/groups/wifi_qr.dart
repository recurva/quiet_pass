/// Builds the standard `WIFI:` QR payload a phone's own camera (Android's
/// built-in scanner, iOS's Camera app) recognizes and offers to join —
/// this app never joins the network itself; see wifi_page.dart's banner.
///
/// Per the format, `\`, `;`, `,`, `:`, and `"` inside a field must be
/// backslash-escaped so they aren't read as field separators. WPA is
/// assumed for `T:` — the backend only stores one ssid/password pair with
/// no separate "security type" field, and WPA/WPA2 covers the
/// overwhelming majority of home networks; open (no-password) networks
/// aren't representable by this form today (password is required).
String buildWifiQrPayload({required String ssid, required String password}) {
  return 'WIFI:T:WPA;S:${_escape(ssid)};P:${_escape(password)};;';
}

String _escape(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll(':', r'\:')
      .replaceAll('"', r'\"');
}
