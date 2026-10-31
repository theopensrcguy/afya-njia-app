/// A person who can sign in on the counter phone: the owner or a helper.
class Staff {
  const Staff({required this.id, required this.name, required this.role});

  final int id;
  final String name;
  final String role; // 'owner' | 'helper'

  bool get isOwner => role == 'owner';

  factory Staff.fromJson(Map<String, dynamic> json) => Staff(
        id: json['id'] as int,
        name: json['name'] as String,
        role: json['role'] as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'role': role};
}
