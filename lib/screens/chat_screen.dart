
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final service = ChatService();
  final input = TextEditingController();
  final scroll = ScrollController();

  List<ChatMessage> messages = [];
  bool loading = true;
  bool sending = false;
  bool someoneTyping = false;
  bool typingSent = false;

  RealtimeChannel? channel;
  Timer? typingTimer;

  final emojis = [
    '😀', '😂', '😍', '🥰', '😎',
    '😭', '😊', '❤️', '🔥', '👍',
    '👋', '🎉', '😘', '🤔', '🙏',
    '💯', '🤣', '😢', '😉', '🥳',
  ];

  @override
  void initState() {
    super.initState();
    load();
    setupRealtime();
  }

  void setupRealtime() {
    channel = Supabase.instance.client.channel('onechat-presence');

    channel!
      .onPresenceSync((_) {
        if (mounted) setState(() {});
      })
      .onBroadcast(
        event: 'typing',
        callback: (payload) {
          final data = payload['payload'] is Map
              ? Map<String, dynamic>.from(payload['payload'])
              : Map<String, dynamic>.from(payload);

          if (data['user_id'] == service.userId) return;

          if (mounted) {
            setState(() {
              someoneTyping = data['typing'] == true;
            });
          }
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'messages',
        callback: (_) => load(),
      )
      .subscribe((status, error) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await channel!.track({
            'user_id': service.userId,
            'online_at': DateTime.now().toIso8601String(),
          });
        }
      });
  }

  Future<void> sendTyping(bool value) async {
    if (channel == null) return;
    try {
      await channel!.sendBroadcastMessage(
        event: 'typing',
        payload: {
          'user_id': service.userId,
          'typing': value,
        },
      );
    } catch (_) {}
  }

  void onTyping(String value) {
    if (value.trim().isEmpty) {
      typingTimer?.cancel();
      if (typingSent) {
        typingSent = false;
        sendTyping(false);
      }
      return;
    }

    if (!typingSent) {
      typingSent = true;
      sendTyping(true);
    }

    typingTimer?.cancel();
    typingTimer = Timer(const Duration(seconds: 2), () {
      typingSent = false;
      sendTyping(false);
    });
  }

  Future<void> load() async {
    try {
      final data = await service.loadMessages();
      if (mounted) {
        setState(() {
          messages = data;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> send() async {
    final value = input.text.trim();
    if (value.isEmpty || sending) return;

    setState(() => sending = true);
    input.clear();

    typingTimer?.cancel();
    typingSent = false;
    sendTyping(false);

    try {
      await service.send(value);
      await load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось отправить сообщение')),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void addEmoji(String emoji) {
    final text = input.text;
    final selection = input.selection;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;

    final newText = text.replaceRange(start, end, emoji);
    input.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: start + emoji.length,
      ),
    );
    onTyping(newText);
  }

  Future<void> remove(ChatMessage message) async {
    try {
      await service.delete(message.id);
      await load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось удалить сообщение')),
        );
      }
    }
  }

  Color avatarColor(String name) {
    final colors = [
      Colors.indigo,
      Colors.teal,
      Colors.deepPurple,
      Colors.blue,
      Colors.pink,
      Colors.orange,
      Colors.green,
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  @override
  void dispose() {
    typingTimer?.cancel();
    input.dispose();
    scroll.dispose();

    if (channel != null) {
      channel!.untrack();
      Supabase.instance.client.removeChannel(channel!);
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentId = service.userId;
    final online = channel?.presenceState().length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'OneChat',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '$online в сети',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.green,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? const Center(
                        child: Text('Пока нет сообщений. Начните разговор.'),
                      )
                    : ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (_, i) {
                          final message = messages[i];
                          final mine = message.userId == currentId;

                          return Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: GestureDetector(
                              onLongPress: mine
                                  ? () => showModalBottomSheet(
                                        context: context,
                                        builder: (_) => ListTile(
                                          leading: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          title: const Text(
                                            'Удалить сообщение',
                                          ),
                                          onTap: () {
                                            Navigator.pop(context);
                                            remove(message);
                                          },
                                        ),
                                      )
                                  : null,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                constraints:
                                    const BoxConstraints(maxWidth: 320),
                                decoration: BoxDecoration(
                                  color: mine
                                      ? const Color(0xFFE2E7FF)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircleAvatar(
                                          radius: 15,
                                          backgroundColor:
                                              avatarColor(message.name),
                                          child: Text(
                                            message.name.isNotEmpty
                                                ? message.name[0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 7),
                                        Flexible(
                                          child: Text(
                                            mine ? 'Вы' : message.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(message.body),
                                    const SizedBox(height: 4),
                                    Align(
                                      alignment: Alignment.bottomRight,
                                      child: Text(
                                        DateFormat('HH:mm')
                                            .format(message.createdAt),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),

          if (someoneTyping)
            const Padding(
              padding: EdgeInsets.only(left: 18, bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Кто-то печатает…',
                  style: TextStyle(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),

          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: emojis.map((emoji) {
                return InkWell(
                  onTap: () => addEmoji(emoji),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    child: Center(
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 25),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: 4,
                      onChanged: onTyping,
                      decoration: const InputDecoration(
                        hintText: 'Сообщение…',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: sending ? null : send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
