class ChatMessage {
  const ChatMessage({
    required this.id, required this.userId, required this.text,
    required this.createdAt, required this.userName,
    this.mediaPath, this.mediaType, this.mediaDurationSeconds,
    this.replyToMessageId, this.replyToText, this.replyToUserName,
  });

  final String id, userId, text, userName;
  final DateTime createdAt;
  final String? mediaPath, mediaType;
  final int? mediaDurationSeconds;
  final int? replyToMessageId;
  final String? replyToText, replyToUserName;
  bool get hasMedia => mediaPath != null && mediaType != null;

  Map<String, dynamic> toCacheMap() => {
    'id': id, 'user_id': userId, 'body': text,
    'created_at': createdAt.toUtc().toIso8601String(),
    'user_name': userName, 'media_path': mediaPath,
    'media_type': mediaType, 'media_duration_seconds': mediaDurationSeconds,
    'reply_to_message_id': replyToMessageId, 'reply_to_text': replyToText,
    'reply_to_user_name': replyToUserName,
  };

  factory ChatMessage.fromCacheMap(Map<String, dynamic> map) => ChatMessage(
    id: map['id'].toString(), userId: map['user_id'].toString(),
    text: map['body'] as String? ?? '',
    createdAt: DateTime.parse(map['created_at'].toString()).toLocal(),
    userName: map['user_name'] as String? ?? 'Пользователь',
    mediaPath: map['media_path'] as String?, mediaType: map['media_type'] as String?,
    mediaDurationSeconds: map['media_duration_seconds'] as int?,
    replyToMessageId: map['reply_to_message_id'] as int?,
    replyToText: map['reply_to_text'] as String?,
    replyToUserName: map['reply_to_user_name'] as String?,
  );

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
      replyToMessageId: map['reply_to_message_id'] as int?,
      replyToText: map['reply_to_text'] as String?,
      replyToUserName: map['reply_to_user_name'] as String?,
    );
  }
}
