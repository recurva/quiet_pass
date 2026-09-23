/// Shared input validation, used wherever a display name or phone number is
/// collected client-side (name_sheet.dart, phone_entry_page.dart). These are
/// a UX convenience only — the backend enforces the same rules again on
/// every request (see UserUpdate/SignInRequest in app/schemas), since a
/// client-side check can always be bypassed.
library;

/// Matches DISPLAY_NAME_MAX_LENGTH in app/schemas/user.py.
const displayNameMaxLength = 60;

final _lettersAndSpacesOnly = RegExp(r'^[a-zA-Z ]+$');

/// Returns a user-facing error, or null if [value] is a valid name. Trims
/// first — so a name that's only whitespace reads as empty, and a name
/// typed with a leading/trailing space (e.g. " Sam") is saved as just the
/// letters, same as the backend's own validator — then rejects anything
/// but letters and (single, internal) spaces: no digits, no punctuation.
String? validateDisplayName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Enter a name.';
  if (trimmed.length > displayNameMaxLength) {
    return 'Name must be $displayNameMaxLength characters or fewer.';
  }
  if (!_lettersAndSpacesOnly.hasMatch(trimmed)) {
    return 'Name can only contain letters and spaces.';
  }
  return null;
}

/// India-only national number: exactly 10 digits, not starting with 0
/// (matches how Indian mobile numbers are actually allocated — the
/// TextField's own digitsOnly formatter already excludes anything
/// non-numeric, so this only needs to check length and the leading digit).
String? validateNationalPhoneNumber(String nationalNumber) {
  if (nationalNumber.isEmpty) return 'Enter your phone number.';
  if (!RegExp(r'^[6-9]\d{9}$').hasMatch(nationalNumber)) {
    return 'Enter a valid 10-digit mobile number.';
  }
  return null;
}
