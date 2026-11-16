import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/money.dart';
import '../../core/year_month.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../customers/customers_screen.dart';
import '../payments/payment_form.dart';
import '../overdue/overdue_screen.dart';
import '../search/search_screen.dart';
class DashboardScreen extends StatefulWidget { const DashboardScreen({super.key}); @override State<DashboardScreen> createState()=>_S(); }
class _S extends State<DashboardScreen> {
  @override void initState(){ super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) async { final repos=context.read<Repos>(); await repos.ensureCyclesForAllActiveLines(); if(mounted) setState((){}); }); }
  @override Widget build(BuildContext context) {
    final db = context.read<AppDatabase>(); final repos = context.read<Repos>();
    final now = YearMonth.nowCairo();
    return Scaffold(appBar: AppBar(title: const Text('الرئيسية'), actions: [IconButton(icon: const Icon(Icons.search), tooltip: 'بحث', onPressed: ()=>Navigator.push(context, MaterialPageRoute(builder: (_)=>const SearchScreen())))]), body: RefreshIndicator(onRefresh: () async { await repos.ensureCyclesForAllActiveLines(); setState((){}); }, child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FutureBuilder<List<dynamic>>(
        future: Future.wait([db.select(db.customers).get(), db.select(db.lines).get(), db.select(db.billingCycles).get(), db.select(db.payments).get()]),
        builder: (c, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final customers = (snap.data![0] as List<Customer>).where((c)=>c.deletedAt==null && !c.isArchived).toList(); final lines = (snap.data![1] as List<Line>).where((l)=>l.deletedAt==null).toList(); final cycles = snap.data![2] as List<BillingCycle>; final pays = snap.data![3] as List<Payment>;
          final activeLines = lines.where((l)=>l.status=='active' && l.deletedAt==null).length;
          final thisMonthCycles = cycles.where((x)=>x.year==now.year&&x.month==now.month);
          final paidThisMonth = thisMonthCycles.where((x)=>x.status=='paid').length;
          final unpaid = thisMonthCycles.where((x)=>x.status!='paid').length;
          final collectedMonth = pays.where((p)=>!p.isVoided && p.paidAt.year==now.year && p.paidAt.month==now.month).fold(0,(s,p)=>s+p.amountPiasters);
          // FIXED: arrears only up to current month, future not counted
          final arrears = cycles.where((x)=> YearMonth(x.year,x.month).compareTo(now) <= 0).fold<int>(0,(s,x)=>s+(x.pricePiasters-x.paidPiasters).clamp(0, 1 << 62).toInt());
          final today = DateTime.now(); final collectedToday = pays.where((p)=>!p.isVoided && p.paidAt.year==today.year&&p.paidAt.month==today.month&&p.paidAt.day==today.day).fold(0,(s,p)=>s+p.amountPiasters);
          return Column(children: [
            Wrap(spacing: 12, runSpacing: 12, children: [
              _card('إجمالي العملاء', '${customers.length}'),
              _card('الخطوط النشطة', '$activeLines'),
              _card('تم تحصيلها هذا الشهر', '$paidThisMonth'),
              _card('لم تدفع', '$unpaid'),
              _card('المحصّل هذا الشهر', Money.format(collectedMonth)),
              _card('إجمالي المتأخرات', Money.format(arrears)),
              _card('المحصّل اليوم', Money.format(collectedToday)),
            ]),
            const SizedBox(height: 16),
            if (arrears>0) Card(color: Colors.red.shade50, child: ListTile(leading: const Icon(Icons.warning, color: Colors.red), title: Text('يوجد متأخرات: ${Money.format(arrears)}'), subtitle: const Text('اضغط لعرض الخطوط المتأخرة'), onTap: ()=>Navigator.push(context, MaterialPageRoute(builder: (_)=>const OverdueScreen())))),
          ]);
        }),
      const SizedBox(height: 16),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _action(context, 'إضافة عميل', Icons.person_add, ()=>Navigator.push(context, MaterialPageRoute(builder: (_)=>const CustomersScreen()))),
        _action(context, 'تسجيل دفعة', Icons.payments, ()=>Navigator.push(context, MaterialPageRoute(builder: (_)=>const PaymentFormScreen()))),
        _action(context, 'بحث', Icons.search, ()=>Navigator.push(context, MaterialPageRoute(builder: (_)=>const SearchScreen()))),
        _action(context, 'المتأخرات', Icons.warning, ()=>Navigator.push(context, MaterialPageRoute(builder: (_)=>const OverdueScreen()))),
      ]),
      const SizedBox(height: 16),
      const Text('آخر العمليات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      FutureBuilder<List<Payment>>(future: repos.recentPayments(limit: 10), builder: (c, snap) {
        if (!snap.hasData) return const SizedBox();
        if (snap.data!.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('لا توجد عمليات بعد. ابدأ بإضافة أول عميل: أضف باقة > أضف عميل > أضف خط > سجّل دفعة.')));
        return Column(children: snap.data!.map((p)=>Card(child: ListTile(title: Text('دفعة ${Money.format(p.amountPiasters)}'), subtitle: Text('${p.paidAt.day}/${p.paidAt.month}/${p.paidAt.year} — ${p.method} — إيصال ${p.receiptNumber}'), trailing: Text(p.isVoided?'ملغاة':'ناجحة')))).toList());
      }),
    ]))));
  }
  Widget _card(String t, String v)=>SizedBox(width: 160, child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(color: Colors.black54)), const SizedBox(height: 6), Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]))));
  Widget _action(BuildContext ctx, String t, IconData i, VoidCallback onTap)=>ElevatedButton.icon(onPressed: onTap, icon: Icon(i), label: Text(t));
}
