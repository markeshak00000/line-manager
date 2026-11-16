import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import 'customer_detail_screen.dart';
class CustomersScreen extends StatefulWidget { const CustomersScreen({super.key}); @override State<CustomersScreen> createState()=>_S(); }
class _S extends State<CustomersScreen> {
  String _q=''; final _search=TextEditingController();
  @override Widget build(BuildContext context) {
    final repos = context.read<Repos>();
    return Scaffold(appBar: AppBar(title: const Text('العملاء')), body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: TextField(controller: _search, decoration: InputDecoration(hintText: 'ابحث بالاسم أو جزء من الاسم أو رقم الخط أو رقم التواصل', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), onChanged: (v)=>setState(()=>_q=v))),
      Expanded(child: FutureBuilder<List<SearchHit>>(future: _q.trim().isEmpty ? Future.value([]) : repos.globalSearch(_q), builder: (c, snap) {
        if (_q.trim().isEmpty) {
          return FutureBuilder<List<Customer>>(future: repos.searchCustomers(''), builder: (c2, s2){ if(!s2.hasData) return const Center(child: CircularProgressIndicator()); if(s2.data!.isEmpty) return const Center(child: Text('لا يوجد عملاء بعد. اضغط + لإضافة أول عميل.')); return ListView.builder(itemCount: s2.data!.length, itemBuilder: (c,i){ final cu=s2.data![i]; return FutureBuilder<List<Line>>(future: repos.linesForCustomer(cu.id), builder: (c3, ls){ final n=ls.data?.length??0; return Card(child: ListTile(title: Text(cu.name), subtitle: Text('${cu.phone??'بدون رقم'} • $n خط'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.edit), onPressed: ()=>_editCustomer(context, repos, cu)), const Icon(Icons.arrow_forward_ios, size:16)]), onTap: ()=>Navigator.push(context, MaterialPageRoute(builder: (_)=>CustomerDetailScreen(customer: cu)))); }); }); });
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.data!.isEmpty) return const Center(child: Text('لا توجد نتائج'));
        return ListView(children: snap.data!.map((h)=>Card(child: ListTile(title: Text(h.title), subtitle: Text(h.subtitle), onTap: () async { if(h.customerId!=null){ final db=context.read<AppDatabase>(); final cu=await (db.select(db.customers)..where((x)=>x.id.equals(h.customerId!))).getSingle(); if(context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_)=>CustomerDetailScreen(customer: cu))); } }))).toList());
      })),
    ]), floatingActionButton: FloatingActionButton.extended(onPressed: ()=>_addCustomer(context, repos), icon: const Icon(Icons.add), label: const Text('عميل جديد')));
  }
  Future<void> _addCustomer(BuildContext ctx, Repos repos) async {
    final name=TextEditingController(); final phone=TextEditingController(); final wa=TextEditingController(); final addr=TextEditingController(); final notes=TextEditingController();
    final ok = await showDialog<bool>(context: ctx, builder: (c)=>AlertDialog(title: const Text('إضافة عميل'), content: SingleChildScrollView(child: Column(children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم العميل *')), TextField(controller: phone, decoration: const InputDecoration(labelText: 'رقم موبايل (اختياري)'), keyboardType: TextInputType.phone), TextField(controller: wa, decoration: const InputDecoration(labelText: 'رقم واتساب (اختياري)'), keyboardType: TextInputType.phone), TextField(controller: addr, decoration: const InputDecoration(labelText: 'العنوان (اختياري)')), TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'))])), actions: [TextButton(onPressed: ()=>Navigator.pop(c,false), child: const Text('إلغاء')), ElevatedButton(onPressed: ()=>Navigator.pop(c,true), child: const Text('حفظ'))]));
    if (ok==true && name.text.trim().isNotEmpty) { await repos.addCustomer(name: name.text.trim(), phone: phone.text.trim().isEmpty?null:phone.text.trim(), whatsapp: wa.text.trim().isEmpty?null:wa.text.trim(), address: addr.text.trim().isEmpty?null:addr.text.trim(), notes: notes.text.trim().isEmpty?null:notes.text.trim()); if (mounted) { setState((){}); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إضافة العميل بنجاح'))); } }
  }
  Future<void> _editCustomer(BuildContext ctx, Repos repos, Customer cu) async {
    final name=TextEditingController(text: cu.name); final phone=TextEditingController(text: cu.phone??''); final wa=TextEditingController(text: cu.whatsapp??''); final addr=TextEditingController(text: cu.address??''); final notes=TextEditingController(text: cu.notes??'');
    final ok = await showDialog<bool>(context: ctx, builder: (c)=>AlertDialog(title: const Text('تعديل بيانات العميل'), content: SingleChildScrollView(child: Column(children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم العميل *')), TextField(controller: phone, decoration: const InputDecoration(labelText: 'رقم موبايل')), TextField(controller: wa, decoration: const InputDecoration(labelText: 'رقم واتساب')), TextField(controller: addr, decoration: const InputDecoration(labelText: 'العنوان')), TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات'))])), actions: [TextButton(onPressed: ()=>Navigator.pop(c,false), child: const Text('إلغاء')), ElevatedButton(onPressed: ()=>Navigator.pop(c,true), child: const Text('حفظ'))]));
    if (ok==true) { await repos.updateCustomer(id: cu.id, name: name.text.trim(), phone: phone.text.trim().isEmpty?null:phone.text.trim(), whatsapp: wa.text.trim().isEmpty?null:wa.text.trim(), address: addr.text.trim().isEmpty?null:addr.text.trim(), notes: notes.text.trim().isEmpty?null:notes.text.trim()); if (mounted) { setState((){}); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تعديل بيانات العميل'))); } }
  }
}
