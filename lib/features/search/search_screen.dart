import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/repositories.dart';
import '../customers/customer_detail_screen.dart';
import '../lines/line_detail_screen.dart';
import '../../data/database.dart';
class SearchScreen extends StatefulWidget { const SearchScreen({super.key}); @override State<SearchScreen> createState()=>_S(); }
class _S extends State<SearchScreen> {
  String q='';
  @override Widget build(BuildContext context){
    final repos=context.read<Repos>(); final db=context.read<AppDatabase>();
    return Scaffold(appBar: AppBar(title: const Text('بحث ذكي')), body: Column(children:[
      Padding(padding: const EdgeInsets.all(12), child: TextField(autofocus: true, decoration: const InputDecoration(hintText: 'اسم العميل، جزء من الاسم، رقم الخط، رقم التواصل، رقم الإيصال', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()), onChanged:(v)=>setState(()=>q=v))),
      Expanded(child: q.trim().isEmpty ? const Center(child: Text('اكتب اسماً أو رقم خط أو رقم إيصال')) : FutureBuilder<List<SearchHit>>(future: repos.globalSearch(q), builder:(c,snap){
        if(!snap.hasData) return const Center(child: CircularProgressIndicator());
        if(snap.data!.isEmpty) return const Center(child: Text('لا توجد نتائج'));
        return ListView(children: snap.data!.map((h){
          IconData icon = h.type=='customer'?Icons.person: h.type=='line'?Icons.phone: Icons.receipt;
          return Card(child: ListTile(leading: Icon(icon), title: Text(h.title), subtitle: Text(h.subtitle), onTap: () async {
            if(h.type=='customer' && h.customerId!=null){ final cu=await (db.select(db.customers)..where((x)=>x.id.equals(h.customerId!))).getSingle(); if(context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_)=>CustomerDetailScreen(customer: cu))); }
            else if(h.type=='line' && h.lineId!=null){ final ln=await (db.select(db.lines)..where((x)=>x.id.equals(h.lineId!))).getSingle(); if(context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_)=>LineDetailScreen(line: ln))); }
            else if(h.type=='payment' && h.lineId!=null){ final ln=await (db.select(db.lines)..where((x)=>x.id.equals(h.lineId!))).getSingle(); if(context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_)=>LineDetailScreen(line: ln))); }
          }));
        }).toList());
      })),
    ]));
  }
}
