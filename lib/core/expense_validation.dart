/// Matches the shared backend's decimal precision and ten-digit amount limit.
/// The business must approve any lower per-expense limit in its financial policy.
bool isValidExpenseAmount(String value, {bool allowZero = false}) {
  if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(value)) return false;
  final amount = num.tryParse(value);
  return amount != null &&
      amount.isFinite &&
      (allowZero ? amount >= 0 : amount > 0) &&
      amount <= 9999999999.99;
}
