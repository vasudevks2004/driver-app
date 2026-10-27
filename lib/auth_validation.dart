/// Accepts a formatted international number, or a local number with a country.
String? normalizePhone(String input, {String countryCode = '+91'}) {
  final trimmed = input.trim();
  if (RegExp(r'[^0-9+()\s-]').hasMatch(trimmed)) return null;
  var value = trimmed.replaceAll(RegExp(r'[()\s-]'), '');
  if (value.startsWith('00')) value = '+${value.substring(2)}';
  if (!value.startsWith('+')) {
    if (countryCode == '+91' && value.startsWith('0')) {
      value = value.substring(1);
    }
    value = '$countryCode$value';
  }
  if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value)) return null;
  if (value.startsWith('+91') && !RegExp(r'^\+91[6-9]\d{9}$').hasMatch(value)) {
    return null;
  }
  return value;
}

bool isValidEmail(String input) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(input.trim());

bool isValidOtp(String input) => RegExp(r'^\d{6}$').hasMatch(input.trim());
