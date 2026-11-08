/// A person who can sign in on the counter phone: the owner or a helper.
class Staff {
  const Staff({required this.id, required this.name, required this.role, this.permissions = const [], this.mustChangePin = false, this.locale});

  final int id;
  final String name;
  final String role; // 'owner' | 'helper'

  /// What this person may do right now (see core/permissions.dart). The
  /// server decides and enforces; the app uses this only to show or hide
  /// buttons, and re-reads it on every home load (GET me).
  final List<String> permissions;

  /// True when the PIN was set by someone else (the owner): it's temporary,
  /// and the person must choose their own before doing anything else.
  final bool mustChangePin;

  /// 'sw' or 'en': this person's language, the same on every phone and on the web.
  final String? locale;

  bool get isOwner => role == 'owner';

  /// The owner can always; anyone else only with an active grant.
  bool can(String permission) => isOwner || permissions.contains(permission);

  factory Staff.fromJson(Map<String, dynamic> json) => Staff(
        id: json['id'] as int,
        name: json['name'] as String,
        role: json['role'] as String,
        permissions: ((json['permissions'] as List?) ?? const []).cast<String>(),
        mustChangePin: json['must_change_pin'] == true,
        locale: json['locale'] as String?,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'role': role, 'permissions': permissions, 'must_change_pin': mustChangePin, 'locale': locale};
}
