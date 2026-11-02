import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import 'lock_screen.dart';

/// Decides whether private app content may be shown.
///
/// The shell is built only after local device authentication succeeds, so
/// locked states never mount screens that request private backend data.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.child});

  final Widget child;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthController>().initialize();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final auth = context.read<AuthController>();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      auth.handleAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      auth.handleAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    if (auth.state != AuthState.unlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.popUntil((route) => route.isFirst);
        }
      });
    }

    switch (auth.state) {
      case AuthState.initializing:
        return const AuthSplash();
      case AuthState.pairingRequired:
        return const PairingScreen();
      case AuthState.locked:
        return const LockScreen();
      case AuthState.unlocked:
        return widget.child;
    }
  }
}
