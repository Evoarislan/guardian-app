import 'package:material_ui/material_ui.dart';

import 'consent/consent.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const GuardianApp());
}

class GuardianApp extends StatefulWidget {
  const GuardianApp({super.key});

  @override
  State<GuardianApp> createState() => _GuardianAppState();
}

class _GuardianAppState extends State<GuardianApp> {
  // The one wearer-owned consent store (local demo state, no grants yet).
  final ConsentStore _consent = ConsentStore();

  @override
  void dispose() {
    _consent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) =>
          ConsentScope(store: _consent, child: child!),
      title: 'Guardian',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 18),
          bodyLarge: TextStyle(fontSize: 20),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
