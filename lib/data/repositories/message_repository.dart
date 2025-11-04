import 'dart:convert';
import 'package:actionmail/data/db/app_database.dart';
import 'package:actionmail/data/models/message_index.dart';
import 'package:sqflite/sqflite.dart';

class MessageRepository {
  final AppDatabase _dbProvider = AppDatabase();

  Future<void> upsertMessages(List<MessageIndex> messages) async {
    if (messages.isEmpty) return;
    final db = await _dbProvider.database;
    
    // Get existing messages to preserve unsubLink values
    final ids = messages.map((m) => m.id).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final existingRows = await db.query(
      'messages',
      columns: ['id', 'unsubLink'],
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    final existingUnsubLinks = <String, String?>{};
    for (final row in existingRows) {
      existingUnsubLinks[row['id'] as String] = row['unsubLink'] as String?;
    }
    
    final batch = db.batch();
    for (final m in messages) {
      final row = _toRow(m);
      // Preserve existing unsubLink if it exists
      final existingUnsubLink = existingUnsubLinks[m.id];
      if (existingUnsubLink != null) {
        row['unsubLink'] = existingUnsubLink;
      }
      batch.insert(
        'messages',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<MessageIndex>> getAll(String accountId) async {
    final db = await _dbProvider.database;
    final rows = await db.query('messages', where: 'accountId=?', whereArgs: [accountId], orderBy: 'internalDate DESC');
    return rows.map(_fromRow).toList();
  }

  Future<List<MessageIndex>> getByFolder(String accountId, String folderLabel) async {
    final db = await _dbProvider.database;
    final queryStart = DateTime.now();
    final rows = await db.query(
      'messages',
      where: 'accountId=? AND folderLabel=?',
      whereArgs: [accountId, folderLabel],
      orderBy: 'internalDate DESC',
    );
    final queryDuration = DateTime.now().difference(queryStart);
    if (rows.length > 10) {
      // ignore: avoid_print
      print('[DB] Query ${rows.length} rows took ${queryDuration.inMilliseconds}ms');
    }
    final parseStart = DateTime.now();
    final result = rows.map(_fromRow).toList();
    final parseDuration = DateTime.now().difference(parseStart);
    if (rows.length > 10) {
      // ignore: avoid_print
      print('[DB] Parse ${rows.length} rows took ${parseDuration.inMilliseconds}ms');
    }
    return result;
  }

  Future<MessageIndex?> getById(String messageId) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      'messages',
      where: 'id=?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<void> clearAll() async {
    await _dbProvider.clearAll();
  }

  /// Delete the entire database file (for testing/fresh start)
  Future<void> deleteDatabase() async {
    await _dbProvider.deleteDatabase();
  }

  Future<void> updateLocalTag(String messageId, String? localTag) async {
    final db = await _dbProvider.database;
    await db.update(
      'messages',
      {'localTagPersonal': localTag},
      where: 'id=?',
      whereArgs: [messageId],
    );
  }

  Future<void> setSenderDefaultLocalTag(String senderEmail, String? localTag) async {
    final db = await _dbProvider.database;
    await db.insert(
      'sender_prefs',
      {'sender': senderEmail, 'localTag': localTag},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, String?>> getAllSenderPrefs() async {
    final db = await _dbProvider.database;
    final rows = await db.query('sender_prefs');
    final map = <String, String?>{};
    for (final r in rows) {
      map[r['sender'] as String] = r['localTag'] as String?;
    }
    return map;
  }

  Future<void> updateStarred(String messageId, bool isStarred) async {
    final db = await _dbProvider.database;
    await db.update(
      'messages',
      {'isStarred': isStarred ? 1 : 0},
      where: 'id=?',
      whereArgs: [messageId],
    );
  }

  Future<void> updateRead(String messageId, bool isRead) async {
    final db = await _dbProvider.database;
    await db.update(
      'messages',
      {'isRead': isRead ? 1 : 0},
      where: 'id=?',
      whereArgs: [messageId],
    );
  }

  /// Update only label-related fields (categories, flags, folder) without replacing entire message
  /// This is used during incremental sync when only labels change
  Future<void> updateMessageLabelsAndFlags(
    String messageId,
    List<String> gmailCategories,
    List<String> gmailSmartLabels,
    bool isRead,
    bool isStarred,
    bool isImportant,
    String folderLabel,
  ) async {
    final db = await _dbProvider.database;
    // Check if CATEGORY_PURCHASES is in gmailCategories to set shoppingLocal
    final shoppingLocal = gmailCategories.contains('CATEGORY_PURCHASES');
    await db.update(
      'messages',
      {
        'gmailCategories': jsonEncode(gmailCategories),
        'gmailSmartLabels': jsonEncode(gmailSmartLabels),
        'shoppingLocal': shoppingLocal ? 1 : 0,
        'isRead': isRead ? 1 : 0,
        'isStarred': isStarred ? 1 : 0,
        'isImportant': isImportant ? 1 : 0,
        'folderLabel': folderLabel,
      },
      where: 'id=?',
      whereArgs: [messageId],
    );
  }

  Future<void> updateFolderWithPrev(String messageId, String newFolderLabel, {String? prevFolderLabel}) async {
    final db = await _dbProvider.database;
    await db.update(
      'messages',
      {
        'folderLabel': newFolderLabel,
        if (prevFolderLabel != null) 'prevFolderLabel': prevFolderLabel,
      },
      where: 'id=?',
      whereArgs: [messageId],
    );
  }

  /// Update folder without modifying prevFolderLabel (used for ARCHIVE<->TRASH moves)
  Future<void> updateFolderNoPrev(String messageId, String newFolderLabel) async {
    final db = await _dbProvider.database;
    await db.update(
      'messages',
      {
        'folderLabel': newFolderLabel,
      },
      where: 'id=?',
      whereArgs: [messageId],
    );
  }

  Future<void> restoreToPrev(String messageId) async {
    final db = await _dbProvider.database;
    // Set folderLabel back to prevFolderLabel (or INBOX if null), then clear prevFolderLabel
    await db.rawUpdate(
      'UPDATE messages SET folderLabel=COALESCE(prevFolderLabel, "INBOX"), prevFolderLabel=NULL WHERE id=?',
      [messageId],
    );
  }

  // Pending Gmail operations queue
  Future<int> enqueuePendingOp(String accountId, String messageId, String action) async {
    final db = await _dbProvider.database;
    return await db.insert('pending_ops', {
      'accountId': accountId,
      'messageId': messageId,
      'action': action,
      'retries': 0,
      'lastAttempt': null,
      'status': 'pending',
    });
  }

  Future<List<Map<String, dynamic>>> getPendingOps({int limit = 20}) async {
    final db = await _dbProvider.database;
    return await db.query('pending_ops', where: 'status = ?', whereArgs: ['pending'], orderBy: 'id ASC', limit: limit);
  }

  Future<void> markOpAttempted(int id, {required int retries, required DateTime when}) async {
    final db = await _dbProvider.database;
    await db.update('pending_ops', {
      'retries': retries,
      'lastAttempt': when.millisecondsSinceEpoch,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markOpDone(int id) async {
    final db = await _dbProvider.database;
    await db.update('pending_ops', {'status': 'done'}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markOpFailed(int id) async {
    final db = await _dbProvider.database;
    await db.update('pending_ops', {'status': 'failed'}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateAction(String messageId, DateTime? actionDate, String? actionText, [double? confidence, bool? actionComplete]) async {
    final db = await _dbProvider.database;
    // Determine if action exists (has date or text)
    final hasAction = actionDate != null || (actionText != null && actionText.isNotEmpty);
    final data = <String, Object?>{
      'actionDate': actionDate?.millisecondsSinceEpoch,
      'actionInsightText': actionText,
      'hasAction': hasAction ? 1 : 0,
      if (confidence != null) 'actionConfidence': confidence,
      if (actionComplete != null) 'actionComplete': actionComplete ? 1 : 0,
    };
    await db.update(
      'messages',
      data,
      where: 'id=?',
      whereArgs: [messageId],
    );
  }

  Future<Map<String, MessageIndex>> getByIds(String accountId, List<String> ids) async {
    if (ids.isEmpty) return {};
    final db = await _dbProvider.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      'messages',
      where: 'accountId=? AND id IN ($placeholders)',
      whereArgs: [accountId, ...ids],
    );
    final map = <String, MessageIndex>{};
    for (final r in rows) {
      final m = _fromRow(r);
      map[m.id] = m;
    }
    return map;
  }

  Future<void> updateLocalClassification(String messageId, {bool? subs, bool? shopping, String? unsubLink, bool? unsubscribed}) async {
    final db = await _dbProvider.database;
    final data = <String, Object?>{};
    if (subs != null) data['subsLocal'] = subs ? 1 : 0;
    if (shopping != null) data['shoppingLocal'] = shopping ? 1 : 0;
    if (unsubLink != null) data['unsubLink'] = unsubLink;
    if (unsubscribed != null) data['unsubscribedLocal'] = unsubscribed ? 1 : 0;
    if (data.isEmpty) return;
    await db.update('messages', data, where: 'id=?', whereArgs: [messageId]);
  }

  /// Mark all emails from a sender email address as unsubscribed
  /// senderEmail should be the extracted email address in lowercase (e.g., "user@example.com")
  Future<void> markSenderUnsubscribed(String accountId, String senderEmail) async {
    final db = await _dbProvider.database;
    // Extract email from fromAddr field (handles "Name <email@domain.com>" format)
    // We need to match emails where fromAddr contains the sender email (case-insensitive)
    // Use LOWER() for case-insensitive matching to handle "Name <Email@Domain.com>" formats
    // Match both "Name <email@domain.com>" and "email@domain.com" formats
    final lowerSender = senderEmail.toLowerCase();
    await db.update(
      'messages',
      {'unsubscribedLocal': 1},
      where: 'accountId=? AND (LOWER(fromAddr) LIKE ? OR LOWER(fromAddr) = ?)',
      whereArgs: [accountId, '%<$lowerSender>%', lowerSender],
    );
  }

  Future<String?> getUnsubLink(String messageId) async {
    final db = await _dbProvider.database;
    final rows = await db.query('messages', columns: ['unsubLink'], where: 'id=?', whereArgs: [messageId], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['unsubLink'] as String?;
  }

  Future<List<MessageIndex>> getUnclassifiedForBackground(String accountId, {int limit = 200}) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      'messages',
      where: 'accountId=? AND (subsLocal=0 OR shoppingLocal=0)',
      whereArgs: [accountId],
      orderBy: 'internalDate DESC',
      limit: limit,
    );
    return rows.map(_fromRow).toList();
  }

  // Account state (history)
  Future<String?> getLastHistoryId(String accountId) async {
    final db = await _dbProvider.database;
    final rows = await db.query('account_state', where: 'accountId=?', whereArgs: [accountId], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['lastHistoryId'] as String?;
  }

  Future<void> setLastHistoryId(String accountId, String historyId) async {
    final db = await _dbProvider.database;
    await db.insert(
      'account_state',
      {'accountId': accountId, 'lastHistoryId': historyId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Map<String, Object?> _toRow(MessageIndex m) {
    return {
      'id': m.id,
      'threadId': m.threadId,
      'accountId': m.accountId,
      'historyId': m.historyId,
      'internalDate': m.internalDate.millisecondsSinceEpoch,
      'fromAddr': m.from,
      'toAddr': m.to,
      'subject': m.subject,
      'snippet': m.snippet,
      'hasAttachments': m.hasAttachments ? 1 : 0,
      'gmailCategories': jsonEncode(m.gmailCategories),
      'gmailSmartLabels': jsonEncode(m.gmailSmartLabels),
      'localTagPersonal': m.localTagPersonal,
      'subsLocal': m.subsLocal ? 1 : 0,
      'shoppingLocal': m.shoppingLocal ? 1 : 0,
      'unsubLink': null,
      'unsubscribedLocal': m.unsubscribedLocal ? 1 : 0,
      'actionDate': m.actionDate?.millisecondsSinceEpoch,
      'actionConfidence': m.actionConfidence,
      'actionInsightText': m.actionInsightText,
      'actionComplete': m.actionComplete ? 1 : 0,
      'hasAction': m.hasAction ? 1 : 0,
      'isRead': m.isRead ? 1 : 0,
      'isStarred': m.isStarred ? 1 : 0,
      'isImportant': m.isImportant ? 1 : 0,
      'folderLabel': m.folderLabel,
      'prevFolderLabel': m.prevFolderLabel,
    };
  }

  MessageIndex _fromRow(Map<String, Object?> row) {
    // Optimize JSON decoding: parse once and reuse
    final categoriesJson = row['gmailCategories'] as String;
    final labelsJson = row['gmailSmartLabels'] as String;
    List<String> gmailCategories;
    List<String> gmailSmartLabels;
    
    // Fast path for empty arrays (most common case)
    if (categoriesJson == '[]') {
      gmailCategories = const [];
    } else {
      gmailCategories = (jsonDecode(categoriesJson) as List<dynamic>).cast<String>();
    }
    
    if (labelsJson == '[]') {
      gmailSmartLabels = const [];
    } else {
      gmailSmartLabels = (jsonDecode(labelsJson) as List<dynamic>).cast<String>();
    }
    
    return MessageIndex(
      id: row['id'] as String,
      threadId: row['threadId'] as String,
      accountId: row['accountId'] as String,
      historyId: row['historyId'] as String?,
      internalDate: DateTime.fromMillisecondsSinceEpoch(row['internalDate'] as int),
      from: row['fromAddr'] as String,
      to: row['toAddr'] as String,
      subject: row['subject'] as String,
      snippet: row['snippet'] as String?,
      hasAttachments: (row['hasAttachments'] as int) == 1,
      gmailCategories: gmailCategories,
      gmailSmartLabels: gmailSmartLabels,
      localTagPersonal: row['localTagPersonal'] as String?,
      subsLocal: (row['subsLocal'] as int? ?? 0) == 1,
      shoppingLocal: (row['shoppingLocal'] as int? ?? 0) == 1,
      unsubscribedLocal: (row['unsubscribedLocal'] as int? ?? 0) == 1,
      // unsubLink not present on model yet, but we can expose via separate getter if needed
      actionDate: row['actionDate'] != null ? DateTime.fromMillisecondsSinceEpoch(row['actionDate'] as int) : null,
      actionConfidence: (row['actionConfidence'] as num?)?.toDouble(),
      actionInsightText: row['actionInsightText'] as String?,
      actionComplete: (row['actionComplete'] as int? ?? 0) == 1,
      // hasAction: derive from actionDate/actionInsightText if column doesn't exist (for backwards compatibility)
      hasAction: row.containsKey('hasAction') 
          ? (row['hasAction'] as int? ?? 0) == 1
          : (row['actionDate'] != null || (row['actionInsightText'] != null && (row['actionInsightText'] as String).isNotEmpty)),
      isRead: (row['isRead'] as int) == 1,
      isStarred: (row['isStarred'] as int) == 1,
      isImportant: (row['isImportant'] as int) == 1,
      folderLabel: row['folderLabel'] as String,
      prevFolderLabel: row['prevFolderLabel'] as String?,
    );
  }

  /// Get unread count for a specific folder
  Future<int> getUnreadCountByFolder(String accountId, String folderLabel) async {
    final db = await _dbProvider.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages WHERE accountId=? AND folderLabel=? AND isRead=0',
      [accountId, folderLabel],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get starred count for an account (across all folders)
  Future<int> getStarredCount(String accountId) async {
    final db = await _dbProvider.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages WHERE accountId=? AND isStarred=1',
      [accountId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get important count for an account (across all folders)
  Future<int> getImportantCount(String accountId) async {
    final db = await _dbProvider.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages WHERE accountId=? AND isImportant=1',
      [accountId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get unread count for an account (across all folders)
  Future<int> getUnreadCount(String accountId) async {
    final db = await _dbProvider.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages WHERE accountId=? AND isRead=0',
      [accountId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}


