import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/services/contacts/contacts_provider.dart';
import 'package:domail/services/contacts/contact_model.dart';
import 'package:domail/shared/widgets/app_window_dialog.dart';
import 'package:domail/features/home/presentation/widgets/message_compose_type.dart';

/// Dialog for selecting a contact
/// Returns the selected contact's email or phone depending on messageType
class ContactPickerDialog extends ConsumerStatefulWidget {
  final ComposeMessageType messageType; // email, sms, or whatsapp
  
  const ContactPickerDialog({
    super.key,
    required this.messageType,
  });

  static Future<String?> show({
    required BuildContext context,
    required ComposeMessageType messageType,
  }) {
    return AppWindowDialog.show<String>(
      context: context,
      title: 'Select Contact',
      size: AppWindowSize.small,
      height: 500,
      child: ContactPickerDialog(messageType: messageType),
    );
  }

  @override
  ConsumerState<ContactPickerDialog> createState() => _ContactPickerDialogState();
}

class _ContactPickerDialogState extends ConsumerState<ContactPickerDialog> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      ref.read(contactSearchProvider.notifier).state = _searchController.text;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _selectContact(Contact contact) {
    String? value;
    
    switch (widget.messageType) {
      case ComposeMessageType.email:
        value = contact.email;
        break;
      case ComposeMessageType.sms:
      case ComposeMessageType.whatsapp:
        value = contact.phone;
        break;
    }
    
    if (value != null && value.isNotEmpty) {
      Navigator.of(context).pop(value);
    } else {
      // Show error if contact doesn't have the required field
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.messageType == ComposeMessageType.email
                ? 'This contact does not have an email address'
                : 'This contact does not have a phone number',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contactsAsync = ref.watch(filteredContactsProvider);

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search contacts...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            autofocus: true,
          ),
        ),
        const Divider(height: 1),
        // Contact list
        Expanded(
          child: contactsAsync.when(
            data: (contacts) {
              // Filter contacts based on message type
              final filteredContacts = contacts.where((contact) {
                switch (widget.messageType) {
                  case ComposeMessageType.email:
                    return contact.hasEmail;
                  case ComposeMessageType.sms:
                  case ComposeMessageType.whatsapp:
                    return contact.hasPhone;
                }
              }).toList();

              if (filteredContacts.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(
                      _searchController.text.isEmpty
                          ? 'No contacts available'
                          : 'No contacts found',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }

              return ListView.builder(
                itemCount: filteredContacts.length,
                itemBuilder: (context, index) {
                  final contact = filteredContacts[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      child: Text(
                        contact.displayName.isNotEmpty
                            ? contact.displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(contact.displayName),
                    subtitle: contact.displaySubtitle != null
                        ? Text(contact.displaySubtitle!)
                        : null,
                    trailing: widget.messageType == ComposeMessageType.email
                        ? (contact.hasEmail
                            ? Icon(Icons.email, color: theme.colorScheme.primary)
                            : null)
                        : (contact.hasPhone
                            ? Icon(Icons.phone, color: theme.colorScheme.primary)
                            : null),
                    onTap: () => _selectContact(contact),
                  );
                },
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, stack) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'Error loading contacts: $error',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

