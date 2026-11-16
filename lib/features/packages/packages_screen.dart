import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/year_month.dart';
import '../../data/database.dart';
import '../../data/repositories.dart';
import '../../services/notification_service.dart';

class PackagesScreen extends StatefulWidget {
  const PackagesScreen({super.key});

  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final repos = context.read<Repos>();

    return Scaffold(
      appBar: AppBar(title: const Text('الباقات')),
      body: FutureBuilder<List<Package>>(
        future: (db.select(db.packages)..where((item) => item.deletedAt.isNull())).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('تعذر تحميل الباقات'));
          }
          final packages = snapshot.data ?? const <Package>[];
          if (packages.isEmpty) {
            return const Center(
              child: Text('لا توجد باقات بعد. أضف أول باقة لاستخدامها مع الخطوط.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: packages.length,
            itemBuilder: (context, index) {
              final package = packages[index];
              return Card(
                child: ListTile(
                  title: Text(package.name),
                  subtitle: Text(
                    '${Money.format(package.pricePiasters)} شهريًا'
                    '${package.isArchived ? ' — مؤرشفة' : ''}',
                  ),
                  trailing: PopupMenuButton<String>(
                    enabled: !_working,
                    onSelected: (value) {
                      if (value == 'edit') _editPrice(context, db, repos, package);
                      if (value == 'archive') _archive(context, repos, package);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('تعديل السعر')),
                      if (!package.isArchived)
                        const PopupMenuItem(value: 'archive', child: Text('أرشفة الباقة')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _working ? null : () => _add(context, repos),
        icon: const Icon(Icons.add),
        label: const Text('باقة جديدة'),
      ),
    );
  }

  Future<void> _add(BuildContext context, Repos repos) async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إضافة باقة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'اسم الباقة *'),
            ),
            TextField(
              controller: priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'السعر الشهري بالجنيه *'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final price = Money.parseEGP(priceController.text);
      if (nameController.text.trim().isEmpty || price == null || price <= 0) {
        _showMessage('أدخل اسم الباقة وسعرًا صحيحًا أكبر من صفر');
      } else {
        try {
          await repos.addPackage(nameController.text, price, null);
          if (mounted) setState(() {});
        } catch (error) {
          _showMessage('تعذرت إضافة الباقة: $error');
        }
      }
    }

    nameController.dispose();
    priceController.dispose();
  }

  Future<void> _editPrice(
    BuildContext context,
    AppDatabase db,
    Repos repos,
    Package package,
  ) async {
    final priceController = TextEditingController(
      text: Money.format(package.pricePiasters).replaceAll(' ج.م', ''),
    );
    final linkedLines = await (db.select(db.lines)
          ..where((line) => line.packageId.equals(package.id) & line.deletedAt.isNull()))
        .get();
    if (!context.mounted) {
      priceController.dispose();
      return;
    }

    final effective = YearMonth.nowCairo();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('تعديل سعر ${package.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('السعر الحالي: ${Money.format(package.pricePiasters)}'),
            Text('الخطوط المرتبطة: ${linkedLines.length}'),
            const SizedBox(height: 8),
            Text('سيبدأ السعر الجديد من ${effective.labelAr} على الشهور غير المسددة.'),
            TextField(
              controller: priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'السعر الجديد بالجنيه'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تأكيد التعديل'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final newPrice = Money.parseEGP(priceController.text);
      if (newPrice == null || newPrice <= 0) {
        _showMessage('أدخل سعرًا صحيحًا أكبر من صفر');
      } else {
        setState(() => _working = true);
        try {
          final affected = await repos.updatePackagePrice(
            packageId: package.id,
            newPrice: newPrice,
            effective: effective,
          );
          await NotificationService.refreshAll(db);
          if (mounted) {
            setState(() {});
            _showMessage('تم تحديث الباقة. عدد الاستحقاقات التي تغيرت: $affected');
          }
        } catch (error) {
          _showMessage('تعذر تعديل السعر: $error');
        } finally {
          if (mounted) setState(() => _working = false);
        }
      }
    }
    priceController.dispose();
  }

  Future<void> _archive(
    BuildContext context,
    Repos repos,
    Package package,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('أرشفة الباقة؟'),
        content: const Text(
          'لن تُحذف الخطوط أو المدفوعات القديمة. لن تظهر الباقة في اختيارات الخطوط الجديدة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('أرشفة'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _working = true);
    try {
      await repos.archivePackage(package.id);
      if (mounted) setState(() {});
    } catch (error) {
      _showMessage('تعذرت أرشفة الباقة: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
