import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/auth_controller.dart';

class AuthSplash extends StatelessWidget {
  const AuthSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoreColors.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'LORE',
              style: LoreTypography.headlineMd.copyWith(
                color: LoreColors.onSurface,
                letterSpacing: 2.4,
              ),
            ),
            const SizedBox(height: 18),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 14),
            Text(
              'Preparing your private archive…',
              style: LoreTypography.bodySm.copyWith(
                color: LoreColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LockScreen extends StatelessWidget {
  const LockScreen({super.key});

  Future<void> _confirmSignOut(BuildContext context) async {
    final auth = context.read<AuthController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out and forget this device?'),
        content: const Text(
          'The backend session will be revoked and the stored token removed. '
          'You will need a new pairing code from the LORE backend to reconnect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await auth.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: LoreColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'LORE',
                    style: LoreTypography.headlineMd.copyWith(
                      color: LoreColors.onSurface,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: LoreColors.primaryFixed,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: LoreColors.outlineVariant,
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      size: 38,
                      color: LoreColors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Your archive is locked',
                    textAlign: TextAlign.center,
                    style: LoreTypography.headlineMd.copyWith(
                      color: LoreColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Confirm your identity to open your documents. Private '
                    'content is not shown until this device is unlocked.',
                    textAlign: TextAlign.center,
                    style: LoreTypography.bodyMd.copyWith(
                      color: LoreColors.secondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: LoreColors.surfaceContainer,
                      borderRadius: LoreRadius.borderFull,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.fingerprint,
                          size: 15,
                          color: LoreColors.tertiary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            auth.capabilityLabel,
                            style: LoreTypography.labelSm.copyWith(
                              color: LoreColors.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (auth.error != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      auth.error!,
                      textAlign: TextAlign.center,
                      style: LoreTypography.bodySm.copyWith(
                        color: LoreColors.error,
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (auth.deviceAuthUnavailable) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Android could not provide a biometric or screen-lock '
                      'prompt on this device. The app session is still '
                      'protected by the backend token, but local unlock '
                      'confirmation is unavailable.',
                      textAlign: TextAlign.center,
                      style: LoreTypography.bodySm.copyWith(
                        color: LoreColors.secondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: auth.isBusy ? null : auth.unlock,
                      icon: auth.isBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: LoreColors.onPrimary,
                              ),
                            )
                          : const Icon(Icons.fingerprint, size: 20),
                      label: Text(
                        auth.isBusy
                            ? 'Waiting for authentication…'
                            : 'Unlock LORE',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: auth.isBusy
                        ? null
                        : () => _confirmSignOut(context),
                    style: TextButton.styleFrom(
                      foregroundColor: LoreColors.secondary,
                    ),
                    child: const Text('Sign out and forget this device'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    FocusScope.of(context).unfocus();
    await context.read<AuthController>().pair(_codeController.text);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final baseUrl = context.read<AuthController>().client.config.baseUrl;

    return Scaffold(
      backgroundColor: LoreColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LORE',
                    style: LoreTypography.headlineMd.copyWith(
                      color: LoreColors.onSurface,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Pair this device',
                    style: LoreTypography.headlineMd.copyWith(
                      color: LoreColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the one-time pairing code created by your LORE '
                    'backend. The code expires and is deleted after a '
                    'successful pairing.',
                    style: LoreTypography.bodyMd.copyWith(
                      color: LoreColors.secondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: LoreColors.surfaceContainerLow,
                      borderRadius: LoreRadius.borderMd,
                      border: Border.all(color: LoreColors.structuralLine),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ON THE BACKEND COMPUTER',
                          style: LoreTypography.labelSm.copyWith(
                            color: LoreColors.secondary,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Start the LORE server, then open data/pairing-code.txt '
                          'in the backend project folder.',
                          style: LoreTypography.bodySm.copyWith(
                            color: LoreColors.onSurface,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Connected to $baseUrl',
                          style: LoreTypography.labelSm.copyWith(
                            color: LoreColors.tertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _codeController,
                    enabled: !auth.isBusy,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _pair(),
                    decoration: InputDecoration(
                      labelText: 'Pairing code',
                      hintText: 'Paste the code from the backend',
                      prefixIcon: const Icon(Icons.key_outlined, size: 20),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show code' : 'Hide code',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 19,
                        ),
                      ),
                    ),
                  ),
                  if (auth.error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      auth.error!,
                      style: LoreTypography.bodySm.copyWith(
                        color: LoreColors.error,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: auth.isBusy ? null : _pair,
                      child: auth.isBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: LoreColors.onPrimary,
                              ),
                            )
                          : const Text('Pair and continue'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Pairing only exchanges a session token with your own '
                    'backend. It does not upload documents or contact any AI '
                    'provider.',
                    style: LoreTypography.bodySm.copyWith(
                      color: LoreColors.secondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
