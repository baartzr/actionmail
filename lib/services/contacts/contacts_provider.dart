import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/services/contacts/contact_service.dart';
import 'package:domail/services/contacts/contact_model.dart';

/// Provider for ContactService singleton
final contactServiceProvider = Provider<ContactService>((ref) {
  return ContactService();
});

/// Provider for all contacts (auto-refreshes)
final contactsProvider = FutureProvider<List<Contact>>((ref) async {
  final service = ref.watch(contactServiceProvider);
  return service.getContacts();
});

/// Provider for contact search
final contactSearchProvider = StateProvider<String>((ref) => '');

/// Provider for filtered contacts based on search
final filteredContactsProvider = FutureProvider<List<Contact>>((ref) async {
  final service = ref.watch(contactServiceProvider);
  final searchQuery = ref.watch(contactSearchProvider);
  
  if (searchQuery.trim().isEmpty) {
    return service.getContacts();
  }
  
  return service.searchContacts(searchQuery);
});

