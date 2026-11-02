import 'package:flutter/foundation.dart';

import '../core/error_text.dart';
import '../data/api_client.dart';
import '../data/models.dart';

/// Global provider and privacy state reported by the LORE backend.
class AppState extends ChangeNotifier {
  AppState({required this.client});

  final LoreApiClient client;

  SystemStatusResponse? _systemStatus;
  String? _backendError;
  AskStatusResponse? _askStatus;
  String? _askStatusError;
  bool _checkingSystem = false;
  bool _loadingAskStatus = false;
  bool _changingMode = false;
  String? _modeError;

  SystemStatusResponse? get systemStatus => _systemStatus;
  String? get backendError => _backendError;
  AskStatusResponse? get askStatus => _askStatus;
  String? get askStatusError => _askStatusError;
  bool get isCheckingSystem => _checkingSystem;
  bool get isLoadingAskStatus => _loadingAskStatus;
  bool get isChangingMode => _changingMode;
  String? get modeError => _modeError;

  bool get isOnline => _systemStatus?.isHealthy == true;
  bool get isBusy => _checkingSystem || _loadingAskStatus;

  String get aiMode => _askStatus?.mode ?? 'private';
  bool get isAssistedMode => aiMode == 'assisted';
  String get selectedProvider => _askStatus?.selectedProvider ?? 'extractive';
  String get privacyLabel => isAssistedMode ? 'Assisted' : 'Private';

  String get providerLabel => providerLabelFor(selectedProvider);
  bool get assistedAvailable => _askStatus?.externalProviderConfigured ?? false;
  bool get localModelReady => _askStatus?.localModelReady ?? false;
  bool get extractiveAvailable =>
      _askStatus?.providers['extractive']?.available ?? true;
  String? get localModelReason => _askStatus?.providers['local-llm']?.reason;
  String? get externalProviderReason =>
      _askStatus?.providers['external']?.reason;

  static String providerLabelFor(String provider) {
    switch (provider) {
      case 'extractive':
        return 'Extractive';
      case 'local-llm':
        return 'Local LLM';
      case 'assisted':
      case 'external':
        return 'Assisted';
      default:
        return provider;
    }
  }

  Future<void> initialize() async {
    await Future.wait([refreshSystem(), refreshAskStatus()]);
  }

  Future<void> refreshSystem() async {
    if (_checkingSystem) return;
    _checkingSystem = true;
    notifyListeners();
    try {
      _systemStatus = await client.getSystemStatus();
      _backendError = null;
    } catch (error) {
      _systemStatus = null;
      _backendError = describeError(error);
    } finally {
      _checkingSystem = false;
      notifyListeners();
    }
  }

  Future<void> refreshAskStatus() async {
    if (_loadingAskStatus) return;
    _loadingAskStatus = true;
    notifyListeners();
    try {
      _askStatus = await client.getAskStatus();
      _askStatusError = null;
    } catch (error) {
      _askStatusError = describeError(error);
    } finally {
      _loadingAskStatus = false;
      notifyListeners();
    }
  }

  Future<bool> setAiMode(String mode) async {
    final normalized = mode.trim().toLowerCase();
    if (normalized != 'private' && normalized != 'assisted') {
      _modeError = 'AI mode must be private or assisted.';
      notifyListeners();
      return false;
    }
    if (normalized == 'assisted' && !assistedAvailable) {
      _modeError =
          'Assisted Mode is unavailable because the LORE backend has no '
          'complete external AI provider configuration. Configure a valid '
          'endpoint and API key on the server before enabling it.';
      notifyListeners();
      return false;
    }
    _changingMode = true;
    _modeError = null;
    notifyListeners();
    try {
      final result = await client.setAiMode(normalized);
      final current = _askStatus;
      if (current != null) {
        _askStatus = AskStatusResponse(
          providers: current.providers,
          selectedProvider: result.selectedProvider,
          available: result.available,
          mode: result.mode,
          localModelReady: current.localModelReady,
          externalProviderConfigured: current.externalProviderConfigured,
        );
      }
      await refreshAskStatus();
      return true;
    } catch (error) {
      _modeError = describeError(error);
      await refreshAskStatus();
      return false;
    } finally {
      _changingMode = false;
      notifyListeners();
    }
  }

  void clearModeError() {
    if (_modeError == null) return;
    _modeError = null;
    notifyListeners();
  }

  /// Drops private backend metadata when the app locks or signs out.
  void clearSensitiveState() {
    _systemStatus = null;
    _backendError = null;
    _askStatus = null;
    _askStatusError = null;
    _checkingSystem = false;
    _loadingAskStatus = false;
    _changingMode = false;
    _modeError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    client.dispose();
    super.dispose();
  }
}
