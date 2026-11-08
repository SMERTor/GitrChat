import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

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

  Future<void> _start() async {
    try {
      _messages = await _service.loadMessages();
      _subscribeMessages();
      _subscribePresence();
    } catch (_) {
      if (mounted) _error('Не удалось загрузить сообщения. Проверьте подключение к Supabase.');
    } finally {
      if (mounted) setState(() => _loading = false);
      _jumpToBottom();
    }
  }

  void _subscribeMessages() {
    _messageSub = _client.from('messages').stream(primaryKey: ['id'])
      .order('created_at').listen((_) async {
        try {
          final refreshed = await _service.loadMessages();
          if (mounted) setState(() => _messages = refreshed);
          _jumpToBottom();
        } catch (_) {}
      });
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
    final count = await _service.countOnlineUsers(channel);
    if (mounted) setState(() => _onlineCount = count);
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
      final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 78, maxWidth: 1920);
      if (picked != null) await _upload(File(picked.path), 'image');
    } catch (_) { if (mounted) _error('Не удалось выбрать фотографию.'); }
  }

  Future<void> _recordCircle() async {
    try {
      final picked = await _picker.pickVideo(source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front, maxDuration: const Duration(seconds: 60));
      if (picked != null) await _upload(File(picked.path), 'video_circle');
    } catch (_) { if (mounted) _error('Не удалось записать видеосообщение.'); }
  }

  Future<void> _upload(File file, String type, {int? duration}) async {
    setState(() => _sending = true);
    try { await _service.sendMedia(file, type, durationSeconds: duration); }
    catch (e) { if (mounted) _error('Не удалось отправить медиа: $e'); }
    finally { if (mounted) setState(() => _sending = false); }
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
    try { await _service.deleteMessage(message); }
    catch (_) { if (mounted) _error('Не удалось удалить сообщение.'); }
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
    _typingTimer?.cancel(); _messageSub?.cancel();
    final channel = _channel;
    if (channel != null) _client.removeChannel(channel);
    _text.dispose(); _scroll.dispose(); super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typing = _typingUsers.isNotEmpty;
    return Scaffold(
      appBar: AppBar(titleSpacing: 4, title: Row(children: [
        CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(Icons.forum_rounded, color: Theme.of(context).colorScheme.primary)),
        const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Общий чат', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text('$_onlineCount онлайн', style: const TextStyle(fontSize: 12, color: Colors.green)),
        ]),
      ]), actions: [
        IconButton(tooltip: 'Настройки', icon: const Icon(Icons.tune_rounded),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        IconButton(tooltip: 'Выйти', onPressed: () => _client.auth.signOut(), icon: const Icon(Icons.logout_rounded)),
      ]),
      body: Column(children: [
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) :
          _messages.isEmpty ? const Center(child: Text('Пока сообщений нет\nНачните общение первым', textAlign: TextAlign.center)) :
          ListView.builder(controller: _scroll, padding: const EdgeInsets.fromLTRB(14,12,14,16),
            itemCount: _messages.length, itemBuilder: (context, index) {
              final m = _messages[index]; final mine = m.userId == _myId;
              return GestureDetector(onLongPress: mine ? () => _delete(m) : null,
                child: Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(
                  mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (!mine) ...[CircleAvatar(radius: 16, child: Text(_initials(m.userName))), const SizedBox(width: 7)],
                    Flexible(child: Container(constraints: const BoxConstraints(maxWidth: 300),
                      padding: const EdgeInsets.all(10), decoration: BoxDecoration(
                        color: mine ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(17)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (!mine) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(m.userName,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Theme.of(context).colorScheme.primary))),
                        if (m.hasMedia) MediaBubble(message: m, service: _service),
                        if (m.text.isNotEmpty) Text(m.text, style: TextStyle(color: mine ? Colors.white : null)),
                        Align(alignment: Alignment.bottomRight, child: Text(_time(m.createdAt),
                          style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : Theme.of(context).hintColor))),
                      ]))),
                  ],
                )));
            })),
        if (typing) const Padding(padding: EdgeInsets.fromLTRB(18,0,18,8), child: Align(
          alignment: Alignment.centerLeft, child: Text('Собеседник печатает…', style: TextStyle(fontSize: 12)))),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(8,6,8,10), child: Row(children: [
          IconButton(tooltip: 'Смайлики', onPressed: _emoji, icon: const Icon(Icons.emoji_emotions_outlined)),
          IconButton(tooltip: 'Фото', onPressed: _sending ? null : _pickImage, icon: const Icon(Icons.image_outlined)),
          IconButton(tooltip: 'Видеокружок', onPressed: _sending ? null : _recordCircle, icon: const Icon(Icons.video_camera_front_outlined)),
          Expanded(child: TextField(controller: _text, minLines: 1, maxLines: 4,
            textCapitalization: TextCapitalization.sentences, onChanged: _onTextChanged,
            onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'Сообщение…'))),
          const SizedBox(width: 6), IconButton.filled(onPressed: _sending ? null : _send,
            icon: _sending ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.send_rounded)),
        ]))),
      ]),
    );
  }
}

class MediaBubble extends StatelessWidget {
  const MediaBubble({super.key, required this.message, required this.service});
  final ChatMessage message;
  final ChatService service;

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: service.mediaUrl(message.mediaPath!),
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const SizedBox(width: 190,height:130,child:Center(child:CircularProgressIndicator()));
      return FutureBuilder<File>(
        future: DefaultCacheManager().getSingleFile(snapshot.data!),
        builder: (context, file) {
          if (!file.hasData) return const SizedBox(width:190,height:130,child:Center(child:CircularProgressIndicator()));
          if (message.mediaType == 'image') return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
              appBar: AppBar(), body: Center(child: InteractiveViewer(child: Image.file(file.data!, fit: BoxFit.contain))))),
            child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(file.data!, width: 220, fit: BoxFit.cover)));
          return VideoCircle(file: file.data!, duration: message.mediaDurationSeconds ?? 0);
        },
      );
    },
  );
}

class VideoCircle extends StatefulWidget {
  const VideoCircle({super.key, required this.file, required this.duration});
  final File file; final int duration;
  @override
  State<VideoCircle> createState() => _VideoCircleState();
}
class _VideoCircleState extends State<VideoCircle> {
  late final VideoPlayerController _controller;
  @override
  void initState() { super.initState(); _controller = VideoPlayerController.file(widget.file)
    ..initialize().then((_) { if (mounted) setState(() {}); }); }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: () {
    if (_controller.value.isPlaying) _controller.pause(); else _controller.play();
    setState(() {});
  }, child: ClipOval(child: SizedBox(width: 190,height:190, child: _controller.value.isInitialized
    ? Stack(fit: StackFit.expand, children: [FittedBox(fit: BoxFit.cover, child: SizedBox(
      width: _controller.value.size.width, height: _controller.value.size.height, child: VideoPlayer(_controller))),
      if (!_controller.value.isPlaying) const Center(child: Icon(Icons.play_circle_fill, size: 54, color: Colors.white))])
    : const ColoredBox(color: Colors.black12, child: Center(child: CircularProgressIndicator())))));
}
