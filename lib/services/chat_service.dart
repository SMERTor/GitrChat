import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_message.dart';

class ChatService {
  final SupabaseClient client = Supabase.instance.client;
  String get userId => client.auth.currentUser!.id;

  Future<void> signIn(String name) async {
    if (client.auth.currentSession == null) await client.auth.signInAnonymously();
    final id = userId;
    await client.from('profiles').upsert({'id': id, 'name': name.trim(), 'updated_at': DateTime.now().toUtc().toIso8601String()});
  }

  Future<List<ChatMessage>> loadMessages() async {
    final rows = await client.from('messages').select('id,user_id,body,created_at,profiles(name)').order('created_at');
    return rows.map((e) => ChatMessage.fromMap(e)).toList();
  }

  Future<void> send(String body) async {
    await client.from('messages').insert({'user_id': userId, 'body': body.trim()});
  }

  Future<void> delete(int id) async {
    await client.from('messages').delete().eq('id', id).eq('user_id', userId);
  }

  Stream<List<Map<String, dynamic>>> messageStream() => client
      .from('messages')
      .stream(primaryKey: ['id'])
      .order('created_at');

  Future<void> updateName(String name) async {
    await client.from('profiles').update({'name': name.trim(), 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', userId);
  }
}
