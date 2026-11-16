import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'data/database.dart';
import 'data/repositories.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await NotificationService.init();
  } catch (_) {
    // The app remains usable locally if Android notification setup is denied.
  }

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
      final client = Supabase.instance.client;
      if (client.auth.currentSession == null) {
        // Anonymous Auth gives this installation a private owner_id for RLS.
        // Enable Anonymous Sign-Ins in the Supabase project before using sync.
        await client.auth.signInAnonymously();
      }
    } catch (_) {
      // Cloud sync is optional. The SQLite database remains the local source
      // of truth and the app must continue to open if cloud setup is absent.
    }
  }

  final database = AppDatabase();
  final repositories = Repos(database);
  final syncService = SyncService(database);

  try {
    await repositories.ensureCyclesForAllActiveLines();
  } catch (_) {}
  try {
    await NotificationService.refreshAll(database);
  } catch (_) {}
  syncService.startAutoSync();

  runApp(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: database),
        Provider<Repos>.value(value: repositories),
        Provider<SyncService>.value(value: syncService),
      ],
      child: const LineManagerApp(),
    ),
  );
}

class LineManagerApp extends StatelessWidget {
  const LineManagerApp({super.key});

  @override
  Widget build(BuildContext context) => const AppRoot();
}
