class Tombstone {
  final String id;
  final int deletedAt; // milliseconds since epoch

  const Tombstone({required this.id, required this.deletedAt});

  Map<String, dynamic> toJson() => {'id': id, 'deletedAt': deletedAt};

  factory Tombstone.fromJson(Map<String, dynamic> json) => Tombstone(
        id: json['id'] as String,
        deletedAt: json['deletedAt'] as int,
      );

  Map<String, dynamic> toMap() => {'id': id, 'deleted_at': deletedAt};
}
