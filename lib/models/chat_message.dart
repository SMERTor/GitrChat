class ChatMessage {
  final int id;
  final String userId;
  final String body;
  final String name;
  final DateTime createdAt;
  ChatMessage({required this.id, required this.userId, required this.body, required this.name, required this.createdAt});
  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
    id: map['id'] as int,
    userId: map['user_id'] as String,
    body: map['body'] as String,
    name: (map['profiles']?['name'] ?? 'Пользователь') as String,
    createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
  );
}
