import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _setTheme(ThemeMode mode) async {
    appThemeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? const Color(0xFF91A69D) : const Color(0xFF71877D);
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ValueListenableBuilder<ThemeMode>(
        valueListenable: appThemeMode,
        builder: (context, mode, _) => ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF123B2E), Color(0xFF0D211B), Color(0xFF111A1B)],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFF11F3A6).withOpacity(.24)),
              ),
              child: Row(children: [
                Container(width: 58, height: 58,
                  decoration: const BoxDecoration(color: Color(0xFF11F3A6), shape: BoxShape.circle),
                  child: const Icon(Icons.forum_rounded, color: Color(0xFF04251B), size: 29)),
                const SizedBox(width: 16),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('GitrChat', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text('Личное пространство для двоих', style: TextStyle(color: Color(0xFFB8D9CC), fontSize: 13)),
                ])),
                const Icon(Icons.verified_rounded, color: Color(0xFF11F3A6)),
              ]),
            ),
            const SizedBox(height: 28),
            Text('ВНЕШНИЙ ВИД', style: TextStyle(fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w800, color: muted)),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: dark ? Colors.white.withOpacity(.06) : const Color(0xFFE0EEE8)),
              ),
              child: Column(children: [
                _ThemeTile(icon: Icons.brightness_auto_rounded, title: 'Системная тема',
                  subtitle: 'Как на устройстве', selected: mode == ThemeMode.system,
                  onTap: () => _setTheme(ThemeMode.system)),
                Divider(height: 1, indent: 60, endIndent: 16, color: muted.withOpacity(.15)),
                _ThemeTile(icon: Icons.light_mode_rounded, title: 'Светлая',
                  subtitle: 'Чистая и воздушная', selected: mode == ThemeMode.light,
                  onTap: () => _setTheme(ThemeMode.light)),
                Divider(height: 1, indent: 60, endIndent: 16, color: muted.withOpacity(.15)),
                _ThemeTile(icon: Icons.dark_mode_rounded, title: 'Тёмная',
                  subtitle: 'Комфортная в темноте', selected: mode == ThemeMode.dark,
                  onTap: () => _setTheme(ThemeMode.dark)),
              ]),
            ),
            const SizedBox(height: 28),
            Text('ХРАНЕНИЕ', style: TextStyle(fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w800, color: muted)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: dark ? Colors.white.withOpacity(.06) : const Color(0xFFE0EEE8)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 42, height: 42,
                  decoration: BoxDecoration(color: const Color(0xFF11F3A6).withOpacity(.14), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.offline_pin_rounded, color: Color(0xFF11B982))),
                const SizedBox(width: 14),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Локальная история', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  SizedBox(height: 5),
                  Text('Прочитанные сообщения сохраняются на телефоне. При синхронизации загружаются только новые сообщения и изменения.',
                    style: TextStyle(fontSize: 12, height: 1.45, color: Color(0xFF8A9C94))),
                ])),
              ]),
            ),
            const SizedBox(height: 28),
            Text('О ПРИЛОЖЕНИИ', style: TextStyle(fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w800, color: muted)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: dark ? Colors.white.withOpacity(.06) : const Color(0xFFE0EEE8)),
              ),
              child: Row(children: [
                const Icon(Icons.chat_bubble_rounded, color: Color(0xFF11B982)),
                const SizedBox(width: 12),
                const Expanded(child: Text('GitrChat', style: TextStyle(fontWeight: FontWeight.w700))),
                Text('Версия 1.1.0', style: TextStyle(color: muted, fontSize: 12)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.icon, required this.title, required this.subtitle,
    required this.selected, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    leading: Container(width: 40, height: 40,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF11F3A6).withOpacity(.17) : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(13)),
      child: Icon(icon, color: selected ? const Color(0xFF11B982) : Theme.of(context).colorScheme.onSurfaceVariant)),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
    trailing: selected ? const Icon(Icons.check_circle_rounded, color: Color(0xFF11B982)) : const Icon(Icons.chevron_right_rounded),
  );
}
