import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/name_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/privacy_lock_gate.dart';
import 'theme_controller.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL',
    defaultValue: 'https://glukgaobjsanjlyxowhl.supabase.co');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_8zUnA4hDWb3MQsOj9c4M7Q_ulbv68vN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('theme_mode') ?? 'system';
  appThemeMode.value = ThemeMode.values.firstWhere(
    (mode) => mode.name == saved,
    orElse: () => ThemeMode.system,
  );
  if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
    runApp(const SetupRequiredApp());
    return;
  }
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  runApp(const OneChatApp());
}

class OneChatApp extends StatelessWidget {
  const OneChatApp({super.key});

  ThemeData _theme(Brightness brightness) {
    const accent = Color(0xFF11F3A6);
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      primary: accent,
      onPrimary: const Color(0xFF04251B),
      secondary: const Color(0xFF73FFD0),
      surface: dark ? const Color(0xFF111A1B) : Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF071110) : const Color(0xFFF2FAF7),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF071110) : const Color(0xFFF2FAF7),
        foregroundColor: dark ? const Color(0xFFE9FFF7) : const Color(0xFF10231D),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: dark ? const Color(0xFFE9FFF7) : const Color(0xFF10231D),
          fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: dark ? const Color(0xFF111E1B) : Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF14211D) : Colors.white,
        hintStyle: TextStyle(color: dark ? const Color(0xFF8BA49A) : const Color(0xFF80948B)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: accent, width: 1.4)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: const Color(0xFF04251B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: dark ? Colors.white.withOpacity(.07) : const Color(0xFFE2EEE8)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'GitrChat', debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light), darkTheme: _theme(Brightness.dark),
        themeMode: mode,
        home: StreamBuilder<AuthState>(
          stream: client.auth.onAuthStateChange,
          builder: (context, snapshot) => client.auth.currentSession == null
              ? const NameScreen() : const PrivacyLockGate(child: ChatScreen()),
        ),
      ),
    );
  }
}

class SetupRequiredApp extends StatelessWidget {
  const SetupRequiredApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(body: Center(child: Text('Нужно настроить Supabase'))));
}
