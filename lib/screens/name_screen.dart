import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/account_service.dart';

class NameScreen extends StatefulWidget {
  const NameScreen({super.key});

  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _run(bool create) async {
    if (_loading) return;
    final name = _name.text.trim();
    final pin = _pin.text.trim();
    if (name.isEmpty || pin.length != 6) {
      setState(() => _error = 'Введите имя и PIN из 6 цифр.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final client = Supabase.instance.client;
    try {
      final accounts = AccountService(client);
      if (create) {
        await accounts.createOrLink(name, pin);
      } else {
        await accounts.signIn(name, pin);
      }
    } catch (e) {
      if (mounted) {
        final message = e.toString();
        setState(() => _error = create
          ? (message.contains('name_already_claimed')
              ? 'Это имя уже занято. Войдите в существующий аккаунт.'
              : 'Не удалось создать аккаунт. Проверьте имя, PIN и подключение.')
          : 'Аккаунт не найден или PIN неверный. Если вы здесь впервые, создайте аккаунт ниже.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmCreate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Создать новый аккаунт?'),
        content: const Text('Сначала приложение попробует войти в существующий аккаунт. Новый будет создан только по вашему отдельному подтверждению.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Создать')),
        ],
      ),
    );
    if (confirmed == true) await _run(true);
  }

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(26),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 88, width: 88, alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0xFF11F3A6), borderRadius: BorderRadius.circular(28)),
                    child: const Icon(Icons.forum_rounded, size: 42, color: Color(0xFF04251B)),
                  ),
                  const SizedBox(height: 28),
                  const Text('GitrChat', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text('Войдите в свой прежний аккаунт. Имя и PIN помогут восстановить его на другом устройстве.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15)),
                  const SizedBox(height: 30),
                  TextField(
                    controller: _name, maxLength: 24,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'Имя аккаунта',
                      prefixIcon: Icon(Icons.person_outline_rounded), counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pin, maxLength: 6, obscureText: true,
                    keyboardType: TextInputType.number, textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _run(false),
                    decoration: const InputDecoration(
                      hintText: 'PIN из 6 цифр',
                      prefixIcon: Icon(Icons.lock_outline_rounded), counterText: '',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _loading ? null : () => _run(false),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 17)),
                    child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Войти в существующий аккаунт'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _loading ? null : _confirmCreate,
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: const Text('Создать новый аккаунт'),
                  ),
                  const SizedBox(height: 14),
                  Text('Новый аккаунт не создаётся автоматически при ошибке входа.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
