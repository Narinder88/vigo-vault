import 'package:intl/intl.dart';

String formatNumber(int value) {
  return NumberFormat('###,###,###').format(value);
}

String formatNumberDouble(double value) {
  return NumberFormat('###,###,###.#').format(value);
}
