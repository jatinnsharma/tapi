import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/firebase_status.dart';
import '../../../core/theme/app_components.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../../core/theme/glass.dart';
import '../../social/data/social_repository.dart';
import '../../social/domain/explorer_profile.dart';
import '../application/auth_service.dart';

/// Plain words for a Firebase sign-in error [code] (never the raw message).
String friendlyAuthError(String code) => friendlyAuthCode(code);

/// Sign in or create an account, with email and password or Google.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _isSubmitting = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Creates the explorer profile friends see, if there isn't one yet.
  /// Best effort: being signed in matters more, and the profile can be
  /// created or edited later, so a failure here never shows as a sign-in
  /// failure.
  Future<void> _ensureProfile(User user, {required String name}) async {
    try {
      final social = ref.read(socialRepositoryProvider);
      if (await social.getProfile(user.uid) != null) return;
      await social.upsertProfile(
        ExplorerProfile(
          uid: user.uid,
          displayName: name,
          photoUrl: user.photoURL,
          createdAt: DateTime.now(),
        ),
      );
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final authService = ref.read(authServiceProvider);
    final email = _emailController.text.trim();
    try {
      if (_isSignUp) {
        final name = _nameController.text.trim();
        final user = await authService.signUp(
          email: email,
          password: _passwordController.text,
          name: name,
        );
        if (user != null) await _ensureProfile(user, name: name);
      } else {
        await authService.signIn(
          email: email,
          password: _passwordController.text,
        );
      }
      _leave();
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = friendlyAuthCode(e.code));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Something went wrong. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Signed in: back to where the user came from (or the Friends tab).
  void _leave() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/social');
    }
  }

  Future<void> _google() async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final user = await ref.read(authServiceProvider).signInWithGoogle();
      if (user != null) {
        // First Google sign-in: create the explorer profile with the
        // Google name. A profile that already exists is left alone.
        await _ensureProfile(
          user,
          name: (user.displayName?.trim().isNotEmpty ?? false)
              ? user.displayName!.trim()
              : 'Explorer',
        );
      }
      _leave();
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = googleSignInError(e.code));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not sign in with Google. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _forgotPassword() async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => _ResetPasswordDialog(email: _emailController.text.trim()),
    );
    if (sent == true && mounted) {
      // Firebase doesn't say whether the email has an account (so nobody can
      // find out who uses the app), and neither does this message.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'If there\'s an account for that email, a reset link is on its '
            'way. Check your inbox and spam folder.',
          ),
        ),
      );
    }
  }

  void _toggleMode() => setState(() {
    _isSignUp = !_isSignUp;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final firebaseReady = ref.watch(firebaseReadyProvider);
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);

    if (!firebaseReady) {
      return Scaffold(
        appBar: AppBar(leading: const CloseButton()),
        body: const GateCard(
          icon: Icons.cloud_off_rounded,
          title: 'Sign-in unavailable',
          message:
              "Accounts aren't available in this version of the app yet. "
              'Everything else works without one.',
        ),
      );
    }

    return Scaffold(
      // A way back: Login is always opened on top of another screen.
      appBar: AppBar(leading: const CloseButton()),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FadeSlideIn(
                        child: HeroCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                                child: Image.asset(
                                  'assets/branding/tabi_logo.png',
                                  width: 56,
                                  height: 56,
                                  semanticLabel: 'Tabi',
                                ),
                              ),
                              const SizedBox(height: 16),
                              Semantics(
                                header: true,
                                child: Text(
                                  _isSignUp
                                      ? 'Create your Explorer account'
                                      : 'Welcome back, Explorer',
                                  style: text.headlineSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Back up your trips and explore with friends.',
                                style: text.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onPrimary
                                      .withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_isSignUp) ...[
                        TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          maxLength: 40,
                          decoration: const InputDecoration(
                            labelText: 'Your name',
                            helperText: 'What friends and other explorers see',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                            counterText: '',
                          ),
                          validator: nameProblem,
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                        ),
                        validator: (value) => looksLikeEmail(value ?? '')
                            ? null
                            : 'Enter a valid email',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_showPassword,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        autofillHints: [
                          _isSignUp
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          helperText: _isSignUp
                              ? 'At least 6 characters'
                              : null,
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _showPassword
                                ? 'Hide password'
                                : 'Show password',
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                        validator: (value) =>
                            (value == null || value.length < 6)
                            ? 'At least 6 characters'
                            : null,
                      ),
                      if (!_isSignUp)
                        Align(
                          alignment: Alignment.centerRight,
                          child: AppButton.tertiary(
                            label: 'Forgot password?',
                            onPressed: _isSubmitting ? null : _forgotPassword,
                          ),
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        StatusBanner(kind: StatusKind.error, title: _error!),
                      ],
                      const SizedBox(height: 16),
                      AppButton(
                        label: _isSignUp ? 'Create account' : 'Sign in',
                        expand: true,
                        loading: _isSubmitting,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              'or',
                              style: text.bodyMedium?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppButton.secondary(
                        label: 'Continue with Google',
                        icon: Icons.g_mobiledata,
                        expand: true,
                        onPressed: _isSubmitting ? null : _google,
                      ),
                      const SizedBox(height: 8),
                      AppButton.tertiary(
                        label: _isSignUp
                            ? 'Already have an account? Sign in'
                            : "Don't have an account? Create one",
                        onPressed: _isSubmitting ? null : _toggleMode,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for the email and sends a reset link. Pops true once sent.
class _ResetPasswordDialog extends ConsumerStatefulWidget {
  const _ResetPasswordDialog({required this.email});

  final String email;

  @override
  ConsumerState<_ResetPasswordDialog> createState() =>
      _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends ConsumerState<_ResetPasswordDialog> {
  late final _email = TextEditingController(text: widget.email);
  final _formKey = GlobalKey<FormState>();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || !_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .sendPasswordResetEmail(_email.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = friendlyAuthCode(e.code);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Couldn\'t send the email. Check your connection.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset password'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('We\'ll email you a link to choose a new password.'),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              onFieldSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              validator: (value) =>
                  looksLikeEmail(value ?? '') ? null : 'Enter a valid email',
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
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        AppButton(label: 'Send link', loading: _sending, onPressed: _send),
      ],
    );
  }
}
