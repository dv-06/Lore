import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_navigation.dart';
import '../state/app_state.dart';
import '../state/documents_controller.dart';
import 'ask_screen.dart';
import 'documents_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final appState = context.read<AppState>();
      final documents = context.read<DocumentsController>();
      appState.initialize();
      documents.load();
    });
  }

  void _selectTab(int index) {
    context.read<AppNavigation>().goToTab(index);
    if (index == 1) {
      context.read<DocumentsController>().load();
    } else if (index == 2) {
      context.read<AppState>().refreshAskStatus();
    }
  }

  Future<void> _retryConnection() async {
    final appState = context.read<AppState>();
    final documents = context.read<DocumentsController>();
    await appState.initialize();
    if (documents.hasLoaded) {
      await documents.refresh();
    } else {
      await documents.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final navigation = context.watch<AppNavigation>();
    final appState = context.watch<AppState>();
    final showBanner =
        appState.backendError != null && !appState.isCheckingSystem;

    Widget content = IndexedStack(
      index: navigation.index,
      children: const [
        HomeScreen(),
        DocumentsScreen(),
        AskScreen(),
        SettingsScreen(),
      ],
    );

    if (showBanner) {
      content = Column(
        children: [
          Material(
            color: LoreColors.errorContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      size: 16,
                      color: LoreColors.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        appState.backendError!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: LoreTypography.bodySm.copyWith(
                          color: LoreColors.onErrorContainer,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _retryConnection,
                      child: Text(
                        'Retry',
                        style: LoreTypography.labelMd.copyWith(
                          color: LoreColors.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: content,
            ),
          ),
        ],
      );
    }

    return Scaffold(
      body: content,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigation.index,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Documents',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Ask',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
