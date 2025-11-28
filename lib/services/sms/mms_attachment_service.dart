import 'package:flutter/foundation.dart';

/// Service to store and retrieve MMS attachment information
/// Since MessageIndex doesn't store attachment details, we cache them here
class MmsAttachmentService {
  static final MmsAttachmentService _instance = MmsAttachmentService._internal();
  factory MmsAttachmentService() => _instance;
  MmsAttachmentService._internal();

  /// Cache of message ID -> attachment info
  final Map<String, List<MmsAttachmentInfo>> _attachmentCache = {};

  /// Store attachment info for a message
  void storeAttachments(String messageId, List<MmsAttachmentInfo> attachments) {
    if (attachments.isNotEmpty) {
      _attachmentCache[messageId] = attachments;
      debugPrint('[MmsAttachmentService] Stored ${attachments.length} attachments for message $messageId');
    }
  }

  /// Retrieve attachment info for a message
  List<MmsAttachmentInfo> getAttachments(String messageId) {
    return _attachmentCache[messageId] ?? [];
  }

  /// Clear attachment cache (useful for cleanup)
  void clearCache() {
    _attachmentCache.clear();
  }

  /// Clear attachments for a specific message
  void clearMessage(String messageId) {
    _attachmentCache.remove(messageId);
  }
}

/// Information about an MMS attachment
class MmsAttachmentInfo {
  final String partId;
  final String contentType;
  final String? name;
  final int? size;
  final String? uri; // Content URI from Android

  MmsAttachmentInfo({
    required this.partId,
    required this.contentType,
    this.name,
    this.size,
    this.uri,
  });

  /// Get filename from name or generate from content type
  String get filename {
    if (name != null && name!.isNotEmpty) {
      return name!;
    }
    // Generate filename from content type
    final extension = _getExtensionFromMimeType(contentType);
    return 'attachment_$partId$extension';
  }

  String _getExtensionFromMimeType(String mimeType) {
    final map = {
      'image/jpeg': '.jpg',
      'image/png': '.png',
      'image/gif': '.gif',
      'image/webp': '.webp',
      'video/mp4': '.mp4',
      'video/3gpp': '.3gp',
      'audio/mpeg': '.mp3',
      'audio/amr': '.amr',
      'application/pdf': '.pdf',
      'text/plain': '.txt',
    };
    return map[mimeType.toLowerCase()] ?? '.bin';
  }

  factory MmsAttachmentInfo.fromJson(Map<String, dynamic> json) {
    return MmsAttachmentInfo(
      partId: json['partId'] as String,
      contentType: json['contentType'] as String,
      name: json['name'] as String?,
      size: json['size'] as int?,
      uri: json['uri'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'partId': partId,
      'contentType': contentType,
      'name': name,
      'size': size,
      'uri': uri,
    };
  }
}

