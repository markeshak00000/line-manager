import 'package:intl/intl.dart';
import 'money.dart';
class Fmt {
  static final _date = DateFormat('dd/MM/yyyy');
  static final _dateTime = DateFormat('dd/MM/yyyy - hh:mm a', 'ar');
  static String date(DateTime d) => _date.format(d);
  static String dateTime(DateTime d) => _dateTime.format(d);
  static String money(int p) => Money.format(p);
}
