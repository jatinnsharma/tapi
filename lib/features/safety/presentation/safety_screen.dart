import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../application/emergency_service.dart';
import '../domain/emergency_contact.dart';
import '../domain/emergency_helplines.dart';
import 'sos_button.dart';
import '../../../core/ui/confirm_destructive.dart';

/// `/safety`: the SOS button, the user's emergency contacts and India's
/// helplines.
class SafetyScreen extends ConsumerWidget {
  const SafetyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(emergencyContactsProvider);
    final contacts = contactsAsync.value ?? const <EmergencyContact>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Safety')),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          const SizedBox(height: 8),
          const Center(child: SosHoldButton()),
          const SizedBox(height: 12),
          Text(
            contacts.isEmpty
                ? 'Hold SOS to send your location. Add a contact below so '
                      'it goes straight to them.'
                : 'Hold SOS to text your location to '
                      '${contacts.length == 1 ? contacts.single.name : '${contacts.length} contacts'}.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.inkMuted, height: 1.4),
          ),
          const SizedBox(height: 24),
          SectionHeader(
            title: 'Emergency contacts',
            actionLabel: contacts.length < maxEmergencyContacts ? 'Add' : null,
            onAction: contacts.length < maxEmergencyContacts
                ? () => _editContact(context, ref)
                : null,
          ),
          const SizedBox(height: 8),
          if (contactsAsync.isLoading && contactsAsync.value == null)
            const LinearProgressIndicator()
          else if (contacts.isEmpty)
            EmptyStateCard(
              icon: Icons.contact_phone_outlined,
              title: 'No contacts yet',
              message:
                  'Add up to $maxEmergencyContacts people. They are kept on '
                  'this phone only.',
              actionLabel: 'Add contact',
              onAction: () => _editContact(context, ref),
            )
          else
            for (var i = 0; i < contacts.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SoftCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  onTap: () => _editContact(
                    context,
                    ref,
                    contact: contacts[i],
                    index: i,
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text(contacts[i].name),
                    subtitle: Text(
                      [
                        contacts[i].phone,
                        if (contacts[i].relationship.isNotEmpty)
                          contacts[i].relationship,
                      ].join(' · '),
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove ${contacts[i].name}',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        final removed = contacts[i];
                        final notifier = ref.read(
                          emergencyContactsProvider.notifier,
                        );
                        notifier.remove(i);
                        showUndoSnackBar(
                          context,
                          message: '${removed.name} removed',
                          onUndo: () => notifier.restore(i, removed),
                        );
                      },
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 24),
          const SectionHeader(title: 'Helplines in India'),
          const SizedBox(height: 8),
          for (final helpline in indiaHelplines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SoftCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(helpline.name),
                  subtitle: Text(helpline.description),
                  trailing: FilledButton.tonalIcon(
                    onPressed: () => launchUrl(dialUri(helpline.number)),
                    icon: const Icon(Icons.call, size: 18),
                    label: Text(helpline.number),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editContact(
    BuildContext context,
    WidgetRef ref, {
    EmergencyContact? contact,
    int? index,
  }) async {
    final saved = await showDialog<EmergencyContact>(
      context: context,
      builder: (_) => _ContactDialog(initial: contact),
    );
    if (saved == null) return;
    await ref
        .read(emergencyContactsProvider.notifier)
        .save(saved, index: index);
  }
}

class _ContactDialog extends StatefulWidget {
  const _ContactDialog({this.initial});

  final EmergencyContact? initial;

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late final _relationship = TextEditingController(
    text: widget.initial?.relationship,
  );

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _relationship.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      EmergencyContact(
        name: _name.text.trim(),
        phone: normalizePhone(_phone.text)!,
        relationship: _relationship.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add contact' : 'Edit contact'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter a name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                hintText: '+91 98765 43210',
              ),
              validator: (v) => normalizePhone(v ?? '') == null
                  ? 'Enter a phone number'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _relationship,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Relationship (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
