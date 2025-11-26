import 'package:sqflite/sqflite.dart';
import 'package:domail/data/db/app_database.dart';
import 'package:domail/services/contacts/contact_model.dart';

/// Repository for contact database operations
class ContactRepository {
  final AppDatabase _dbProvider = AppDatabase();

  Future<Database> get _database async => _dbProvider.database;

  /// Get all contacts
  Future<List<Contact>> getAll() async {
    final db = await _database;
    final rows = await db.query(
      'contacts',
      orderBy: 'lastUsed DESC, name ASC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Get contact by ID
  Future<Contact?> getById(String id) async {
    final db = await _database;
    final rows = await db.query(
      'contacts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Get contact by email
  Future<Contact?> getByEmail(String email) async {
    final db = await _database;
    final rows = await db.query(
      'contacts',
      where: 'email = ?',
      whereArgs: [email.toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Get contact by phone
  Future<Contact?> getByPhone(String phone) async {
    final db = await _database;
    final normalizedPhone = _normalizePhone(phone);
    final rows = await db.query(
      'contacts',
      where: 'phone = ?',
      whereArgs: [normalizedPhone],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Search contacts by name, email, or phone
  Future<List<Contact>> search(String query) async {
    if (query.trim().isEmpty) return getAll();
    
    final db = await _database;
    final searchTerm = '%${query.toLowerCase()}%';
    final rows = await db.query(
      'contacts',
      where: 'LOWER(name) LIKE ? OR LOWER(email) LIKE ? OR phone LIKE ?',
      whereArgs: [searchTerm, searchTerm, searchTerm],
      orderBy: 'lastUsed DESC, name ASC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Upsert contact (insert or update if exists)
  Future<void> upsert(Contact contact) async {
    final db = await _database;
    await db.insert(
      'contacts',
      _toRow(contact),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Batch upsert contacts
  Future<void> upsertMany(List<Contact> contacts) async {
    if (contacts.isEmpty) return;
    final db = await _database;
    final batch = db.batch();
    for (final contact in contacts) {
      batch.insert(
        'contacts',
        _toRow(contact),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Delete contact by ID
  Future<void> delete(String id) async {
    final db = await _database;
    await db.delete(
      'contacts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete all contacts
  Future<void> deleteAll() async {
    final db = await _database;
    await db.delete('contacts');
  }

  /// Update lastUsed timestamp
  Future<void> updateLastUsed(String id, DateTime timestamp) async {
    final db = await _database;
    await db.update(
      'contacts',
      {'lastUsed': timestamp.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get last contact update time (from SharedPreferences or contacts table)
  Future<DateTime?> getLastUpdateTime() async {
    final db = await _database;
    // Check if we have a last_update_time setting (could use SharedPreferences too)
    // For now, we'll get the max lastUpdated from contacts
    final rows = await db.query(
      'contacts',
      columns: ['MAX(lastUpdated) as maxTime'],
    );
    if (rows.isEmpty || rows.first['maxTime'] == null) return null;
    final maxTime = rows.first['maxTime'] as int?;
    if (maxTime == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(maxTime);
  }

  /// Set last contact update time
  Future<void> setLastUpdateTime(DateTime timestamp) async {
    // Could use SharedPreferences or a settings table
    // For now, we'll track this via contact service
  }

  Map<String, Object?> _toRow(Contact contact) {
    return {
      'id': contact.id,
      'name': contact.name,
      'email': contact.email?.toLowerCase(),
      'phone': contact.phone != null ? _normalizePhone(contact.phone!) : null,
      'lastUsed': contact.lastUsed?.millisecondsSinceEpoch,
      'lastUpdated': contact.lastUpdated.millisecondsSinceEpoch,
    };
  }

  Contact _fromRow(Map<String, Object?> row) {
    return Contact(
      id: row['id'] as String,
      name: row['name'] as String?,
      email: row['email'] as String?,
      phone: row['phone'] as String?,
      lastUsed: row['lastUsed'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['lastUsed'] as int)
          : null,
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(row['lastUpdated'] as int),
    );
  }

  /// Normalize phone number (remove formatting, ensure + prefix)
  String _normalizePhone(String phone) {
    var normalized = phone.trim().replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    if (!normalized.startsWith('+')) {
      if (normalized.startsWith('00')) {
        normalized = '+${normalized.substring(2)}';
      } else {
        normalized = '+$normalized';
      }
    }
    return normalized;
  }
}

