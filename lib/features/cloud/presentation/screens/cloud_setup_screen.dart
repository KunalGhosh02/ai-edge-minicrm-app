import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:minicrm/app/router/app_router.dart';
import 'package:minicrm/features/assistant/presentation/controllers/assistant_controller.dart';
import 'package:minicrm/features/cloud/data/repositories/firestore_customer_session_repository.dart';
import 'package:minicrm/features/cloud/domain/entities/auth_user.dart';
import 'package:minicrm/features/cloud/domain/entities/customer_session.dart';
import 'package:minicrm/features/cloud/presentation/controllers/auth_controller.dart';
import 'package:minicrm/features/cloud/presentation/controllers/support_online_controller.dart';

class CloudSetupScreen extends ConsumerWidget {
  const CloudSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    final controller = ref.read(authControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Set up Support Bot')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _FirebaseStatusCard(),
            const SizedBox(height: 16),
            _AuthCard(
              status: state.status,
              onSignIn: controller.signInWithGoogle,
              onSignOut: controller.signOut,
            ),
            const SizedBox(height: 16),
            const _FirestoreCard(),
            const SizedBox(height: 16),
            const _SupportOnlineCard(),
            const SizedBox(height: 16),
            const _SessionsCard(),
          ],
        ),
      ),
    );
  }
}

class _FirebaseStatusCard extends StatelessWidget {
  const _FirebaseStatusCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final apps = Firebase.apps;
    final configured = apps.isNotEmpty;
    final projectId = configured ? apps.first.options.projectId : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  configured ? Icons.check_circle : Icons.error_outline,
                  color: configured
                      ? Colors.green
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  configured ? 'Firebase configured' : 'Firebase not configured',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (configured)
              Text('Project: $projectId', style: theme.textTheme.bodySmall)
            else
              Text(
                'Drop your google-services.json into android/app/ and rebuild '
                'the app. The Gradle plugin will pick it up automatically.',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.status,
    required this.onSignIn,
    required this.onSignOut,
  });

  final AuthStatus status;
  final Future<void> Function() onSignIn;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Account', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            switch (status) {
              AuthSignedIn(user: final u) => _SignedInBody(
                  user: u,
                  onSignOut: onSignOut,
                ),
              AuthSigningIn() => const _LoadingBody(label: 'Signing in…'),
              AuthError(message: final m) => _ErrorBody(
                  message: m,
                  onSignIn: onSignIn,
                ),
              AuthIdle() => _SignInBody(onSignIn: onSignIn),
            },
          ],
        ),
      ),
    );
  }
}

class _SignInBody extends StatelessWidget {
  const _SignInBody({required this.onSignIn});

  final Future<void> Function() onSignIn;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: onSignIn,
        icon: const Icon(Icons.login),
        label: const Text('Sign in with Google'),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onSignIn});

  final String message;
  final Future<void> Function() onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: onSignIn,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ),
      ],
    );
  }
}

class _SignedInBody extends StatelessWidget {
  const _SignedInBody({required this.user, required this.onSignOut});

  final AuthUser user;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        CircleAvatar(
          backgroundImage:
              user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
          child: user.photoUrl == null
              ? Text(_initial(user))
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.displayName ?? user.email,
                style: theme.textTheme.titleSmall,
              ),
              Text(user.email, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: onSignOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }

  String _initial(AuthUser u) {
    final source = u.displayName ?? u.email;
    return source.isEmpty ? '?' : source.characters.first.toUpperCase();
  }
}

class _SupportOnlineCard extends ConsumerWidget {
  const _SupportOnlineCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(supportOnlineControllerProvider);
    final controller = ref.read(supportOnlineControllerProvider.notifier);
    final signedIn = ref.watch(authControllerProvider).status is AuthSignedIn;
    final modelLoaded =
        ref.watch(assistantControllerProvider).currentModel != null;

    final (icon, color, label) = switch (state.status) {
      SupportOnline() => (
          Icons.check_circle,
          Colors.green,
          modelLoaded
              ? 'Online — listening for customer messages.'
              : 'Online without a loaded model. Customers will receive a '
                  'temporary auto-reply until you load one from the '
                  'Playground.',
        ),
      SupportConnecting() => (
          Icons.sync,
          theme.colorScheme.primary,
          'Connecting…',
        ),
      SupportOnlineError(message: final m) => (
          Icons.error_outline,
          theme.colorScheme.error,
          m,
        ),
      SupportOffline() => (
          Icons.pause_circle_outline,
          theme.colorScheme.outline,
          'Offline. Press Go online to start auto-responding to customer messages.',
        ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text('Support bot', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: state.status is SupportOnline
                  ? FilledButton.tonalIcon(
                      onPressed: controller.goOffline,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Go offline'),
                    )
                  : FilledButton.icon(
                      onPressed: signedIn ? controller.goOnline : null,
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Go online'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionsCard extends ConsumerWidget {
  const _SessionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authStatus = ref.watch(authControllerProvider).status;
    if (authStatus is! AuthSignedIn) {
      return const SizedBox.shrink();
    }
    final repo = ref.watch(customerSessionRepositoryProvider);
    return StreamBuilder<List<CustomerSession>>(
      stream: repo.watchSessions(authStatus.user.uid),
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? const <CustomerSession>[];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.forum_outlined),
                    const SizedBox(width: 8),
                    Text(
                      'Customer sessions (${sessions.length})',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  )
                else if (sessions.isEmpty)
                  Text(
                    'No customer sessions yet. They appear here as soon as '
                    'a customer message lands in Firestore.',
                    style: theme.textTheme.bodySmall,
                  )
                else
                  for (final session in sessions.take(5))
                    InkWell(
                      onTap: () => context.push(
                        AppRoute.customerChat(session.customerId),
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 4,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person_outline, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                session.customerName ?? session.customerId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            if (session.takenOver)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.support_agent,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            if (session.lastMessagePreview != null)
                              Expanded(
                                child: Text(
                                  session.lastMessagePreview!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            const Icon(Icons.chevron_right, size: 18),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FirestoreCard extends StatelessWidget {
  const _FirestoreCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String? projectId;
    var ready = false;
    try {
      projectId = FirebaseFirestore.instance.app.options.projectId;
      ready = true;
    } on Object {
      ready = false;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ready ? Icons.cloud_done : Icons.cloud_off,
                  color: ready
                      ? Colors.green
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Text('Firestore', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              ready
                  ? 'Firestore client initialized for project $projectId. '
                      'Chat sync will be wired in a follow-up.'
                  : 'Firestore is not initialized — configure Firebase first.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
