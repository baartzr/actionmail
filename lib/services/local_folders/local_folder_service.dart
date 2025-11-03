import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:actionmail/data/models/message_index.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service for managing local backup folders on desktop
/// Stores emails and attachments as files on the filesystem
class LocalFolderService {
  static const String _baseFolderName = 'local_backups';
  
  /// Get the base directory for local backups
  Future<Directory> _getBaseDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final backupsDir = Directory(path.join(appDocDir.path, _baseFolderName));
    if (!await backupsDir.exists()) {
      await backupsDir.create(recursive: true);
    }
    return backupsDir;
  }
  
  /// Get directory for a specific folder (supports nested paths like "Finance/Taxes")
  Future<Directory> _getFolderDirectory(String folderPath) async {
    final baseDir = await _getBaseDirectory();
    final folderDir = Directory(path.join(baseDir.path, folderPath));
    if (!await folderDir.exists()) {
      await folderDir.create(recursive: true);
    }
    return folderDir;
  }
  
  /// Get directory for a specific email within a folder
  Future<Directory> _getEmailDirectory(String folderName, String messageId) async {
    final folderDir = await _getFolderDirectory(folderName);
    final emailDir = Directory(path.join(folderDir.path, messageId));
    if (!await emailDir.exists()) {
      await emailDir.create(recursive: true);
    }
    return emailDir;
  }
  
  /// List all local backup folders (returns flat list for backward compatibility)
  Future<List<String>> listFolders() async {
    final tree = await listFoldersTree();
    return _flattenFolderTree(tree);
  }
  
  /// List folders as a tree structure with nested subfolders
  /// Returns a map where keys are folder paths and values are nested maps
  Future<Map<String, dynamic>> listFoldersTree() async {
    try {
      final baseDir = await _getBaseDirectory();
      if (!await baseDir.exists()) {
        return {};
      }
      
      final tree = <String, dynamic>{};
      await _buildFolderTree(baseDir, baseDir.path, tree);
      return tree;
    } catch (e) {
      debugPrint('[LocalFolderService] Error listing folders tree: $e');
      return {};
    }
  }
  
  /// Recursively build folder tree structure
  /// Uses folder names as keys (not full paths) to allow proper nesting
  Future<void> _buildFolderTree(Directory dir, String basePath, Map<String, dynamic> tree) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final entityName = path.basename(entity.path);
          // Skip hidden/system folders
          if (entityName.startsWith('.')) continue;
          
          // Check if this is an email directory (contains metadata.json)
          final metadataFile = File(path.join(entity.path, 'metadata.json'));
          final hasEmail = await metadataFile.exists();
          
          // Build subtree for this directory
          final subTree = <String, dynamic>{};
          await _buildFolderTree(entity, basePath, subTree);
          
          // Filter out standard email subdirectories (attachments) when checking for real subfolders
          final realSubFolders = <String, dynamic>{};
          for (final entry in subTree.entries) {
            // Skip "attachments" directory as it's part of email storage, not a real folder
            if (entry.key != 'attachments') {
              realSubFolders[entry.key] = entry.value;
            }
          }
          
          // Only add as folder if it's not an email directory OR has real subfolders (not just attachments)
          if (!hasEmail || realSubFolders.isNotEmpty) {
            // Use just the folder name as the key, not the full relative path
            // This allows proper nested structure where each level uses only folder names
            tree[entityName] = realSubFolders.isEmpty ? null : realSubFolders;
          }
        }
      }
    } catch (e) {
      debugPrint('[LocalFolderService] Error building folder tree: $e');
    }
  }
  
  /// Flatten folder tree to list of paths
  List<String> _flattenFolderTree(Map<String, dynamic> tree, [String prefix = '']) {
    final result = <String>[];
    for (final entry in tree.entries) {
      final fullPath = prefix.isEmpty ? entry.key : '$prefix/${entry.key}';
      result.add(fullPath);
      if (entry.value is Map<String, dynamic>) {
        result.addAll(_flattenFolderTree(entry.value as Map<String, dynamic>, fullPath));
      }
    }
    return result;
  }
  
  /// Create a new local backup folder
  /// [folderPath] can be a simple name or nested path like "Finance/Taxes"
  /// [parentPath] is optional parent folder path (null means root)
  Future<bool> createFolder(String folderName, {String? parentPath}) async {
    try {
      // Sanitize folder name (remove invalid characters)
      final sanitized = _sanitizeFolderName(folderName);
      if (sanitized.isEmpty) {
        return false;
      }
      
      final baseDir = await _getBaseDirectory();
      final fullPath = parentPath != null 
          ? path.join(parentPath, sanitized)
          : sanitized;
      final folderDir = Directory(path.join(baseDir.path, fullPath));
      
      // Check if folder already exists
      if (await folderDir.exists()) {
        debugPrint('[LocalFolderService] Folder "$fullPath" already exists');
        return false;
      }
      
      // Create the folder
      await folderDir.create(recursive: true);
      debugPrint('[LocalFolderService] Folder "$fullPath" created successfully');
      return true;
    } catch (e) {
      debugPrint('[LocalFolderService] Error creating folder: $e');
      return false;
    }
  }
  
  /// Rename a local backup folder
  Future<bool> renameFolder(String oldFolderPath, String newFolderName) async {
    try {
      // Sanitize new folder name
      final sanitized = _sanitizeFolderName(newFolderName);
      if (sanitized.isEmpty) {
        return false;
      }
      
      final baseDir = await _getBaseDirectory();
      final oldDir = Directory(path.join(baseDir.path, oldFolderPath));
      
      if (!await oldDir.exists()) {
        return false;
      }
      
      // Calculate new path
      final oldParent = path.dirname(oldFolderPath);
      final newPath = oldParent == '.' || oldParent.isEmpty
          ? sanitized
          : path.join(oldParent, sanitized);
      
      final newDir = Directory(path.join(baseDir.path, newPath));
      
      // Check if new folder already exists
      if (await newDir.exists()) {
        debugPrint('[LocalFolderService] Folder "$newPath" already exists');
        return false;
      }
      
      // Rename the folder
      await oldDir.rename(newDir.path);
      debugPrint('[LocalFolderService] Folder "$oldFolderPath" renamed to "$newPath"');
      return true;
    } catch (e) {
      debugPrint('[LocalFolderService] Error renaming folder: $e');
      return false;
    }
  }

  /// Delete a local backup folder and all its contents
  Future<bool> deleteFolder(String folderName) async {
    try {
      final folderDir = await _getFolderDirectory(folderName);
      if (await folderDir.exists()) {
        await folderDir.delete(recursive: true);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[LocalFolderService] Error deleting folder: $e');
      return false;
    }
  }
  
  /// Check if a folder exists
  Future<bool> folderExists(String folderName) async {
    try {
      final folderDir = await _getFolderDirectory(folderName);
      return await folderDir.exists();
    } catch (e) {
      return false;
    }
  }
  
  /// Save an email with its body and attachments to a local folder
  /// Returns true if successful
  Future<bool> saveEmailToFolder({
    required String folderName,
    required MessageIndex message,
    required String emailBodyHtml,
    required String accountId,
    required String? accessToken,
  }) async {
    try {
      final emailDir = await _getEmailDirectory(folderName, message.id);
      
      // 1. Save email body
      final bodyFile = File(path.join(emailDir.path, 'email.html'));
      await bodyFile.writeAsString(emailBodyHtml, encoding: utf8);
      
      // 2. Save metadata as JSON
      final metadata = {
        'id': message.id,
        'threadId': message.threadId,
        'accountId': message.accountId,
        'internalDate': message.internalDate.toIso8601String(),
        'from': message.from,
        'to': message.to,
        'subject': message.subject,
        'snippet': message.snippet,
        'hasAttachments': message.hasAttachments,
        'gmailCategories': message.gmailCategories,
        'gmailSmartLabels': message.gmailSmartLabels,
        'localTagPersonal': message.localTagPersonal,
        'subsLocal': message.subsLocal,
        'shoppingLocal': message.shoppingLocal,
        'unsubscribedLocal': message.unsubscribedLocal,
        'actionDate': message.actionDate?.toIso8601String(),
        'actionConfidence': message.actionConfidence,
        'actionInsightText': message.actionInsightText,
        'isRead': message.isRead,
        'isStarred': message.isStarred,
        'isImportant': message.isImportant,
        'folderLabel': message.folderLabel,
        'prevFolderLabel': message.prevFolderLabel,
        'savedAt': DateTime.now().toIso8601String(),
      };
      
      final metadataFile = File(path.join(emailDir.path, 'metadata.json'));
      await metadataFile.writeAsString(
        jsonEncode(metadata),
        encoding: utf8,
      );
      
      // 3. Download and save attachments if they exist
      if (message.hasAttachments && accessToken != null) {
        await _saveAttachments(
          emailDir: emailDir,
          messageId: message.id,
          accessToken: accessToken,
        );
      }
      
      debugPrint('[LocalFolderService] Saved email ${message.id} to folder $folderName');
      return true;
    } catch (e) {
      debugPrint('[LocalFolderService] Error saving email: $e');
      return false;
    }
  }
  
  /// Download and save attachments for an email
  Future<void> _saveAttachments({
    required Directory emailDir,
    required String messageId,
    required String accessToken,
  }) async {
    try {
      // Create attachments directory
      final attachmentsDir = Directory(path.join(emailDir.path, 'attachments'));
      if (!await attachmentsDir.exists()) {
        await attachmentsDir.create(recursive: true);
      }
      
      // Fetch full message to get attachment info
      final response = await http.get(
        Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$messageId?format=full'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      
      if (response.statusCode != 200) {
        debugPrint('[LocalFolderService] Failed to fetch message for attachments: ${response.statusCode}');
        return;
      }
      
      final messageData = jsonDecode(response.body) as Map<String, dynamic>;
      final payload = messageData['payload'] as Map<String, dynamic>?;
      
      if (payload == null) return;
      
      // Recursively find all attachments
      final attachments = <Map<String, dynamic>>[];
      void findAttachments(dynamic part) {
        if (part is! Map<String, dynamic>) return;
        
        final body = part['body'] as Map<String, dynamic>?;
        final attachmentId = body?['attachmentId'] as String?;
        
        if (attachmentId != null) {
          final filename = part['filename'] as String? ?? 'attachment';
          attachments.add({
            'attachmentId': attachmentId,
            'filename': filename,
            'mimeType': part['mimeType'] as String? ?? 'application/octet-stream',
            'size': body?['size'] as int? ?? 0,
          });
        }
        
        // Check nested parts
        final parts = part['parts'] as List<dynamic>?;
        if (parts != null) {
          for (final p in parts) {
            findAttachments(p);
          }
        }
      }
      
      findAttachments(payload);
      
      // Download each attachment
      for (final att in attachments) {
        final attachmentId = att['attachmentId'] as String;
        final filename = att['filename'] as String;
        final sanitizedFilename = _sanitizeFilename(filename);
        
        try {
          final attResponse = await http.get(
            Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$messageId/attachments/$attachmentId'),
            headers: {'Authorization': 'Bearer $accessToken'},
          );
          
          if (attResponse.statusCode == 200) {
            final attData = jsonDecode(attResponse.body) as Map<String, dynamic>;
            final data = attData['data'] as String?;
            
            if (data != null) {
              // Decode base64url
              final bytes = base64Url.decode(
                data.replaceAll('-', '+').replaceAll('_', '/'),
              );
              
              final attFile = File(path.join(attachmentsDir.path, '${attachmentId}_$sanitizedFilename'));
              await attFile.writeAsBytes(bytes);
              
              debugPrint('[LocalFolderService] Saved attachment: $sanitizedFilename');
            }
          }
        } catch (e) {
          debugPrint('[LocalFolderService] Error downloading attachment $filename: $e');
        }
      }
    } catch (e) {
      debugPrint('[LocalFolderService] Error saving attachments: $e');
    }
  }
  
  /// Load all saved emails from a folder
  Future<List<MessageIndex>> loadFolderEmails(String folderName) async {
    try {
      final folderDir = await _getFolderDirectory(folderName);
      if (!await folderDir.exists()) {
        return [];
      }
      
      final emails = <MessageIndex>[];
      final entities = folderDir.listSync();
      
      for (final entity in entities) {
        if (entity is Directory) {
          final messageId = path.basename(entity.path);
          final metadataFile = File(path.join(entity.path, 'metadata.json'));
          
          if (await metadataFile.exists()) {
            try {
              final metadataJson = await metadataFile.readAsString(encoding: utf8);
              final metadata = jsonDecode(metadataJson) as Map<String, dynamic>;
              
              final email = MessageIndex(
                id: metadata['id'] as String,
                threadId: metadata['threadId'] as String,
                accountId: metadata['accountId'] as String,
                internalDate: DateTime.parse(metadata['internalDate'] as String),
                from: metadata['from'] as String,
                to: metadata['to'] as String,
                subject: metadata['subject'] as String,
                snippet: metadata['snippet'] as String?,
                hasAttachments: metadata['hasAttachments'] as bool? ?? false,
                gmailCategories: (metadata['gmailCategories'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ?? [],
                gmailSmartLabels: (metadata['gmailSmartLabels'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ?? [],
                localTagPersonal: metadata['localTagPersonal'] as String?,
                subsLocal: metadata['subsLocal'] as bool? ?? false,
                shoppingLocal: metadata['shoppingLocal'] as bool? ?? false,
                unsubscribedLocal: metadata['unsubscribedLocal'] as bool? ?? false,
                actionDate: metadata['actionDate'] != null
                    ? DateTime.parse(metadata['actionDate'] as String)
                    : null,
                actionConfidence: metadata['actionConfidence'] as double?,
                actionInsightText: metadata['actionInsightText'] as String?,
                isRead: metadata['isRead'] as bool? ?? false,
                isStarred: metadata['isStarred'] as bool? ?? false,
                isImportant: metadata['isImportant'] as bool? ?? false,
                folderLabel: metadata['folderLabel'] as String? ?? 'INBOX',
                prevFolderLabel: metadata['prevFolderLabel'] as String?,
              );
              
              emails.add(email);
            } catch (e) {
              debugPrint('[LocalFolderService] Error loading email $messageId: $e');
            }
          }
        }
      }
      
      // Sort by date (most recent first)
      emails.sort((a, b) => b.internalDate.compareTo(a.internalDate));
      
      return emails;
    } catch (e) {
      debugPrint('[LocalFolderService] Error loading folder emails: $e');
      return [];
    }
  }
  
  /// Load email body from saved file
  Future<String?> loadEmailBody(String folderName, String messageId) async {
    try {
      final emailDir = await _getEmailDirectory(folderName, messageId);
      final bodyFile = File(path.join(emailDir.path, 'email.html'));
      
      if (await bodyFile.exists()) {
        return await bodyFile.readAsString(encoding: utf8);
      }
      return null;
    } catch (e) {
      debugPrint('[LocalFolderService] Error loading email body: $e');
      return null;
    }
  }
  
  /// Load attachment file path
  Future<String?> getAttachmentPath(String folderName, String messageId, String attachmentId) async {
    try {
      final emailDir = await _getEmailDirectory(folderName, messageId);
      final attachmentsDir = Directory(path.join(emailDir.path, 'attachments'));
      
      if (!await attachmentsDir.exists()) {
        return null;
      }
      
      final entities = attachmentsDir.listSync();
      for (final entity in entities) {
        if (entity is File && path.basename(entity.path).startsWith('${attachmentId}_')) {
          return entity.path;
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('[LocalFolderService] Error getting attachment path: $e');
      return null;
    }
  }
  
  /// Check if an email exists in a folder
  Future<bool> emailExistsInFolder(String folderName, String messageId) async {
    try {
      final emailDir = await _getEmailDirectory(folderName, messageId);
      final metadataFile = File(path.join(emailDir.path, 'metadata.json'));
      return await metadataFile.exists();
    } catch (e) {
      return false;
    }
  }
  
  /// Remove an email from a folder
  Future<bool> removeEmailFromFolder(String folderName, String messageId) async {
    try {
      final emailDir = await _getEmailDirectory(folderName, messageId);
      if (await emailDir.exists()) {
        await emailDir.delete(recursive: true);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[LocalFolderService] Error removing email: $e');
      return false;
    }
  }
  
  /// Sanitize folder name to be filesystem-safe
  String _sanitizeFolderName(String name) {
    // Remove invalid characters for folder names
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
  
  /// Sanitize filename to be filesystem-safe
  String _sanitizeFilename(String filename) {
    // Remove invalid characters for file names
    return filename
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .trim();
  }
}

