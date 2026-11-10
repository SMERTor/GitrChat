import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:video_compress/video_compress.dart';

import '../models/chat_message.dart';
import '../services/chat_service.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();
  late final SupabaseClient _client;
  late final ChatService _service;
  late final String _myId;
  RealtimeChannel? _channel;
  StreamSubscription<List<Map<String, dynamic>>>? _messageSub;
  List<ChatMessage> _messages = [];
  final Set<String> _typingUsers = {};
  int _onlineCount = 1;
  final Set<String> _onlineUserIds = {};
  Timer? _lastSeenTimer;
  bool _loading = true, _sending = false;
  Timer? _typingTimer;
  bool _typingSent = false;

  @override
  void initState() {
    super.initState();
    _client = Supabase.instance.client;
    _service = ChatService(_client);
    _myId = _client.auth.currentUser!.id;
    _start();
  }

  String get _cacheKey => 'gitrchat_messages_$_myId';

  Future<void> _saveLocalMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final recent = _messages.length > 1000 ? _messages.sublist(_messages.length - 1000) : _messages;
    await prefs.setString(_cacheKey, jsonEncode(recent.map((m) => m.toCacheMap()).toList()));
  }

  Future<void> _syncNewMessages() async {
    try {
      final last = _messages.isEmpty ? null : _messages.last.createdAt;
      final incoming = await _service.loadMessages(after: last);
      if (incoming.isEmpty) return;
      final ids = _messages.map((m) => m.id).toSet();
      final fresh = incoming.where((m) => !ids.contains(m.id)).toList();
      if (fresh.isEmpty) return;
      if (mounted) setState(() => _messages = [..._messages, ...fresh]);
      await _saveLocalMessages();
      _jumpToBottom();
    } catch (_) { /* cached messages remain available offline */ }
  }

  Future<void> _start() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_cacheKey);
      if (saved != null) {
        final decoded = (jsonDecode(saved) as List).cast<Map<String, dynamic>>();
        _messages = decoded.map(ChatMessage.fromCacheMap).toList();
        if (mounted) setState(() {});
      }
      // Only the first run downloads history. Later runs request rows newer than
      // the newest locally cached message, never the already cached history.
      await _syncNewMessages();
      if (_messages.isEmpty) {
        final initial = await _service.loadMessages();
        if (mounted) setState(() => _messages = initial);
        await _saveLocalMessages();
      }
      _subscribeMessages();
      _subscribePresence();
      await _service.updateLastSeen();
      _lastSeenTimer?.cancel();
      _lastSeenTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _service.updateLastSeen();
      });
    } catch (_) {
      if (mounted && _messages.isEmpty) _error('Нет подключения. Локальная история появится после первой синхронизации.');
    } finally {
      if (mounted) setState(() => _loading = false);
      _jumpToBottom();
    }
  }

  void _subscribeMessages() {
    _messageSub = _client.from('messages').stream(primaryKey: ['id'])
      .listen((_) => _syncNewMessages());
  }

  void _subscribePresence() {
    final channel = _client.channel('public:onechat', opts: const RealtimeChannelConfig(self: true));
    _channel = channel;
    channel.onPresenceSync((_) { if (mounted) _refreshPresenceCount(); })
      .onBroadcast(event: 'typing', callback: (payload) {
        final id = payload['user_id']?.toString();
        if (id == null || id == _myId || !mounted) return;
        setState(() {
          if (payload['is_typing'] == true) { _typingUsers.add(id); }
          else { _typingUsers.remove(id); }
        });
      }).subscribe((status, error) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await channel.track({'user_id': _myId, 'online_at': DateTime.now().toIso8601String()});
          _refreshPresenceCount();
        }
      });
  }

  Future<void> _refreshPresenceCount() async {
    final channel = _channel;
    if (channel == null) return;
    final states = channel.presenceState();
    final ids = <String>{};
    for (final state in states) {
      for (final presence in state.presences) {
        final payload = presence.payload;
        final id = payload['user_id']?.toString();
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }
    if (mounted) {
      setState(() {
        _onlineUserIds
          ..clear()
          ..addAll(ids);
        _onlineCount = ids.length;
      });
    }
  }

  Future<void> _showOnlineUsers() async {
    try {
      final profiles = await _service.loadProfiles();
      if (!mounted) return;
      final onlineIds = Set<String>.from(_onlineUserIds);
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Участники чата',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                ...profiles.map((profile) {
                  final id = profile['id']?.toString() ?? '';
                  final name = profile['name']?.toString() ?? 'Пользователь';
                  final isOnline = onlineIds.contains(id);
                  final rawLastSeen = profile['last_seen_at']?.toString();
                  final lastSeen = rawLastSeen == null
                      ? null : DateTime.tryParse(rawLastSeen)?.toLocal();
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          backgroundColor: const Color(0xFF11F3A6).withOpacity(.16),
                          foregroundColor: const Color(0xFF11A879),
                          child: Text(_initials(name)),
                        ),
                        Positioned(
                          right: 0, bottom: 0,
                          child: Container(
                            width: 11, height: 11,
                            decoration: BoxDecoration(
                              color: isOnline ? const Color(0xFF11F3A6) : Colors.grey,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(sheetContext).scaffoldBackgroundColor,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(isOnline
                        ? 'В сети'
                        : lastSeen == null
                            ? 'Время последнего посещения неизвестно'
                            : 'Был(а) ${_lastSeenLabel(lastSeen)}'),
                    trailing: isOnline
                        ? const Text('Онлайн', style: TextStyle(
                            color: Color(0xFF11B982), fontWeight: FontWeight.w700))
                        : null,
                  );
                }),
                if (profiles.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('Пока нет участников'),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) _error('Не удалось загрузить список участников.');
    }
  }

  String _lastSeenLabel(DateTime value) {
    final now = DateTime.now();
    final difference = now.difference(value);
    if (difference.inMinutes < 1) return 'только что';
    if (difference.inMinutes < 60) return '${difference.inMinutes} мин. назад';
    if (difference.inHours < 24) return '${difference.inHours} ч. назад';
    if (difference.inDays == 1) return 'вчера в ${_time(value)}';
    return '${value.day.toString().padLeft(2, '0')}.'
        '${value.month.toString().padLeft(2, '0')} '
        'в ${_time(value)}';
  }

  void _onTextChanged(String value) {
    final channel = _channel;
    if (channel == null) return;
    if (value.trim().isNotEmpty && !_typingSent) {
      _typingSent = true;
      channel.sendBroadcastMessage(event: 'typing', payload: {'user_id': _myId, 'is_typing': true});
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), _stopTyping);
  }

  void _stopTyping() {
    _typingTimer?.cancel();
    if (_typingSent) {
      _typingSent = false;
      _channel?.sendBroadcastMessage(event: 'typing', payload: {'user_id': _myId, 'is_typing': false});
    }
  }

  Future<void> _send() async {
    if (_sending || _text.text.trim().isEmpty) return;
    final value = _text.text;
    _text.clear();
    setState(() => _sending = true);
    try { await _service.sendMessage(value); _stopTyping(); }
    catch (_) { if (mounted) _error('Не удалось отправить сообщение.'); _text.text = value; }
    finally { if (mounted) setState(() => _sending = false); }
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 68, maxWidth: 1600, maxHeight: 1600);
      if (picked != null) await _upload(File(picked.path), 'image');
    } catch (_) { if (mounted) _error('Не удалось выбрать фотографию.'); }
  }

  Future<void> _recordCircle() async {
    try {
      final file = await Navigator.of(context).push<File>(
        MaterialPageRoute(builder: (_) => const CircleRecorderScreen()),
      );
      if (file != null && mounted) {
        await _upload(file, 'video_circle');
      }
    } catch (_) {
      if (mounted) _error('Не удалось записать видеосообщение.');
    }
  }

  Future<void> _upload(File file, String type, {int? duration}) async {
    if (mounted) setState(() => _sending = true);
    File uploadFile = file;
    String? compressedPath;
    try {
      // ImagePicker has already produced a resized JPEG for photos.
      // Re-encode video to a mobile-friendly 720p profile before upload.
      if (type == 'video_circle') {
        final info = await VideoCompress.compressVideo(
          file.path,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
          includeAudio: true,
        );
        if (info?.file != null) {
          uploadFile = info!.file!;
          compressedPath = uploadFile.path;
        }
      }
      await _service.sendMedia(uploadFile, type, durationSeconds: duration);
    } catch (e) {
      if (mounted) _error('Не удалось сжать или отправить медиа: $e');
    } finally {
      if (compressedPath != null) {
        try { await VideoCompress.deleteAllCache(); } catch (_) {}
      }
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showAttachMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFF11F3A6).withOpacity(.22)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38, height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(sheetContext).dividerColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text('Поделиться',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _AttachmentTile(
                      icon: Icons.photo_rounded,
                      title: 'Фото',
                      subtitle: 'Из галереи',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickImage();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _AttachmentTile(
                      icon: Icons.circle,
                      title: 'Кружочек',
                      subtitle: 'Записать видео',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _recordCircle();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _emoji() async {
    const emojis = ['😀','😁','😂','🤣','😊','😍','🥰','😘','😉','😎','😭','😅','🤔','👍','👎','❤️','🔥','🎉','🙏','🤝','👏','💯','🥹','😴'];
    final selected = await showModalBottomSheet<String>(context: context, builder: (context) =>
      SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: Wrap(
        spacing: 14, runSpacing: 14, children: emojis.map((e) => InkWell(
          onTap: () => Navigator.pop(context, e), child: Text(e, style: const TextStyle(fontSize: 28))),
        ).toList(),
      ))));
    if (selected != null) {
      final old = _text.value;
      final next = old.text.replaceRange(old.selection.start < 0 ? old.text.length : old.selection.start,
        old.selection.end < 0 ? old.text.length : old.selection.end, selected);
      _text.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length));
    }
  }

  Future<void> _delete(ChatMessage message) async {
    if (message.userId != _myId) return;
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Удалить сообщение?'),
      content: const Text('Оно будет удалено у обоих участников.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить'))],
    ));
    if (yes != true) return;
    try { await _service.deleteMessage(message);
      if (mounted) setState(() => _messages.removeWhere((m) => m.id == message.id));
      await _saveLocalMessages();
    } catch (_) { if (mounted) _error('Не удалось удалить сообщение.'); }
  }

  void _error(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  void _jumpToBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  });
  String _initials(String name) => name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
  String _time(DateTime date) => '${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}';

  @override
  void dispose() {
    _typingTimer?.cancel(); _lastSeenTimer?.cancel(); _messageSub?.cancel();
    final channel = _channel;
    if (channel != null) _client.removeChannel(channel);
    _text.dispose(); _scroll.dispose(); super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typing = _typingUsers.isNotEmpty;
    return Scaffold(
      appBar: AppBar(titleSpacing: 4, title: Row(children: [
        CircleAvatar(backgroundColor: const Color(0xFF11F3A6), child: const Icon(Icons.forum_rounded, color: Color(0xFF04251B))),
        const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('GitrChat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          InkWell(
            onTap: _showOnlineUsers,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF11F3A6), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('$_onlineCount онлайн · участники', style: const TextStyle(fontSize: 12, color: Color(0xFF11B982))),
              ]),
            ),
          ),
        ]),
      ]), actions: [
        IconButton(tooltip: 'Настройки', icon: const Icon(Icons.tune_rounded),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        IconButton(tooltip: 'Выйти', onPressed: () => _client.auth.signOut(), icon: const Icon(Icons.logout_rounded)),
      ]),
      body: Column(children: [
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) :
          _messages.isEmpty ? const Center(child: Text('Пока сообщений нет\nНачните общение первым', textAlign: TextAlign.center)) :
          ListView.builder(controller: _scroll, padding: const EdgeInsets.fromLTRB(16,16,16,20),
            itemCount: _messages.length, itemBuilder: (context, index) {
              final m = _messages[index]; final mine = m.userId == _myId;
              return GestureDetector(onLongPress: mine ? () => _delete(m) : null,
                child: Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(
                  mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (!mine) ...[CircleAvatar(radius: 16, backgroundColor: const Color(0xFF11F3A6).withOpacity(.16), foregroundColor: const Color(0xFF11A879), child: Text(_initials(m.userName), style: const TextStyle(fontWeight: FontWeight.w800))), const SizedBox(width: 7)],
                    Flexible(child: Container(constraints: const BoxConstraints(maxWidth: 300),
                      padding: const EdgeInsets.all(10), decoration: BoxDecoration(
                        gradient: mine ? const LinearGradient(
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                          colors: [Color(0xFF11F3A6), Color(0xFF78FFD2)])
                          : null,
                        color: mine ? null : Theme.of(context).colorScheme.surface,
                        border: mine ? null : Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withOpacity(.055) : const Color(0xFFE0EEE8)),
                        boxShadow: mine ? [BoxShadow(
                          color: const Color(0xFF11F3A6).withOpacity(.13),
                          blurRadius: 18, offset: const Offset(0, 6))] : null,
                        borderRadius: BorderRadius.only(topLeft: const Radius.circular(22), topRight: const Radius.circular(22), bottomLeft: Radius.circular(mine ? 22 : 7), bottomRight: Radius.circular(mine ? 7 : 22))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (!mine) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(m.userName,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Theme.of(context).colorScheme.primary))),
                        if (m.hasMedia) MediaBubble(message: m, service: _service),
                        if (m.text.isNotEmpty) Text(m.text, style: TextStyle(color: mine ? const Color(0xFF04251B) : null, fontWeight: mine ? FontWeight.w500 : FontWeight.normal)),
                        Align(alignment: Alignment.bottomRight, child: Text(_time(m.createdAt),
                          style: TextStyle(fontSize: 10, color: mine ? const Color(0xFF1D6C51) : Theme.of(context).hintColor))),
                      ]))),
                  ],
                )));
            })),
        if (typing) const Padding(padding: EdgeInsets.fromLTRB(18,0,18,8), child: Align(
          alignment: Alignment.centerLeft, child: Text('Собеседник печатает…', style: TextStyle(fontSize: 12)))),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _sending
            ? Padding(
                key: const ValueKey('media-uploading'),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 9),
                    Text('Сжимаем и отправляем…', style: Theme.of(context).textTheme.labelMedium),
                  ]),
                  const SizedBox(height: 7),
                  const LinearProgressIndicator(minHeight: 3),
                ]),
              )
            : const SizedBox(key: ValueKey('media-idle'), height: 0),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 10),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF111C19)
                    : const Color(0xFFF8FFFC),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: const Color(0xFF11F3A6).withOpacity(
                    Theme.of(context).brightness == Brightness.dark ? .22 : .48,
                  ),
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF11F3A6).withOpacity(.09),
                    blurRadius: 24,
                    offset: const Offset(0, 7),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(
                      Theme.of(context).brightness == Brightness.dark ? .20 : .035,
                    ),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 3, 8),
                        child: Material(
                          color: const Color(0xFF11F3A6),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _sending ? null : _showAttachMenu,
                            child: const SizedBox(
                              width: 46,
                              height: 46,
                              child: Icon(
                                Icons.add_rounded,
                                color: Color(0xFF04251B),
                                size: 30,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 5, top: 9, bottom: 7),
                          child: TextField(
                            controller: _text,
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: _onTextChanged,
                            onSubmitted: (_) => _send(),
                            style: const TextStyle(fontSize: 15.5, height: 1.35),
                            decoration: InputDecoration(
                              hintText: 'Напиши что-нибудь…',
                              hintStyle: TextStyle(
                                color: Theme.of(context).hintColor.withOpacity(.8),
                                fontSize: 15,
                              ),
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 8, 5, 8),
                        child: IconButton(
                          tooltip: 'Смайлики',
                          onPressed: _emoji,
                          style: IconButton.styleFrom(
                            foregroundColor: const Color(0xFF11B982),
                            minimumSize: const Size(42, 42),
                          ),
                          icon: const Icon(Icons.mood_rounded, size: 25),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 7, 7, 7),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF11F3A6), Color(0xFF7AFFD1)],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF11F3A6).withOpacity(.24),
                                blurRadius: 13,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: IconButton(
                            tooltip: 'Отправить',
                            onPressed: _sending ? null : _send,
                            color: const Color(0xFF04251B),
                            icon: _sending
                                ? const SizedBox(
                                    width: 19,
                                    height: 19,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF04251B),
                                    ),
                                  )
                                : const Icon(Icons.arrow_upward_rounded, size: 25),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 9),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 12,
                          color: Theme.of(context).hintColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Личное пространство',
                          style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: .2,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '＋  Медиа',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF11F3A6).withOpacity(.09),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: Color(0xFF11F3A6),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: const Color(0xFF04251B)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MediaBubble extends StatelessWidget {
  const MediaBubble({super.key, required this.message, required this.service});
  final ChatMessage message;
  final ChatService service;

  @override
  Widget build(BuildContext context) => FutureBuilder<File>(
    future: service.cachedMediaFile(message.mediaPath!),
    builder: (context, file) {
          if (!file.hasData) return TweenAnimationBuilder<double>(tween: Tween(begin: .35, end: .8), duration: const Duration(milliseconds: 850), curve: Curves.easeInOut, builder: (context, opacity, _) => Container(width: 220, height: 132, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(opacity), borderRadius: BorderRadius.circular(14)), child: const Center(child: Icon(Icons.cloud_download_rounded, size: 30))));
          if (message.mediaType == 'image') {
            return GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(),
                      body: Center(
                        child: InteractiveViewer(
                          child: Image.file(file.data!, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(file.data!, width: 220, fit: BoxFit.cover),
              ),
            );
          }
          return VideoCircle(file: file.data!, duration: message.mediaDurationSeconds ?? 0);
    },
  );
}

class VideoCircle extends StatelessWidget {
  const VideoCircle({super.key, required this.file, required this.duration});
  final File file;
  final int duration;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CircleVideoViewer(
                file: file,
                duration: duration,
              ),
            ),
          );
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipOval(
              child: SizedBox(
                width: 190,
                height: 190,
                child: VideoPlayerPreview(file: file),
              ),
            ),
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.48),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
            if (duration > 0)
              Positioned(
                bottom: 12,
                right: 18,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    child: Text(
                      '${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// A lightweight muted preview; tapping the circle opens the large viewer.
class VideoPlayerPreview extends StatefulWidget {
  const VideoPlayerPreview({super.key, required this.file});
  final File file;

  @override
  State<VideoPlayerPreview> createState() => _VideoPlayerPreviewState();
}

class _VideoPlayerPreviewState extends State<VideoPlayerPreview> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const ColoredBox(
        color: Color(0xFF17231F),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF11F3A6)),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: _controller.value.size.width,
        height: _controller.value.size.height,
        child: VideoPlayer(_controller),
      ),
    );
  }
}

class CircleVideoViewer extends StatefulWidget {
  const CircleVideoViewer({
    super.key,
    required this.file,
    required this.duration,
  });

  final File file;
  final int duration;

  @override
  State<CircleVideoViewer> createState() => _CircleVideoViewerState();
}

class _CircleVideoViewerState extends State<CircleVideoViewer> {
  late final VideoPlayerController _controller;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller.play();
      });
    _controller.addListener(_onVideoChanged);
  }

  void _onVideoChanged() {
    if (mounted) setState(() {});
  }

  void _togglePlayback() {
    if (!_controller.value.isInitialized) return;
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      if (_controller.value.position >= _controller.value.duration) {
        _controller.seekTo(Duration.zero);
      }
      _controller.play();
    }
    setState(() => _showControls = true);
  }

  String _time(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _controller.removeListener(_onVideoChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialized = _controller.value.isInitialized;
    final screen = MediaQuery.sizeOf(context);
    final diameter = (screen.width * .88).clamp(240.0, 420.0);

    return Scaffold(
      backgroundColor: const Color(0xFF050B09),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050B09),
        foregroundColor: Colors.white,
        title: const Text('Видеокружок'),
        actions: [
          IconButton(
            tooltip: 'Закрыть',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: initialized
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() => _showControls = !_showControls);
                        if (_showControls && !_controller.value.isPlaying) {
                          _togglePlayback();
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: diameter,
                        height: diameter,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF11F3A6),
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF11F3A6).withOpacity(.18),
                              blurRadius: 28,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _controller.value.size.width,
                                  height: _controller.value.size.height,
                                  child: VideoPlayer(_controller),
                                ),
                              ),
                              if (_showControls &&
                                  !_controller.value.isPlaying)
                                Container(
                                  color: Colors.black.withOpacity(.20),
                                  child: const Center(
                                    child: Icon(
                                      Icons.play_circle_fill_rounded,
                                      color: Colors.white,
                                      size: 76,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: diameter,
                      child: Row(
                        children: [
                          Text(
                            _time(_controller.value.position),
                            style: const TextStyle(color: Colors.white70),
                          ),
                          Expanded(
                            child: VideoProgressIndicator(
                              _controller,
                              allowScrubbing: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              colors: const VideoProgressColors(
                                playedColor: Color(0xFF11F3A6),
                                bufferedColor: Colors.white30,
                                backgroundColor: Colors.white12,
                              ),
                            ),
                          ),
                          Text(
                            _time(_controller.value.duration),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF11F3A6),
                        foregroundColor: const Color(0xFF04251B),
                        minimumSize: const Size(64, 64),
                      ),
                      onPressed: _togglePlayback,
                      icon: Icon(
                        _controller.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 34,
                      ),
                    ),
                  ],
                )
              : const CircularProgressIndicator(
                  color: Color(0xFF11F3A6),
                ),
        ),
      ),
    );
  }
}


class CircleRecorderScreen extends StatefulWidget {
  const CircleRecorderScreen({super.key});

  @override
  State<CircleRecorderScreen> createState() => _CircleRecorderScreenState();
}

class _CircleRecorderScreenState extends State<CircleRecorderScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  Timer? _ticker;
  int _seconds = 0;
  bool _recording = false;
  bool _paused = false;
  bool _initializing = true;
  bool _stopping = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw Exception('Камера не найдена');
      final front = _cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      _cameraIndex = front >= 0 ? front : 0;
      await _createController();
    } catch (e) {
      if (mounted) setState(() {
        _error = 'Не удалось открыть камеру. Проверьте разрешение на камеру и микрофон.';
        _initializing = false;
      });
    }
  }

  Future<void> _createController() async {
    final old = _camera;
    _camera = null;
    await old?.dispose();
    final controller = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.medium,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _camera = controller;
    await controller.initialize();
    if (mounted) setState(() => _initializing = false);
  }

  Future<void> _switchCamera() async {
    if (_recording || _cameras.length < 2) return;
    setState(() => _initializing = true);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    try {
      await _createController();
    } catch (_) {
      if (mounted) setState(() {
        _error = 'Не удалось переключить камеру.';
        _initializing = false;
      });
    }
  }

  Future<void> _startRecording() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _recording) return;
    try {
      await camera.prepareForVideoRecording();
      await camera.startVideoRecording();
      setState(() {
        _recording = true;
        _paused = false;
        _seconds = 0;
      });
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _paused) return;
        setState(() => _seconds++);
        if (_seconds >= 60) _stopAndSend();
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось начать запись.');
    }
  }

  Future<void> _togglePause() async {
    final camera = _camera;
    if (camera == null || !_recording) return;
    try {
      if (_paused) {
        await camera.resumeVideoRecording();
      } else {
        await camera.pauseVideoRecording();
      }
      if (mounted) setState(() => _paused = !_paused);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось изменить состояние записи.');
    }
  }

  Future<void> _stopAndSend() async {
    final camera = _camera;
    if (camera == null || !_recording || _stopping) return;
    _stopping = true;
    _ticker?.cancel();
    try {
      final video = await camera.stopVideoRecording();
      if (!mounted) return;
      Navigator.of(context).pop(File(video.path));
    } catch (_) {
      if (mounted) setState(() {
        _recording = false;
        _error = 'Не удалось сохранить запись.';
      });
    } finally {
      _stopping = false;
    }
  }

  Future<void> _discard() async {
    final camera = _camera;
    _ticker?.cancel();
    if (_recording && camera != null) {
      try {
        final file = await camera.stopVideoRecording();
        await File(file.path).delete();
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _ticker?.cancel();
      _camera?.dispose();
      _camera = null;
      if (mounted && !_stopping) {
        setState(() {
          _recording = false;
          _paused = false;
          _initializing = true;
          _error = 'Запись остановлена при сворачивании приложения. Откройте камеру снова.';
        });
      }
    }
  }

  String get _timerText =>
      '00:${_seconds.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      backgroundColor: const Color(0xFF07110E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF07110E),
        foregroundColor: Colors.white,
        title: const Text('Видеокружок'),
        actions: [
          IconButton(
            tooltip: 'Переключить камеру',
            onPressed: _recording ? null : _switchCamera,
            icon: const Icon(Icons.flip_camera_android_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: MediaQuery.sizeOf(context).width * .86,
                height: MediaQuery.sizeOf(context).width * .86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _recording
                        ? const Color(0xFFFF526B)
                        : const Color(0xFF11F3A6),
                    width: _recording ? 4 : 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_recording
                              ? const Color(0xFFFF526B)
                              : const Color(0xFF11F3A6))
                          .withOpacity(.18),
                      blurRadius: 30,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: _initializing
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF11F3A6),
                          ),
                        )
                      : camera != null && camera.value.isInitialized
                          ? CameraPreview(camera)
                          : Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _error ?? 'Камера недоступна',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                ),
              ),
            ),
            const Spacer(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.42),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_recording)
                    const Icon(Icons.circle, color: Color(0xFFFF526B), size: 12),
                  if (_recording) const SizedBox(width: 8),
                  Text(
                    _recording ? _timerText : 'До 60 секунд',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton.filledTonal(
                    onPressed: _discard,
                    style: IconButton.styleFrom(
                      foregroundColor: const Color(0xFFFF526B),
                      backgroundColor: Colors.white10,
                      minimumSize: const Size(58, 58),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 30),
                  ),
                  if (_recording)
                    IconButton.filled(
                      onPressed: _togglePause,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF11F3A6),
                        foregroundColor: const Color(0xFF04251B),
                        minimumSize: const Size(66, 66),
                      ),
                      icon: Icon(
                        _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        size: 34,
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: _initializing || _error != null
                          ? null
                          : _startRecording,
                      child: Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          color: const Color(0xFFFF526B),
                        ),
                        child: const Icon(
                          Icons.videocam_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ),
                  IconButton.filled(
                    onPressed: _recording ? _stopAndSend : null,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF11F3A6),
                      foregroundColor: const Color(0xFF04251B),
                      disabledBackgroundColor: Colors.white12,
                      minimumSize: const Size(58, 58),
                    ),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 30),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
