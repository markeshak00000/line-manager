class YearMonth implements Comparable<YearMonth> {
  final int year; final int month;
  const YearMonth(this.year, this.month);
  factory YearMonth.nowCairo() { final n = DateTime.now(); return YearMonth(n.year, n.month); }
  factory YearMonth.fromDate(DateTime d) => YearMonth(d.year, d.month);
  YearMonth addMonths(int n) { final total = (year*12 + (month-1)) + n; return YearMonth(total~/12, total%12+1); }
  YearMonth next() => addMonths(1);
  YearMonth prev() => addMonths(-1);
  bool get isFuture { final now = YearMonth.nowCairo(); return compareTo(now) > 0; }
  bool get isPast { final now = YearMonth.nowCairo(); return compareTo(now) < 0; }
  String get labelAr { const names=['','يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر']; return '${names[month]} $year'; }
  String get key => '$year-${month.toString().padLeft(2,'0')}';
  DateTime get firstDay => DateTime(year, month, 1);
  DateTime get lastDay => DateTime(year, month+1, 0); // handles leap year correctly
  DateTime get dueDate => DateTime(year, month+1, 1); // due at start of next month
  @override int compareTo(YearMonth o) => year!=o.year ? year.compareTo(o.year) : month.compareTo(o.month);
  @override bool operator ==(Object o) => o is YearMonth && o.year==year && o.month==month;
  @override int get hashCode => year*100+month;
  @override String toString() => labelAr;
}
