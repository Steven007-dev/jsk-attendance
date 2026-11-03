import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/app_store.dart';
import 'services/native_notifications_service.dart';
import 'screens/app_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  NativeNotificationsService.initialize();
  final store = AppStore();
  await store.initialize();
  runApp(
    ChangeNotifierProvider.value(value: store, child: const JSKAttendanceApp()),
  );
}

class JSKAttendanceApp extends StatelessWidget {
  const JSKAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) => Consumer<AppStore>(
    builder: (context, store, _) => MaterialApp(
      title: 'JSK Attendance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: store.isDark ? ThemeMode.dark : ThemeMode.light,
      home: const AppShell(),
    ),
  );
}
