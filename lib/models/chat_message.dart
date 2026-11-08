class ChatMessage {
  const ChatMessage({
    required this.id, required this.userId, required this.text,
    required this.createdAt, required this.userName,
    this.mediaPath, this.mediaType, this.mediaDurationSeconds,
  });

  final String id, userId, text, userName;
  final DateTime createdAt;
  final String? mediaPath, mediaType;
  final int? mediaDurationSeconds;
  bool get hasMedia => mediaPath != null && mediaType != null;

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    return ChatMessage(
      id: map['id'].toString(), userId: map['user_id'].toString(),
      text: map['body'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'].toString()).toLocal(),
      userName: profile is Map<String, dynamic>
          ? (profile['name'] as String? ?? 'Пользователь') : 'Пользователь',
      mediaPath: map['media_path'] as String?,
      mediaType: map['media_type'] as String?,
      mediaDurationSeconds: map['media_duration_seconds'] as int?,
    );
  }
}
