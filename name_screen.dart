import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import 'chat_screen.dart';

class NameScreen extends StatefulWidget {
  const NameScreen({super.key});
  @override
  State<NameScreen> createState() => _NameScreenState();
}
class _NameScreenState extends State<NameScreen> {
  final controller = TextEditingController();
  bool busy = false;
  String? error;
  Future<void> submit() async {
    final name = controller.text.trim();
    if (name.isEmpty || name.length > 24) { setState(() => error = 'Введите имя (до 24 символов)'); return; }
    setState(() { busy = true; error = null; });
    try {
      await ChatService().signIn(name);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ChatScreen()));
    } catch (e) { setState(() => error = 'Не удалось войти. Проверьте подключение и настройки Supabase.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Padding(
      padding: const EdgeInsets.all(28), child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.forum_rounded, size: 64, color: Color(0xFF536DFE)),
        const SizedBox(height: 20),
        const Text('Добро пожаловать в OneChat', textAlign: TextAlign.center, style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text('Один общий чат. Просто выберите имя.', textAlign: TextAlign.center),
        const SizedBox(height: 28),
        TextField(controller: controller, maxLength: 24, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'Ваше имя', prefixIcon: Icon(Icons.person_outline)), onSubmitted: (_) => submit()),
        if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 12),
        FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Входим…' : 'Продолжить')),
      ]),
    ))),
  );
}
