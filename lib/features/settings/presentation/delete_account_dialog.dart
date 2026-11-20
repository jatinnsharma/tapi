import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_components.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/friendly_error.dart';
import '../../album/application/album_uploader.dart';
import '../../album/data/album_queue_repository.dart';
import '../../auth/application/account_eraser.dart';
import '../../auth/application/auth_service.dart';
import '../../memories/data/shared_memory_service.dart';

/// Asks for the password (or Google) and deletes the account and the
/// user's data in the cloud. Opened from Settings → Account.
Future<void> showDeleteAccountDialog(BuildContext context, String uid) =>
    showDialog<void>(
      context: context,
      builder: (_) => _DeleteAccountDialog(uid: uid),
    );

/// What deleting removes and what stays, in plain words. Kept next to the
/// code that does it ([eraseAccountData]) so the two can't drift apart.
const deleteAccountRemoves = [
  'Your profile and profile photo',
  'Friends, feed posts, your shared map and live location',
  'Trips you saved to your account (you leave trips others shared '
      'with you)',
  'Your photos in trip albums, and their copies in your Google Drive '
      'uploaded from this phone',
  'Photos and voice notes you shared, place tips, published tours and '
      'friend challenges',
  'Groups and meetups you created (you leave the others)',
  'Your sign-in',
];

const deleteAccountStays = [
  'Messages you sent in group chats, under the name you used',
  'The server\'s record of your verified XP',
  'Everything on this phone: trips, memories and photos',
];

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog({required this.uid});

  final String uid;

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _working = true;
      _error = null;
    });
    final auth = ref.read(authServiceProvider);
    final store = ref.read(accountDataStoreProvider);
    final memories = ref.read(sharedMemoryServiceProvider);
    final uploader = ref.read(albumUploaderProvider);
    final queue = ref.read(albumQueueRepositoryProvider);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Confirm first (password, or Google again): nothing is deleted if it
      // fails.
      await auth.reauthenticate(auth.usesPassword ? _password.text : null);
      // Album copies in the user's own Drive (best effort: needs Drive).
      for (final photo in await queue.withDriveCopies()) {
        try {
          await uploader.remove(photo);
        } catch (_) {}
      }
      await memories.deleteAllFor(widget.uid);
      await eraseAccountData(store, widget.uid);
      await auth.deleteCurrentUser();
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Your account has been deleted.')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = e.code == 'wrong-password' || e.code == 'invalid-credential'
            ? 'That password is incorrect.'
            : googleSignInError(e.code) == null
            ? 'Confirm with Google to delete the account.'
            : 'Couldn\'t delete the account. ${friendlyAuthCode(e.code)}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        // Some data may already be gone; trying again finishes the job.
        _error =
            'Couldn\'t finish deleting. ${friendlyError(e)} Nothing was '
            'left half-done that trying again won\'t finish.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final usesPassword = ref.read(authServiceProvider).usesPassword;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    Widget bullets(List<String> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: Text(item, style: text.bodyMedium)),
              ],
            ),
          ),
      ],
    );
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This permanently deletes:', style: text.titleSmall),
            bullets(deleteAccountRemoves),
            const SizedBox(height: 12),
            Text('What stays:', style: text.titleSmall),
            bullets(deleteAccountStays),
            const SizedBox(height: 8),
            Text(
              'It can\'t be undone.',
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            if (usesPassword)
              TextField(
                controller: _password,
                obscureText: true,
                enabled: !_working,
                autofillHints: const [AutofillHints.password],
                // Rebuild so the delete button enables once there's a password.
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Confirm your password',
                ),
              )
            else
              Text(
                'You\'ll be asked to confirm with Google.',
                style: text.titleSmall,
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              StatusBanner(kind: StatusKind.error, title: _error!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        AppButton.danger(
          label: 'Delete my account',
          loading: _working,
          onPressed: usesPassword && _password.text.isEmpty ? null : _delete,
        ),
      ],
    );
  }
}
