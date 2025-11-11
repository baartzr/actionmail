import 'package:domail/data/models/message_index.dart';
import 'package:domail/constants/app_constants.dart';

/// Gmail API Message structure
/// This matches the actual Gmail API response format
class GmailMessage {
  final String id;
  final String threadId;
  final List<String> labelIds; // Only source of flags/categories
  final String? snippet;
  final String? historyId;
  final int internalDate; // Unix timestamp in milliseconds
  final MessagePayload? payload;
  final int? sizeEstimate;
  final String? raw; // Base64 encoded full message (optional)

  GmailMessage({
    required this.id,
    required this.threadId,
    required this.labelIds,
    this.snippet,
    this.historyId,
    required this.internalDate,
    this.payload,
    this.sizeEstimate,
    this.raw,
  });

  factory GmailMessage.fromJson(Map<String, dynamic> json) {
    // Gmail API returns internalDate as a string of milliseconds since epoch
    final internalDateRaw = json['internalDate'];
    final internalDateMs = internalDateRaw is String
        ? int.tryParse(internalDateRaw) ?? 0
        : (internalDateRaw is int ? internalDateRaw : 0);
    return GmailMessage(
      id: json['id'] as String,
      threadId: json['threadId'] as String,
      labelIds: (json['labelIds'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      snippet: json['snippet'] as String?,
      historyId: json['historyId'] as String?,
      internalDate: internalDateMs,
      payload: json['payload'] != null
          ? MessagePayload.fromJson(json['payload'] as Map<String, dynamic>)
          : null,
      sizeEstimate: json['sizeEstimate'] as int?,
      raw: json['raw'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'threadId': threadId,
      'labelIds': labelIds,
      if (snippet != null) 'snippet': snippet,
      if (historyId != null) 'historyId': historyId,
      'internalDate': internalDate,
      if (payload != null) 'payload': payload!.toJson(),
      if (sizeEstimate != null) 'sizeEstimate': sizeEstimate,
      if (raw != null) 'raw': raw,
    };
  }

  /// Convert Gmail API message to our MessageIndex
  /// Derives flags from labelIds
  MessageIndex toMessageIndex(String accountId) {
    // Derive flags from label IDs
    final isRead = !labelIds.contains('UNREAD');
    final isStarred = labelIds.contains('STARRED');
    final isImportant = labelIds.contains('IMPORTANT');
    
    // Extract Gmail categories from label IDs
    final gmailCategories = labelIds.where((label) => 
      AppConstants.allGmailCategories.contains(label)
    ).toList();

    // Determine folder/system label
    // Gmail does not have an ARCHIVE label; archived messages simply lack INBOX
    String folder = 'INBOX';
    if (labelIds.contains('TRASH')) {
      folder = 'TRASH';
    } else if (labelIds.contains('SPAM')) {
      folder = 'SPAM';
    } else if (labelIds.contains('SENT')) {
      folder = 'SENT';
    } else if (labelIds.contains('INBOX')) {
      folder = 'INBOX';
    } else {
      folder = 'ARCHIVE';
    }

    // Extract headers from payload
    final headers = payload?.headers ?? [];
    final fromHeader = headers.firstWhere(
      (h) => h.name.toLowerCase() == 'from',
      orElse: () => const MessageHeader(name: 'From', value: ''),
    );
    final toHeader = headers.firstWhere(
      (h) => h.name.toLowerCase() == 'to',
      orElse: () => const MessageHeader(name: 'To', value: ''),
    );
    final subjectHeader = headers.firstWhere(
      (h) => h.name.toLowerCase() == 'subject',
      orElse: () => const MessageHeader(name: 'Subject', value: ''),
    );

    // Check for attachments
    final hasAttachments = _hasAttachments(payload);

    // Parse date
    final date = DateTime.fromMillisecondsSinceEpoch(internalDate);

    return MessageIndex(
      id: id,
      threadId: threadId,
      accountId: accountId,
      historyId: historyId,
      internalDate: date,
      from: fromHeader.value,
      to: toHeader.value,
      subject: subjectHeader.value,
      snippet: snippet,
      hasAttachments: hasAttachments,
      gmailCategories: gmailCategories,
      gmailSmartLabels: [], // TODO: Extract from labelIds if needed
      isRead: isRead,
      isStarred: isStarred,
      isImportant: isImportant,
      folderLabel: folder,
      // Action detection would happen separately via heuristics
      actionDate: null,
      actionConfidence: null,
      actionInsightText: null,
    );
  }

  bool _hasAttachments(MessagePayload? payload) {
    if (payload == null) return false;
    
    // Check if payload has parts with attachments
    if (payload.parts != null) {
      for (final part in payload.parts!) {
        if (part.filename != null && part.filename!.isNotEmpty) {
          return true;
        }
        // Recursively check nested parts
        if (part.parts != null) {
          for (final nestedPart in part.parts!) {
            if (nestedPart.filename != null && nestedPart.filename!.isNotEmpty) {
              return true;
            }
          }
        }
      }
    }
    
    // Check if payload itself is an attachment
    if (payload.filename != null && payload.filename!.isNotEmpty) {
      return true;
    }
    
    return false;
  }
}

/// Message payload containing headers and body parts
class MessagePayload {
  final List<MessageHeader> headers;
  final String? body;
  final List<MessagePart>? parts;
  final String? mimeType;
  final String? filename;

  MessagePayload({
    required this.headers,
    this.body,
    this.parts,
    this.mimeType,
    this.filename,
  });

  factory MessagePayload.fromJson(Map<String, dynamic> json) {
    return MessagePayload(
      headers: (json['headers'] as List<dynamic>?)
              ?.map((e) => MessageHeader.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      body: json['body']?['data'] as String?,
      parts: (json['parts'] as List<dynamic>?)
          ?.map((e) => MessagePart.fromJson(e as Map<String, dynamic>))
          .toList(),
      mimeType: json['mimeType'] as String?,
      filename: json['filename'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'headers': headers.map((h) => h.toJson()).toList(),
      if (body != null) 'body': {'data': body},
      if (parts != null) 'parts': parts!.map((p) => p.toJson()).toList(),
      if (mimeType != null) 'mimeType': mimeType,
      if (filename != null) 'filename': filename,
    };
  }
}

/// Message header (From, To, Subject, etc.)
class MessageHeader {
  final String name;
  final String value;

  const MessageHeader({
    required this.name,
    required this.value,
  });

  factory MessageHeader.fromJson(Map<String, dynamic> json) {
    return MessageHeader(
      name: json['name'] as String,
      value: json['value'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'value': value,
    };
  }
}

/// Message part (for multipart messages)
class MessagePart {
  final String? partId;
  final String? mimeType;
  final String? filename;
  final List<MessageHeader> headers;
  final MessageBody? body;
  final List<MessagePart>? parts;

  MessagePart({
    this.partId,
    this.mimeType,
    this.filename,
    required this.headers,
    this.body,
    this.parts,
  });

  factory MessagePart.fromJson(Map<String, dynamic> json) {
    return MessagePart(
      partId: json['partId'] as String?,
      mimeType: json['mimeType'] as String?,
      filename: json['filename'] as String?,
      headers: (json['headers'] as List<dynamic>?)
              ?.map((e) => MessageHeader.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      body: json['body'] != null
          ? MessageBody.fromJson(json['body'] as Map<String, dynamic>)
          : null,
      parts: (json['parts'] as List<dynamic>?)
          ?.map((e) => MessagePart.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (partId != null) 'partId': partId,
      if (mimeType != null) 'mimeType': mimeType,
      if (filename != null) 'filename': filename,
      'headers': headers.map((h) => h.toJson()).toList(),
      if (body != null) 'body': body!.toJson(),
      if (parts != null) 'parts': parts!.map((p) => p.toJson()).toList(),
    };
  }
}

/// Message body (base64 encoded)
class MessageBody {
  final String? data; // Base64 encoded
  final int? size;
  final String? attachmentId;

  MessageBody({
    this.data,
    this.size,
    this.attachmentId,
  });

  factory MessageBody.fromJson(Map<String, dynamic> json) {
    return MessageBody(
      data: json['data'] as String?,
      size: json['size'] as int?,
      attachmentId: json['attachmentId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (data != null) 'data': data,
      if (size != null) 'size': size,
      if (attachmentId != null) 'attachmentId': attachmentId,
    };
  }
}
