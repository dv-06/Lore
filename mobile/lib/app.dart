import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/auth_store.dart';
import 'core/device_authenticator.dart';
import 'core/theme.dart';
import 'data/api_client.dart';
import 'screens/app_shell.dart';
import 'screens/auth_gate.dart';
import 'state/app_navigation.dart';
import 'state/app_state.dart';
import 'state/ask_controller.dart';
import 'state/auth_controller.dart';
import 'state/documents_controller.dart';

class LoreApp extends StatefulWidget {
  const LoreApp({
    super.key,
    this.client,
    this.authStore,
    this.deviceAuthenticator,
  });

  final LoreApiClient? client;
  final AuthStore? authStore;
  final DeviceAuthenticator? deviceAuthenticator;

  @override
  State<LoreApp> createState() => _LoreAppState();
}

class _LoreAppState extends State<LoreApp> {
  late final LoreApiClient _client;
  late final AppState _appState;
  late final DocumentsController _documents;
  late final AskController _ask;
  late final AppNavigation _navigation;
  late final AuthController _auth;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? LoreApiClient();
    _appState = AppState(client: _client);
    _documents = DocumentsController(client: _client);
    _ask = AskController(client: _client, appState: _appState);
    _navigation = AppNavigation();
    _auth = AuthController(
      client: _client,
      store: widget.authStore ?? SecureAuthStore(),
      authenticator: widget.deviceAuthenticator ?? LocalDeviceAuthenticator(),
    );
    _auth.onSessionClosed = () {
      _appState.clearSensitiveState();
      _documents.reset();
      _ask.clearAllConversations();
      _navigation.reset();
    };
  }

  @override
  void dispose() {
    _auth.dispose();
    _ask.dispose();
    _documents.dispose();
    _navigation.dispose();
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<LoreApiClient>.value(value: _client),
        ChangeNotifierProvider<AppState>.value(value: _appState),
        ChangeNotifierProvider<DocumentsController>.value(value: _documents),
        ChangeNotifierProvider<AskController>.value(value: _ask),
        ChangeNotifierProvider<AppNavigation>.value(value: _navigation),
        ChangeNotifierProvider<AuthController>.value(value: _auth),
      ],
      child: MaterialApp(
        title: 'LORE',
        debugShowCheckedModeBanner: false,
        theme: LoreTheme.light,
        home: const AuthGate(child: AppShell()),
      ),
    );
  }
}
