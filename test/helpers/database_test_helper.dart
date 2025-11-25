import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

/// Helper for database testing
/// Provides in-memory databases and cleanup utilities
class DatabaseTestHelper {
  static Database? _testDb;
  
  /// Get an in-memory test database
  static Future<Database> getTestDatabase() async {
    if (_testDb != null) return _testDb!;
    
    // Use in-memory database for tests
    _testDb = await openDatabase(
      inMemoryDatabasePath,
      version: 14, // Match your AppDatabase version
      onCreate: (db, version) async {
        // Create tables matching your schema
        await _createTestTables(db);
      },
    );
    
    return _testDb!;
  }
  
  /// Create test tables matching AppDatabase schema
  static Future<void> _createTestTables(Database db) async {
    // Messages table
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        threadId TEXT NOT NULL,
        accountId TEXT NOT NULL,
        historyId TEXT,
        internalDate INTEGER NOT NULL,
        fromAddr TEXT NOT NULL,
        toAddr TEXT NOT NULL,
        subject TEXT NOT NULL,
        snippet TEXT,
        hasAttachments INTEGER NOT NULL,
        gmailCategories TEXT NOT NULL,
        gmailSmartLabels TEXT NOT NULL,
        localTagPersonal TEXT,
        subsLocal INTEGER NOT NULL DEFAULT 0,
        shoppingLocal INTEGER NOT NULL DEFAULT 0,
        unsubLink TEXT,
        unsubscribedLocal INTEGER NOT NULL DEFAULT 0,
        actionDate INTEGER,
        actionConfidence REAL,
        actionInsightText TEXT,
        actionComplete INTEGER NOT NULL DEFAULT 0,
        hasAction INTEGER NOT NULL DEFAULT 0,
        isRead INTEGER NOT NULL,
        isStarred INTEGER NOT NULL,
        isImportant INTEGER NOT NULL,
        folderLabel TEXT NOT NULL,
        prevFolderLabel TEXT,
        lastUpdated INTEGER
      )
    ''');
    
    // Add other tables as needed (sender_prefs, action_feedback, etc.)
    // For now, just messages table is enough for most tests
  }
  
  /// Clear all data from test database
  static Future<void> clearTestDatabase() async {
    if (_testDb == null) return;
    
    await _testDb!.delete('messages');
    // Clear other tables as needed
  }
  
  /// Close and cleanup test database
  static Future<void> closeTestDatabase() async {
    if (_testDb != null) {
      await _testDb!.close();
      _testDb = null;
    }
  }
  
  /// Create a temporary file database for integration tests
  static Future<Database> createTempDatabase() async {
    final dbPath = path.join(
      Directory.systemTemp.path,
      'domail_test_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    
    return await openDatabase(
      dbPath,
      version: 14,
      onCreate: (db, version) async {
        await _createTestTables(db);
      },
    );
  }
}

