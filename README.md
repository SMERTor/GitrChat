# OneChat — Flutter + Supabase

## Запуск
1. Установите Flutter SDK и Android Studio.
2. Распакуйте архив и откройте папку `onechat_flutter_rebuilt` в Android Studio или VS Code.
3. В терминале выполните:
   ```bash
   flutter pub get
   flutter run
   ```

## Supabase
Проект уже настроен на подключённый Supabase:
- URL: `https://glukgaobjsanjlyxowhl.supabase.co`
- Используется публичный publishable key, предназначенный для клиентского приложения.
- В Supabase должны быть включены Anonymous Sign-Ins: Authentication → Sign In / Providers → Anonymous.

Таблицы `profiles` и `messages`, RLS-политики и публикация Realtime для сообщений уже созданы в Supabase.

## Возможности
- Вход по имени через анонимную авторизацию
- Общая лента сообщений
- Отправка и удаление собственных сообщений
- Базовый индикатор присутствия

Примечание: это стартовый проект. Перед публикацией добавьте полноценную обработку ошибок, модерацию и защиту от спама. Онлайн-индикатор здесь базовый; typing indicator и постоянные аватары требуют дальнейшей доработки.
