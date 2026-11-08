import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';

class ChatService {
  ChatService(this.client);
  final SupabaseClient client;
  String get userId => client.auth.currentUser!.id;
  static const bucket = 'chat-media';

  Future<void> signInWithName(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) throw Exception('Введите имя');
    if (client.auth.currentSession == null) await client.auth.signInAnonymously();
    await client.from('profiles').upsert({
      'id': userId, 'name': name,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<String> getMyName() async {
    final row = await client.from('profiles').select('name').eq('id', userId).maybeSingle();
    return row?['name'] as String? ?? 'Пользователь';
  }

  Future<List<ChatMessage>> loadMessages() async {
    final rows = await client.from('messages')
      .select('id,user_id,body,created_at,media_path,media_type,media_duration_seconds,profiles(name)')
      .order('created_at', ascending: true).limit(100);
    return rows.map((row) => ChatMessage.fromMap(row)).toList();
  }

  Future<void> sendMessage(String text) async {
    final value = text.trim();
    if (value.isEmpty) return;
    await client.from('messages').insert({'user_id': userId, 'body': value});
  }

  Future<void> sendMedia(File file, String type, {int? durationSeconds}) async {
    final ext = file.path.split('.').last.toLowerCase();
    final path = '$userId/${const Uuid().v4()}.$ext';
    final contentType = switch (ext) {
      'png' => 'image/png', 'webp' => 'image/webp', 'heic' => 'image/heic',
      'mov' => 'video/quicktime', _ => type == 'image' ? 'image/jpeg' : 'video/mp4',
    };
    await client.storage.from(bucket).upload(path, file,
      fileOptions: FileOptions(contentType: contentType, upsert: false));
    try {
      await client.from('messages').insert({
        'user_id': userId, 'body': null, 'media_path': path,
        'media_type': type, 'media_duration_seconds': durationSeconds,
      });
    } catch (_) {
      await client.storage.from(bucket).remove([path]);
      rethrow;
    }
  }

  Future<String> mediaUrl(String path) => client.storage.from(bucket).createSignedUrl(path, 60 * 60 * 24 * 7);

  Future<void> deleteMessage(ChatMessage message) async {
    if (message.userId != userId) throw Exception('Можно удалять только свои сообщения');
    await client.from('messages').delete().eq('id', message.id);
    if (message.mediaPath != null) {
      await client.storage.from(bucket).remove([message.mediaPath!]);
    }
  }

  Future<int> countOnlineUsers(RealtimeChannel channel) async =>
      channel.presenceState().fold<int>(0, (sum, state) => sum + state.presences.length);
}
