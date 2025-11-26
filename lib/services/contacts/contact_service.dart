import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:domail/data/repositories/message_repository.dart';
import 'package:domail/data/models/message_index.dart';
import 'package:domail/services/sms/sms_message_converter.dart';
import 'package:domail/services/contacts/contact_model.dart';
import 'package:domail/services/contacts/contact_repository.dart';
import 'package:domail/services/auth/google_auth_service.dart';

/// Service for managing contacts extracted from messages
class ContactService {
  final ContactRepository _repository = ContactRepository();
  final MessageRepository _messageRepository = MessageRepository();
  static const String _lastUpdateKey = 'contacts_last_update_time';

  /// Build contact list from all messages (initial build)
  Future<void> buildContactList() async {
    debugPrint('[ContactService] Building contact list from all messages...');
    final messages = await _getAllMessagesForAllAccounts();
    await _processMessages(messages);
    await _setLastUpdateTime(DateTime.now());
    debugPrint('[ContactService] Contact list built successfully');
  }

  /// Update contact list from new messages (incremental update)
  Future<void> updateContacts() async {
    final lastUpdateTime = await getLastUpdateTime();
    if (lastUpdateTime == null) {
      // First run - build full list
      await buildContactList();
      return;
    }

    debugPrint('[ContactService] Updating contacts from messages since ${lastUpdateTime.toIso8601String()}');
    
    // Get all messages since last update
    final allMessages = await _getAllMessagesForAllAccounts();
    final newMessages = allMessages.where((msg) {
      // Check if message is newer than last update
      // Use internalDate as proxy for when message was processed
      return msg.internalDate.isAfter(lastUpdateTime);
    }).toList();

    if (newMessages.isEmpty) {
      debugPrint('[ContactService] No new messages to process');
      return;
    }

    debugPrint('[ContactService] Processing ${newMessages.length} new messages');
    await _processMessages(newMessages);
    await _setLastUpdateTime(DateTime.now());
    debugPrint('[ContactService] Contact list updated successfully');
  }

  /// Process messages and extract contacts
  Future<void> _processMessages(List<MessageIndex> messages) async {
    final contactsMap = <String, Contact>{}; // id -> Contact
    final now = DateTime.now();

    for (final message in messages) {
      final isSms = SmsMessageConverter.isSmsMessage(message);
      
      if (isSms) {
        // Process SMS message - extract phone number
        final smsContact = _parseSmsContact(message, now);
        if (smsContact != null) {
          _mergeContact(contactsMap, smsContact);
        }
      } else {
        // Process email message - extract from INBOX and SENT
        if (message.folderLabel == 'INBOX') {
          // Extract sender from inbox
          final emailContacts = _parseEmailAddresses(message.from);
          for (final contact in emailContacts) {
            if (_shouldSkipEmailContact(contact.email)) {
              continue;
            }
            final emailContact = Contact(
              id: contact.email.toLowerCase(),
              name: contact.name,
              email: contact.email.toLowerCase(),
              phone: null,
              lastUsed: now,
              lastUpdated: now,
            );
            _mergeContact(contactsMap, emailContact);
          }
        }
        
        if (message.folderLabel == 'SENT') {
          // Extract recipients from sent
          final emailContacts = _parseEmailAddresses(message.to);
          for (final contact in emailContacts) {
            if (_shouldSkipEmailContact(contact.email)) {
              continue;
            }
            final emailContact = Contact(
              id: contact.email.toLowerCase(),
              name: contact.name,
              email: contact.email.toLowerCase(),
              phone: null,
              lastUsed: now,
              lastUpdated: now,
            );
            _mergeContact(contactsMap, emailContact);
          }
        }
      }
    }

    // Save all contacts to database
    if (contactsMap.isNotEmpty) {
      await _repository.upsertMany(contactsMap.values.toList());
    }
  }

  /// Parse SMS contact from message
  Contact? _parseSmsContact(MessageIndex message, DateTime timestamp) {
    // SMS from field format: "Contact Name <+1234567890>" or just "+1234567890"
    final from = message.from;
    
    // Extract phone number
    final phoneRegex = RegExp(r'<([^>]+)>');
    final match = phoneRegex.firstMatch(from);
    
    String? phone;
    String? name;
    
    if (match != null) {
      // Format: "Name <phone>"
      phone = _normalizePhone(match.group(1)!.trim());
      final namePart = from.replaceAll(match.group(0)!, '').trim();
      name = namePart.isNotEmpty ? namePart : null;
    } else {
      // Format: just phone number
      phone = _normalizePhone(from.trim());
      name = null;
    }

    if (phone.isEmpty) return null;

    return Contact(
      id: phone, // Use phone as ID for SMS contacts
      name: name,
      email: null,
      phone: phone,
      lastUsed: timestamp,
      lastUpdated: timestamp,
    );
  }

  /// Parse email addresses from address string
  List<({String name, String email})> _parseEmailAddresses(String addresses) {
    final results = <({String name, String email})>[];
    if (addresses.trim().isEmpty) return results;

    // Split on commas, but not commas inside angle brackets
    final parts = addresses.split(RegExp(r',(?![^<]*>)'));
    
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      
      final parsed = _parseSingleAddress(trimmed);
      if (parsed.email.isNotEmpty) {
        results.add(parsed);
      }
    }

    // If no results, try parsing the whole string
    if (results.isEmpty) {
      final parsed = _parseSingleAddress(addresses);
      if (parsed.email.isNotEmpty) {
        results.add(parsed);
      }
    }

    return results;
  }

  /// Parse single email address (handles "Name {email}" and "email" formats)
  ({String name, String email}) _parseSingleAddress(String address) {
    final angleEmailRegex = RegExp(r'<([^>]+)>');
    final match = angleEmailRegex.firstMatch(address);
    
    if (match != null) {
      // Format: "Name <email@example.com>"
      final email = match.group(1)!.trim().toLowerCase();
      final namePart = address.replaceAll(match.group(0)!, '').trim();
      final name = namePart.replaceAll('"', '').trim();
      return (name: name, email: email);
    } else if (address.contains('@')) {
      // Format: "email@example.com"
      return (name: '', email: address.trim().toLowerCase());
    } else {
      // Invalid format
      return (name: '', email: '');
    }
  }

  /// Merge contact into contacts map (handles merging email + phone for same person)
  void _mergeContact(Map<String, Contact> contactsMap, Contact newContact) {
    final existing = contactsMap[newContact.id];
    
    if (existing == null) {
      // New contact - check if we should merge with existing by email or phone
      Contact? toMerge;
      
      if (newContact.hasEmail) {
        // Check if contact with this email exists
        for (final contact in contactsMap.values) {
          if (contact.email == newContact.email) {
            toMerge = contact;
            break;
          }
        }
      }
      
      if (toMerge == null && newContact.hasPhone) {
        // Check if contact with this phone exists
        for (final contact in contactsMap.values) {
          if (contact.phone == newContact.phone) {
            toMerge = contact;
            break;
          }
        }
      }
      
      if (toMerge != null) {
        // Merge with existing contact
        final merged = Contact(
          id: toMerge.hasEmail ? toMerge.email!.toLowerCase() : toMerge.id,
          name: _chooseBetterName(toMerge.name, newContact.name),
          email: toMerge.email ?? newContact.email,
          phone: toMerge.phone ?? newContact.phone,
          lastUsed: _latestTime(toMerge.lastUsed, newContact.lastUsed),
          lastUpdated: DateTime.now(),
        );
        contactsMap.remove(toMerge.id);
        contactsMap[merged.id] = merged;
      } else {
        // Completely new contact
        contactsMap[newContact.id] = newContact;
      }
    } else {
      // Update existing contact
      final updated = Contact(
        id: existing.id,
        name: _chooseBetterName(existing.name, newContact.name),
        email: existing.email ?? newContact.email,
        phone: existing.phone ?? newContact.phone,
        lastUsed: _latestTime(existing.lastUsed, newContact.lastUsed),
        lastUpdated: DateTime.now(),
      );
      contactsMap[existing.id] = updated;
    }
  }

  /// Choose better name (non-empty, longer wins)
  String? _chooseBetterName(String? name1, String? name2) {
    if (name1 != null && name1.isNotEmpty) {
      if (name2 != null && name2.isNotEmpty && name2.length > name1.length) {
        return name2;
      }
      return name1;
    }
    return name2;
  }

  /// Get latest time (null-safe)
  DateTime? _latestTime(DateTime? time1, DateTime? time2) {
    if (time1 == null) return time2;
    if (time2 == null) return time1;
    return time1.isAfter(time2) ? time1 : time2;
  }

  /// Normalize phone number
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

  /// Skip auto-generated or unsubscribe addresses
  bool _shouldSkipEmailContact(String email) {
    final lower = email.toLowerCase();
    const blockedFragments = [
      'unsubscribe',
      'list-unsubscribe',
      'no-reply',
      'noreply',
      'do-not-reply',
      'donotreply',
      'mailer-daemon',
      'bounce',
    ];
    return blockedFragments.any(lower.contains);
  }

  /// Get all contacts
  Future<List<Contact>> getContacts() async {
    return _repository.getAll();
  }

  /// Add or update a contact manually
  Future<void> saveContact({
    String? id,
    String? name,
    String? email,
    String? phone,
    DateTime? lastUsed,
  }) async {
    final normalizedEmail = email?.trim().toLowerCase();
    final normalizedPhone = phone != null && phone.trim().isNotEmpty ? _normalizePhone(phone) : null;

    if ((normalizedEmail == null || normalizedEmail.isEmpty) &&
        (normalizedPhone == null || normalizedPhone.isEmpty)) {
      throw ArgumentError('Contact must have an email or phone number');
    }

    final contactId = id ?? normalizedEmail ?? normalizedPhone!;
    final contact = Contact(
      id: contactId,
      name: name?.trim().isNotEmpty == true ? name!.trim() : null,
      email: normalizedEmail,
      phone: normalizedPhone,
      lastUsed: lastUsed,
      lastUpdated: DateTime.now(),
    );

    await _repository.upsert(contact);
  }

  /// Delete contact
  Future<void> deleteContact(String id) async {
    await _repository.delete(id);
  }

  /// Clear all contacts from database and rebuild immediately
  Future<void> clearAllContacts() async {
    await _repository.deleteAll();
    // Clear the last update time so contacts will rebuild from scratch
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastUpdateKey);
    // Immediately rebuild the contact list from all messages
    await buildContactList();
    debugPrint('[ContactService] Contacts cleared and rebuilt from all messages');
  }

  /// Search contacts
  Future<List<Contact>> searchContacts(String query) async {
    return _repository.search(query);
  }

  /// Get contact by ID
  Future<Contact?> getContactById(String id) async {
    return _repository.getById(id);
  }

  /// Update last update time
  Future<void> _setLastUpdateTime(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastUpdateKey, time.millisecondsSinceEpoch);
  }

  /// Get last update time
  Future<DateTime?> getLastUpdateTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_lastUpdateKey);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Get all messages from all accounts (helper method)
  Future<List<MessageIndex>> _getAllMessagesForAllAccounts() async {
    // Get all accounts and query messages for each
    final googleAuthService = GoogleAuthService();
    final accounts = await googleAuthService.loadAccounts();
    
    final allMessages = <MessageIndex>[];
    for (final account in accounts) {
      final messages = await _messageRepository.getAll(account.id);
      allMessages.addAll(messages);
    }
    
    return allMessages;
  }
}

