import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/name_screen.dart';
import 'screens/chat_screen.dart';

const supabaseUrl = 'https://glukgaobjsanjlyxowhl.supabase.co';
const supabasePublishableKey = 'sb_publishable_8zUnA4hDWb3MQsOj9c4M7Q_ulbv68vN';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  runApp(const OneChatApp());
}

class OneChatApp extends StatelessWidget {
  const OneChatApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'OneChat',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF536DFE), brightness: Brightness.light),
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF6F7FB), elevation: 0, centerTitle: false),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      ),
    ),
    home: const AuthGate(),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return const NameScreen();
    return const ChatScreen();
  }
}
