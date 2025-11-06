import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:flutter/foundation.dart';

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
      version: 14,
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
        // Create indexes for faster queries
        await db.execute('CREATE INDEX idx_messages_account_folder_date ON messages(accountId, folderLabel, internalDate DESC)');
        await db.execute('CREATE INDEX idx_messages_account_date ON messages(accountId, internalDate DESC)');
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
        if (oldVersion < 11) {
          // Add indexes for faster queries
          await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_account_folder_date ON messages(accountId, folderLabel, internalDate DESC)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_account_date ON messages(accountId, internalDate DESC)');
        }
        if (oldVersion < 12) {
          // Add actionComplete field
          await db.execute('ALTER TABLE messages ADD COLUMN actionComplete INTEGER NOT NULL DEFAULT 0');
          
          // Migrate existing data: detect "(Complete)" in actionInsightText and set actionComplete flag
          // Also clean the text by removing "(Complete)" marker
          final rows = await db.query('messages', columns: ['id', 'actionInsightText'], where: 'actionInsightText IS NOT NULL');
          final batch = db.batch();
          for (final row in rows) {
            final messageId = row['id'] as String;
            final actionText = row['actionInsightText'] as String?;
            if (actionText != null) {
              // Check if text contains "(Complete)" marker (case-insensitive)
              final hasComplete = actionText.toLowerCase().contains('complete');
              if (hasComplete) {
                // Set actionComplete flag
                batch.update(
                  'messages',
                  {'actionComplete': 1},
                  where: 'id=?',
                  whereArgs: [messageId],
                );
                
                // Clean the text by removing "(Complete)" marker only
                // Be careful not to remove legitimate uses of the word "complete"
                final cleanedText = actionText
                    .replaceAll(RegExp(r'\s*\(Complete\)\s*', caseSensitive: false), '')
                    .trim();
                
                // Only update if text changed
                if (cleanedText != actionText && cleanedText.isNotEmpty) {
                  batch.update(
                    'messages',
                    {'actionInsightText': cleanedText},
                    where: 'id=?',
                    whereArgs: [messageId],
                  );
                } else if (cleanedText.isEmpty) {
                  // If cleaned text is empty, set to null
                  batch.update(
                    'messages',
                    {'actionInsightText': null},
                    where: 'id=?',
                    whereArgs: [messageId],
                  );
                }
              }
            }
          }
          await batch.commit(noResult: true);
        }
        if (oldVersion < 13) {
          // Add hasAction field
          await db.execute('ALTER TABLE messages ADD COLUMN hasAction INTEGER NOT NULL DEFAULT 0');
          
          // Set hasAction based on existing actionDate or actionInsightText
          final rows = await db.query('messages', columns: ['id', 'actionDate', 'actionInsightText']);
          final batch = db.batch();
          for (final row in rows) {
            final messageId = row['id'] as String;
            final actionDate = row['actionDate'] as int?;
            final actionText = row['actionInsightText'] as String?;
            final hasAction = actionDate != null || (actionText != null && actionText.isNotEmpty);
            if (hasAction) {
              batch.update(
                'messages',
                {'hasAction': 1},
                where: 'id=?',
                whereArgs: [messageId],
              );
            }
          }
          await batch.commit(noResult: true);
        }
        if (oldVersion < 14) {
          // Add lastUpdated field for timestamp-based conflict resolution
          await db.execute('ALTER TABLE messages ADD COLUMN lastUpdated INTEGER');
        }
      },
    );
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('pending_ops');
  }

  /// Delete the entire database file (for testing/fresh start)
  Future<void> deleteDatabase() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'actionmail.db');
    final dbFile = File(path);
    if (await dbFile.exists()) {
      await dbFile.delete();
      debugPrint('[AppDatabase] Deleted database file: $path');
    }
  }
}


