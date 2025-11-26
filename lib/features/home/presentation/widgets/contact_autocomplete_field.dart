import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/services/contacts/contact_model.dart';
import 'package:domail/services/contacts/contacts_provider.dart';
import 'package:domail/features/home/presentation/widgets/message_compose_type.dart';

typedef ContactSelectedCallback = void Function(Contact contact);

class ContactAutocompleteField extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final ComposeMessageType messageType;
  final String labelText;
  final String? hintText;
  final bool enabled;
  final ContactSelectedCallback? onContactSelected;
  final VoidCallback? onTapContactPicker;
  final FormFieldValidator<String>? validator;
  final InputDecoration? decoration;
  final TextStyle? style;

  const ContactAutocompleteField({
    super.key,
    required this.controller,
    required this.messageType,
    this.focusNode,
    this.labelText = 'To',
    this.hintText,
    this.enabled = true,
    this.onContactSelected,
    this.onTapContactPicker,
    this.validator,
    this.decoration,
    this.style,
  });

  @override
  ConsumerState<ContactAutocompleteField> createState() => _ContactAutocompleteFieldState();
}

class _ContactAutocompleteFieldState extends ConsumerState<ContactAutocompleteField> {
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsProvider);
    final contacts = contactsAsync.maybeWhen(
      data: (value) => value,
      orElse: () => const <Contact>[],
    );

    // Use contacts list length as key to force rebuild when contacts change
    final contactsKey = ValueKey<int>(contacts.length);
    
    return RawAutocomplete<Contact>(
      key: contactsKey,
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<Contact>.empty();
        }
        final lowerQuery = textEditingValue.text.toLowerCase();
        return contacts.where((contact) {
          if (!_supportsMessageType(contact, widget.messageType)) {
            return false;
          }
          final name = contact.name?.toLowerCase() ?? '';
          final email = contact.email?.toLowerCase() ?? '';
          final phone = contact.phone ?? '';
          return name.contains(lowerQuery) || email.contains(lowerQuery) || phone.contains(lowerQuery);
        }).take(8);
      },
      displayStringForOption: (contact) => _contactValue(contact, widget.messageType),
      onSelected: (contact) {
        widget.controller.text = _contactValue(contact, widget.messageType);
        widget.onContactSelected?.call(contact);
      },
      fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: textEditingController,
          focusNode: focusNode,
          decoration: widget.decoration ??
              InputDecoration(
                labelText: widget.labelText,
                hintText: widget.hintText ?? _defaultHint(widget.messageType),
                suffixIcon: IconButton(
                  tooltip: 'Contacts',
                  icon: const Icon(Icons.contact_page_outlined),
                  onPressed: !widget.enabled
                      ? null
                      : () async {
                          if (widget.onTapContactPicker != null) {
                            widget.onTapContactPicker!();
                          }
                        },
                ),
              ),
          enabled: widget.enabled,
          validator: widget.validator,
          style: widget.style,
          onFieldSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final theme = Theme.of(context);
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final contact = options.elementAt(index);
                  return ListTile(
                    title: Text(contact.displayName),
                    subtitle: contact.displaySubtitle != null ? Text(contact.displaySubtitle!) : null,
                    trailing: _buildTrailingIcon(theme, contact, widget.messageType),
                    onTap: () => onSelected(contact),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  bool _supportsMessageType(Contact contact, ComposeMessageType type) {
    switch (type) {
      case ComposeMessageType.email:
        return contact.hasEmail;
      case ComposeMessageType.sms:
      case ComposeMessageType.whatsapp:
        return contact.hasPhone;
    }
  }

  String _contactValue(Contact contact, ComposeMessageType type) {
    switch (type) {
      case ComposeMessageType.email:
        return contact.email ?? '';
      case ComposeMessageType.sms:
      case ComposeMessageType.whatsapp:
        return contact.phone ?? '';
    }
  }

  String _defaultHint(ComposeMessageType type) {
    switch (type) {
      case ComposeMessageType.email:
        return 'Enter email address';
      case ComposeMessageType.sms:
        return 'Enter phone number';
      case ComposeMessageType.whatsapp:
        return 'Enter WhatsApp phone';
    }
  }

  Widget? _buildTrailingIcon(ThemeData theme, Contact contact, ComposeMessageType type) {
    switch (type) {
      case ComposeMessageType.email:
        return contact.hasEmail ? Icon(Icons.email, color: theme.colorScheme.primary) : null;
      case ComposeMessageType.sms:
        return contact.hasPhone ? Icon(Icons.sms, color: theme.colorScheme.primary) : null;
      case ComposeMessageType.whatsapp:
        return contact.hasPhone ? Icon(Icons.chat, color: theme.colorScheme.primary) : null;
    }
  }
}

