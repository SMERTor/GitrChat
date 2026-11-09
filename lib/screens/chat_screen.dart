import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:image_picker/image_picker.dart';
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
      final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 68, maxWidth: 1600, maxHeight: 1600);
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
        CircleAvatar(backgroundColor: const Color(0xFF11F3A6), child: const Icon(Icons.forum_rounded, color: Color(0xFF04251B))),
        const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('GitrChat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Row(children: [Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF11F3A6), shape: BoxShape.circle)), const SizedBox(width: 6), Text('$_onlineCount онлайн', style: const TextStyle(fontSize: 12, color: Color(0xFF11B982)))]),
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
        SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withOpacity(.06) : const Color(0xFFE0EEE8)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(
                Theme.of(context).brightness == Brightness.dark ? .12 : .04),
                blurRadius: 20, offset: const Offset(0, 5))],
            ),
            child: Row(children: [
              IconButton(tooltip: 'Смайлики', onPressed: _emoji,
                color: const Color(0xFF11B982), icon: const Icon(Icons.sentiment_satisfied_alt_rounded)),
              IconButton(tooltip: 'Фото', onPressed: _sending ? null : _pickImage,
                color: const Color(0xFF11B982), icon: const Icon(Icons.image_rounded)),
              IconButton(tooltip: 'Видеокружок', onPressed: _sending ? null : _recordCircle,
                color: const Color(0xFF11B982), icon: const Icon(Icons.video_camera_front_rounded)),
              Expanded(child: TextField(controller: _text, minLines: 1, maxLines: 4,
                textCapitalization: TextCapitalization.sentences, onChanged: _onTextChanged,
                onSubmitted: (_) => _send(), decoration: const InputDecoration(
                  hintText: 'Написать сообщение…', filled: false, border: InputBorder.none,
                  enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)))),
              const SizedBox(width: 4),
              Container(
                decoration: const BoxDecoration(color: Color(0xFF11F3A6), shape: BoxShape.circle),
                child: IconButton(onPressed: _sending ? null : _send,
                  color: const Color(0xFF04251B),
                  icon: _sending ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:Color(0xFF04251B))) : const Icon(Icons.arrow_upward_rounded)),
              ),
            ]),
          ),
        )),
      ]),
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
