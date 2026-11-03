import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/jungle_illustrations.dart';

class _DemoAccount {
  const _DemoAccount(this.role, this.email, this.password);

  final String role;
  final String email;
  final String password;
}

const _demoAccounts = <_DemoAccount>[
  _DemoAccount('Admin', 'admin@jsk.edu', 'admin123'),
  _DemoAccount('Teacher', 'priya.teacher@jsk.edu', 'teacher123'),
  _DemoAccount('Student', 'rahul.student@jsk.edu', 'student123'),
  _DemoAccount('Guardian', 'kavita.guardian@jsk.edu', 'guardian123'),
  _DemoAccount('Staff', 'staff.demo@jsk.edu', 'demo1234'),
];

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hidePassword = true;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final store = context.read<AppStore>();
    final accepted = await store.login(_email.text, _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!accepted) {
      showMessage(
        context,
        store.rows('users').isEmpty
            ? 'No institute accounts are available. Configure the Supabase build values and try again.'
            : 'Email or password is incorrect.',
      );
      return;
    }
    final user = store.currentUser;
    if (user != null && user['phoneNotifs'] == null) {
      final enableNotifications = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.notifications_active_outlined),
          title: const Text('Stay up to date'),
          content: const Text(
            'Allow JSK Attendance to notify you about attendance, fees and institute notices? You can change this later in Settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (enableNotifications == true) {
        await store.requestPushPermission();
      } else {
        await store.setPushEnabled(false);
      }
    }
  }

  void _useDemoAccount(_DemoAccount account) {
    setState(() {
      _email.text = account.email;
      _password.text = account.password;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final line = isDark ? const Color(0xFF3B3B34) : const Color(0xFFC9C3B4);

    return Scaffold(
      body: Stack(
        children: [
          const JungleBackdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final topPadding = constraints.maxHeight < 780 ? 64.0 : 82.0;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16, topPadding, 16, 28),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 68),
                            child: Container(
                              decoration: BoxDecoration(
                                color: colors.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: line),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: .34),
                                    blurRadius: 42,
                                    offset: const Offset(0, 20),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(19),
                                child: Stack(
                                  children: [
                                    const Positioned(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      child: SizedBox(
                                        height: 4,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                AppTheme.marigold,
                                                AppTheme.coral,
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        22,
                                        40,
                                        22,
                                        22,
                                      ),
                                      child: Form(
                                        key: _formKey,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  width: 62,
                                                  height: 62,
                                                  padding: const EdgeInsets.all(
                                                    4,
                                                  ),
                                                  decoration:
                                                      const BoxDecoration(
                                                        color: Colors.white,
                                                        shape: BoxShape.circle,
                                                      ),
                                                  child: ClipOval(
                                                    child: Image.asset(
                                                      'assets/jsk_logo.png',
                                                      fit: BoxFit.contain,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 14),
                                                Expanded(
                                                  child: Text(
                                                    'JSK Institute',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: theme
                                                        .textTheme
                                                        .headlineSmall
                                                        ?.copyWith(
                                                          fontSize: 25,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                const Icon(
                                                  Icons.local_florist_rounded,
                                                  color: Color(0xFFE8749A),
                                                  size: 23,
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 13),
                                            Text(
                                              'ATTENDANCE REGISTER',
                                              style: TextStyle(
                                                color: colors.onSurfaceVariant,
                                                fontFamily: 'monospace',
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 2,
                                              ),
                                            ),
                                            const SizedBox(height: 26),
                                            if (store.rows('users').isEmpty &&
                                                store.cloudMessage != null) ...[
                                              _CloudMessage(
                                                message: store.cloudMessage!,
                                                connected:
                                                    store.onlineSyncConfigured,
                                              ),
                                              const SizedBox(height: 16),
                                            ],
                                            _FieldLabel('Email', color: colors),
                                            const SizedBox(height: 7),
                                            TextFormField(
                                              controller: _email,
                                              keyboardType:
                                                  TextInputType.emailAddress,
                                              textInputAction:
                                                  TextInputAction.next,
                                              autofillHints: const [
                                                AutofillHints.username,
                                                AutofillHints.email,
                                              ],
                                              decoration: const InputDecoration(
                                                hintText: 'you@jsk.edu',
                                              ),
                                              validator: (value) =>
                                                  (value == null ||
                                                      value.trim().isEmpty)
                                                  ? 'Enter your email address'
                                                  : null,
                                            ),
                                            const SizedBox(height: 16),
                                            _FieldLabel(
                                              'Password',
                                              color: colors,
                                            ),
                                            const SizedBox(height: 7),
                                            TextFormField(
                                              controller: _password,
                                              obscureText: _hidePassword,
                                              textInputAction:
                                                  TextInputAction.done,
                                              onFieldSubmitted: (_) =>
                                                  _signIn(),
                                              autofillHints: const [
                                                AutofillHints.password,
                                              ],
                                              decoration: InputDecoration(
                                                suffixIcon: IconButton(
                                                  tooltip: _hidePassword
                                                      ? 'Show password'
                                                      : 'Hide password',
                                                  onPressed: () => setState(
                                                    () => _hidePassword =
                                                        !_hidePassword,
                                                  ),
                                                  icon: Icon(
                                                    _hidePassword
                                                        ? Icons
                                                              .visibility_outlined
                                                        : Icons
                                                              .visibility_off_outlined,
                                                  ),
                                                ),
                                              ),
                                              validator: (value) =>
                                                  (value == null ||
                                                      value.isEmpty)
                                                  ? 'Enter your password'
                                                  : null,
                                            ),
                                            const SizedBox(height: 20),
                                            _GradientSignInButton(
                                              busy: _busy,
                                              onPressed: _busy ? null : _signIn,
                                            ),
                                            const SizedBox(height: 20),
                                            Divider(color: line, height: 1),
                                            const SizedBox(height: 17),
                                            Text(
                                              'DEMO ACCOUNTS',
                                              style: TextStyle(
                                                color: colors.onSurfaceVariant,
                                                fontFamily: 'monospace',
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 1.4,
                                              ),
                                            ),
                                            const SizedBox(height: 11),
                                            for (final account
                                                in _demoAccounts) ...[
                                              _DemoAccountButton(
                                                account: account,
                                                onTap: () =>
                                                    _useDemoAccount(account),
                                                line: line,
                                              ),
                                              const SizedBox(height: 8),
                                            ],
                                            if (store.cloudMessage != null &&
                                                store
                                                    .rows('users')
                                                    .isNotEmpty) ...[
                                              const SizedBox(height: 7),
                                              _CloudMessage(
                                                message: store.cloudMessage!,
                                                connected:
                                                    store.onlineSyncConfigured,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Center(child: SleepyLionIllustration()),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, {required this.color});
  final String label;
  final ColorScheme color;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      color: color.onSurfaceVariant,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    ),
  );
}

class _DemoAccountButton extends StatelessWidget {
  const _DemoAccountButton({
    required this.account,
    required this.onTap,
    required this.line,
  });

  final _DemoAccount account;
  final VoidCallback onTap;
  final Color line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.brightness == Brightness.dark
          ? AppTheme.night
          : const Color(0xFFEFEBE0),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: line),
          ),
          child: Row(
            children: [
              Text(
                account.role,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(' · ', style: TextStyle(color: theme.colorScheme.outline)),
              Expanded(
                child: Text(
                  account.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'use this',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloudMessage extends StatelessWidget {
  const _CloudMessage({required this.message, required this.connected});
  final String message;
  final bool connected;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        connected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );
}

class _GradientSignInButton extends StatelessWidget {
  const _GradientSignInButton({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(30),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(30),
      child: Ink(
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: <Color>[AppTheme.marigold, AppTheme.coral],
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.coral.withValues(alpha: .26),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: busy
              ? const SizedBox.square(
                  dimension: 21,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  'Sign in',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    ),
  );
}
