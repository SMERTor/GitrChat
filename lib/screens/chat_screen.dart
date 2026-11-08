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
  bool loading = true, sending = false;
  RealtimeChannel? channel;
  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
    load();
    channel = Supabase.instance.client.channel('onechat-presence');
    channel!.onPresenceSync((_) { if (mounted) setState(() {}); });
    channel!.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        channel!.track({'user_id': service.userId, 'online_at': DateTime.now().toIso8601String()});
      }
    });
  }

  Future<void> load() async {
    try { final data = await service.loadMessages(); if (mounted) setState(() { messages = data; loading = false; }); }
    catch (_) { if (mounted) setState(() => loading = false); }
  }

  Future<void> send() async {
    final value = input.text.trim();
    if (value.isEmpty || sending) return;
    setState(() => sending = true);
    input.clear();
    try { await service.send(value); await load(); }
    catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось отправить сообщение'))); }
    finally { if (mounted) setState(() => sending = false); }
  }

  Future<void> remove(ChatMessage m) async {
    try { await service.delete(m.id); await load(); }
    catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось удалить сообщение'))); }
  }

  @override
  void dispose() {
    input.dispose(); scroll.dispose(); refreshTimer?.cancel();
    if (channel != null) { Supabase.instance.client.removeChannel(channel!); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentId = service.userId;
    final online = channel?.presenceState().length ?? 0;
    return Scaffold(
      appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('OneChat', style: TextStyle(fontWeight: FontWeight.bold)),
        Text('$online в сети', style: const TextStyle(fontSize: 12, color: Colors.green)),
      ]), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
      body: Column(children: [
        Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : messages.isEmpty
          ? const Center(child: Text('Пока нет сообщений. Начните разговор.'))
          : ListView.builder(controller: scroll, padding: const EdgeInsets.all(16), itemCount: messages.length, itemBuilder: (_, i) {
            final m = messages[i]; final mine = m.userId == currentId;
            return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: GestureDetector(
              onLongPress: mine ? () => showModalBottomSheet(context: context, builder: (_) => ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Удалить сообщение'), onTap: () { Navigator.pop(context); remove(m); })) : null,
              child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), constraints: const BoxConstraints(maxWidth: 320),
                decoration: BoxDecoration(color: mine ? const Color(0xFFE2E7FF) : Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(radius: 12, child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?', style: const TextStyle(fontSize: 11))),
                    const SizedBox(width: 7), Flexible(child: Text(mine ? 'Вы' : m.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ]),
                  const SizedBox(height: 6), Text(m.body),
                  const SizedBox(height: 4), Align(alignment: Alignment.bottomRight, child: Text(DateFormat('HH:mm').format(m.createdAt), style: const TextStyle(fontSize: 10, color: Colors.black54))),
                ]),
              ),
            ));
          })),
        SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), child: Row(children: [
          Expanded(child: TextField(controller: input, minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'Сообщение…', contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12)), onSubmitted: (_) => send())),
          const SizedBox(width: 8), IconButton.filled(onPressed: sending ? null : send, icon: const Icon(Icons.send_rounded)),
        ]))),
      ]),
    );
  }
}
