import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountService {
  AccountService(this.client);
  final SupabaseClient client;

  String _emailForName(String name) {
    final normalized = name.trim().toLowerCase().replaceAll(RegExp(r'\\s+'), ' ');
    final digest = sha256.convert(utf8.encode(normalized)).toString();
    return 'u_${digest.substring(0, 40)}@accounts.gitrchat.invalid';
  }

  Future<void> signIn(String name, String pin) async {
    await client.auth.signInWithPassword(email: _emailForName(name), password: pin);
  }

  Future<void> createOrLink(String name, String pin) async {
    if (client.auth.currentSession == null) {
      await client.auth.signInAnonymously();
    }
    final result = await client.functions.invoke(
      'claim-account',
      body: {'name': name.trim(), 'pin': pin},
    );
    if (result.status < 200 || result.status >= 300) {
      final body = result.data;
      final error = body is Map ? body['error']?.toString() : null;
      throw Exception(error ?? 'Не удалось привязать аккаунт');
    }
  }
}
