/// Contact model representing a person with email and/or phone
class Contact {
  final String id; // email address or normalized phone number
  final String? name;
  final String? email; // email address (nullable)
  final String? phone; // phone number (nullable, normalized format: +1234567890)
  final DateTime? lastUsed; // timestamp of last message with this contact
  final DateTime lastUpdated; // timestamp when this contact was last updated in DB

  const Contact({
    required this.id,
    this.name,
    this.email,
    this.phone,
    this.lastUsed,
    required this.lastUpdated,
  });

  bool get hasEmail => email?.isNotEmpty ?? false;
  bool get hasPhone => phone?.isNotEmpty ?? false;
  bool get hasName => name?.isNotEmpty ?? false;

  /// Get display name (name if available, otherwise email or phone)
  String get displayName {
    if (hasName) return name!;
    if (hasEmail) return email!;
    if (hasPhone) return phone!;
    return id;
  }

  /// Get display subtitle (email if has name and email, phone if has name and phone)
  String? get displaySubtitle {
    if (hasName) {
      if (hasEmail && hasPhone) return '$email • $phone';
      if (hasEmail) return email;
      if (hasPhone) return phone;
    }
    return null;
  }

  Contact copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    DateTime? lastUsed,
    DateTime? lastUpdated,
  }) {
    return Contact(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      lastUsed: lastUsed ?? this.lastUsed,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Contact && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Contact(id: $id, name: $name, email: $email, phone: $phone)';
  }
}

