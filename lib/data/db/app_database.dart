import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'actionmail.db');
    return openDatabase(
      path,
      version: 10,
      onCreate: (db, version) async {
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
            isRead INTEGER NOT NULL,
            isStarred INTEGER NOT NULL,
            isImportant INTEGER NOT NULL,
            folderLabel TEXT NOT NULL,
            prevFolderLabel TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE sender_prefs (
            sender TEXT PRIMARY KEY,
            localTag TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE pending_ops (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            accountId TEXT NOT NULL,
            messageId TEXT NOT NULL,
            action TEXT NOT NULL,
            retries INTEGER NOT NULL DEFAULT 0,
            lastAttempt INTEGER,
            status TEXT NOT NULL DEFAULT 'pending'
          )
        ''');
        await db.execute('''
          CREATE TABLE account_state (
            accountId TEXT PRIMARY KEY,
            lastHistoryId TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE action_feedback (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            messageId TEXT NOT NULL,
            subject TEXT NOT NULL,
            snippet TEXT NOT NULL,
            bodyContent TEXT,
            detectedActionDate INTEGER,
            detectedActionConfidence REAL,
            detectedActionText TEXT,
            userActionDate INTEGER,
            userActionConfidence REAL,
            userActionText TEXT,
            feedbackType TEXT NOT NULL,
            timestamp INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE messages ADD COLUMN folderLabel TEXT NOT NULL DEFAULT "INBOX"');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS sender_prefs (
              sender TEXT PRIMARY KEY,
              localTag TEXT
            )
          ''');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE messages ADD COLUMN prevFolderLabel TEXT');
        }
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS pending_ops (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              accountId TEXT NOT NULL,
              messageId TEXT NOT NULL,
              action TEXT NOT NULL,
              retries INTEGER NOT NULL DEFAULT 0,
              lastAttempt INTEGER,
              status TEXT NOT NULL DEFAULT 'pending'
            )
          ''');
        }
        if (oldVersion < 6) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS account_state (
              accountId TEXT PRIMARY KEY,
              lastHistoryId TEXT
            )
          ''');
        }
        if (oldVersion < 7) {
          await db.execute('ALTER TABLE messages ADD COLUMN subsLocal INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE messages ADD COLUMN shoppingLocal INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 8) {
          await db.execute('ALTER TABLE messages ADD COLUMN unsubLink TEXT');
        }
        if (oldVersion < 9) {
          await db.execute('ALTER TABLE messages ADD COLUMN unsubscribedLocal INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 10) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS action_feedback (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              messageId TEXT NOT NULL,
              subject TEXT NOT NULL,
              snippet TEXT NOT NULL,
              bodyContent TEXT,
              detectedActionDate INTEGER,
              detectedActionConfidence REAL,
              detectedActionText TEXT,
              userActionDate INTEGER,
              userActionConfidence REAL,
              userActionText TEXT,
              feedbackType TEXT NOT NULL,
              timestamp INTEGER NOT NULL
            )
          ''');
        }
      },
    );
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('pending_ops');
  }
}


