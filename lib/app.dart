import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/customers/customers_screen.dart';
import 'features/payments/payment_form.dart';
import 'features/reports/reports_screen.dart';
import 'features/settings/settings_screen.dart';
class AppRoot extends StatefulWidget { const AppRoot({super.key}); @override State<AppRoot> createState()=>_AppRootState(); }
class _AppRootState extends State<AppRoot> {
  int _idx=0; ThemeMode _mode=ThemeMode.system;
  @override void initState(){ super.initState(); _loadTheme(); }
  Future<void> _loadTheme() async { final p=await SharedPreferences.getInstance(); final v=p.getString('theme_mode')??'system'; setState(()=>_mode= v=='light'?ThemeMode.light: v=='dark'?ThemeMode.dark: ThemeMode.system); }
  Future<void> _setTheme(ThemeMode m) async { final p=await SharedPreferences.getInstance(); await p.setString('theme_mode', m==ThemeMode.light?'light': m==ThemeMode.dark?'dark':'system'); setState(()=>_mode=m); }
  @override Widget build(BuildContext context) {
    return MaterialApp(
      title: 'إدارة خطوط العملاء', debugShowCheckedModeBanner: false,
      locale: const Locale('ar'), supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      theme: AppTheme.light(), darkTheme: AppTheme.dark(), themeMode: _mode,
      home: Scaffold(
        body: IndexedStack(index: _idx, children: [const DashboardScreen(), const CustomersScreen(), const PaymentFormScreen(), const ReportsScreen(), SettingsScreen(onThemeChanged: _setTheme, currentMode: _mode)]),
        bottomNavigationBar: NavigationBar(selectedIndex: _idx, onDestinationSelected: (i)=>setState(()=>_idx=i), destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.people), label: 'العملاء'),
          NavigationDestination(icon: Icon(Icons.payments), label: 'التحصيل'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'التقارير'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'الإعدادات'),
        ]),
      ),
    );
  }
}
