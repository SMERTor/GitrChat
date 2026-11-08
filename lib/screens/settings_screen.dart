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
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ValueListenableBuilder<ThemeMode>(
        valueListenable: appThemeMode,
        builder: (context, mode, _) => ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text('Оформление', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(child: Column(children: [
              RadioListTile<ThemeMode>(value: ThemeMode.system, groupValue: mode,
                title: const Text('Как в телефоне'), secondary: const Icon(Icons.settings_suggest),
                onChanged: (v) { if (v != null) _setTheme(v); }),
              RadioListTile<ThemeMode>(value: ThemeMode.light, groupValue: mode,
                title: const Text('Светлая'), secondary: const Icon(Icons.light_mode_outlined),
                onChanged: (v) { if (v != null) _setTheme(v); }),
              RadioListTile<ThemeMode>(value: ThemeMode.dark, groupValue: mode,
                title: const Text('Тёмная'), secondary: const Icon(Icons.dark_mode_outlined),
                onChanged: (v) { if (v != null) _setTheme(v); }),
            ])),
            const SizedBox(height: 18),
            const ListTile(
              leading: Icon(Icons.storage_outlined),
              title: Text('Медиа и кэш'),
              subtitle: Text('Фото и видеосообщения сохраняются в локальный кэш телефона после просмотра.'),
            ),
          ],
        ),
      ),
    );
  }
}
