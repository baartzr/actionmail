import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/services/contacts/contact_model.dart';
import 'package:domail/services/contacts/contacts_provider.dart';
import 'package:domail/shared/widgets/app_window_dialog.dart';

class ContactsManagementDialog extends ConsumerStatefulWidget {
  const ContactsManagementDialog({super.key});

  static Future<void> show(BuildContext context) {
    return AppWindowDialog.show(
      context: context,
      title: 'Contacts',
      size: AppWindowSize.large,
      height: 600,
      child: const ContactsManagementDialog(),
    );
  }

  @override
  ConsumerState<ContactsManagementDialog> createState() => _ContactsManagementDialogState();
}

class _ContactsManagementDialogState extends ConsumerState<ContactsManagementDialog> {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contactsAsync = ref.watch(filteredContactsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search contacts',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add'),
                onPressed: () => _showEditDialog(context, ref),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: contactsAsync.when(
            data: (contacts) {
              if (contacts.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text(
                      'No contacts found',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }

              return ListView.separated(
                itemCount: contacts.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final contact = contacts[index];
                  return ListTile(
                    title: Text(contact.displayName),
                    subtitle: _buildSubtitle(contact),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _showEditDialog(context, ref, contact: contact),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                          onPressed: () => _confirmDelete(contact),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Text(
                  'Error loading contacts: $error',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget? _buildSubtitle(Contact contact) {
    final parts = <String>[];
    if (contact.email != null && contact.email!.isNotEmpty) {
      parts.add(contact.email!);
    }
    if (contact.phone != null && contact.phone!.isNotEmpty) {
      parts.add(contact.phone!);
    }
    if (parts.isEmpty) return null;
    return Text(parts.join(' • '));
  }

  Future<void> _showEditDialog(BuildContext context, WidgetRef ref, {Contact? contact}) async {
    final service = ref.read(contactServiceProvider);
    final nameController = TextEditingController(text: contact?.name ?? '');
    final emailController = TextEditingController(text: contact?.email ?? '');
    final phoneController = TextEditingController(text: contact?.phone ?? '');
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(contact == null ? 'Add Contact' : 'Edit Contact'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty && phoneController.text.trim().isEmpty) {
                    return 'Provide email or phone';
                  }
                  if (trimmed.isNotEmpty && !trimmed.contains('@')) {
                    return 'Invalid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty && emailController.text.trim().isEmpty) {
                    return 'Provide phone or email';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                await service.saveContact(
                  id: contact?.id,
                  name: nameController.text.trim(),
                  email: emailController.text.trim(),
                  phone: phoneController.text.trim(),
                  lastUsed: contact?.lastUsed,
                );
                if (context.mounted) {
                  Navigator.of(context).pop(true);
                }
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to save contact: $e')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true) {
      // Invalidate both providers to force UI update
      ref.invalidate(contactsProvider);
      ref.invalidate(filteredContactsProvider);
    }
  }

  Future<void> _confirmDelete(Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text('Delete ${contact.displayName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(contactServiceProvider).deleteContact(contact.id);
        if (!mounted) return;
        // Invalidate both providers to force UI update
        ref.invalidate(contactsProvider);
        ref.invalidate(filteredContactsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact deleted')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete contact: $e')),
        );
      }
    }
  }
}

