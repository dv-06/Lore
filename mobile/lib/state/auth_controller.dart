import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/auth_store.dart';
import '../core/device_authenticator.dart';
import '../data/api_client.dart';

enum AuthState { initializing, pairingRequired, locked, unlocked }

/// Owns the local app-lock state and the backend bearer token.
///
/// The token lives in memory only while the app is unlocked. Locking removes
/// it from the API client, so no request can leave the phone until the user
/// authenticates locally again. The stored token is not installed into the API
/// client until device authentication succeeds, so a stale or revoked token
/// cannot silently restore access. Logging out also clears secure storage and
/// revokes the backend session where the backend is reachable.
class AuthController extends ChangeNotifier {
  AuthController({
    required this.client,
    required this.store,
    required this.authenticator,
  }) {
    client.onUnauthorized = handleUnauthorized;
  }

  static const List<int> autoLockOptions = [0, 60, 300, 900];

  final LoreApiClient client;
  final AuthStore store;
  final DeviceAuthenticator authenticator;

  /// Called when the authenticated session closes. In-memory documents,
  /// conversations, and status are cleared here.
  VoidCallback? onSessionClosed;

  AuthState _state = AuthState.initializing;
  String? _error;
  bool _busy = false;
  int _autoLockSeconds = 300;
  String _capabilityLabel = 'Checking device authentication…';
  bool _deviceAuthUnavailable = false;
  DateTime? _backgroundedAt;

  AuthState get state => _state;
  String? get error => _error;
  bool get isBusy => _busy;
  int get autoLockSeconds => _autoLockSeconds;
  String get capabilityLabel => _capabilityLabel;
  bool get deviceAuthUnavailable => _deviceAuthUnavailable;
  bool get isUnlocked => _state == AuthState.unlocked;

  static String autoLockLabel(int seconds) {
    if (seconds == 0) return 'Immediately';
    if (seconds < 60) return '$seconds seconds';
    if (seconds < 3600) {
      return '${seconds ~/ 60} minute${seconds == 60 ? '' : 's'}';
    }
    return '${seconds ~/ 3600} hour${seconds == 3600 ? '' : 's'}';
  }

  Future<void> initialize() async {
    _state = AuthState.initializing;
    _error = null;
    notifyListeners();

    unawaited(_refreshCapability());
    try {
      final storedSeconds = await store.readAutoLockSeconds();
      if (storedSeconds != null && storedSeconds >= 0) {
        _autoLockSeconds = storedSeconds;
      }
      final token = await store.readToken();
      if (token == null || token.isEmpty) {
        _state = AuthState.pairingRequired;
        notifyListeners();
        return;
      }

      // The token is intentionally not installed into the API client here.
      // Only unlock() may do that, and only after device authentication.
      _state = AuthState.locked;
      notifyListeners();
      await unlock();
    } catch (_) {
      _state = AuthState.pairingRequired;
      _error =
          'LORE could not read its secure session. Pair this device again.';
      notifyListeners();
    }
  }

  Future<void> unlock() async {
    if (_state != AuthState.locked || _busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final supported = await authenticator.isSupported();
      if (supported) {
        final outcome = await authenticator.authenticate(
          reason: 'Unlock LORE to view your private documents.',
        );
        if (!outcome.authenticated && !outcome.unavailable) {
          _error =
              outcome.message ?? 'Authentication failed. LORE stays locked.';
          return;
        }
        _deviceAuthUnavailable = outcome.unavailable;
      } else {
        _deviceAuthUnavailable = true;
      }

      // Read the token only after the local device check has passed.
      final token = await store.readToken();
      if (token == null || token.isEmpty) {
        _state = AuthState.pairingRequired;
        _error = 'LORE has no stored session. Pair this device again.';
        return;
      }

      client.setSessionToken(token);
      if (!await _isBackendSessionValid()) {
        await _forgetLocalToken();
        _state = AuthState.pairingRequired;
        _error =
            'This device session is no longer valid. Pair again using the '
            'code on the LORE backend.';
        return;
      }
      _enterUnlocked();
    } catch (_) {
      _error = 'Authentication failed. LORE stays locked.';
    } finally {
      _busy = false;
      await _refreshCapability();
      notifyListeners();
    }
  }

  /// Returns false only when the backend explicitly rejects the token with 401.
  ///
  /// Network and server errors are treated as offline: the local unlock still
  /// proceeds, and the first rejected request clears the session via
  /// [handleUnauthorized].
  Future<bool> _isBackendSessionValid() async {
    try {
      await client.getAuthSession();
      return true;
    } on ApiException catch (error) {
      return error.statusCode != 401;
    } catch (_) {
      return true;
    }
  }

  Future<bool> pair(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      _error = 'Enter the pairing code shown on the LORE backend.';
      notifyListeners();
      return false;
    }
    if (_busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final result = await client.pairWithCode(trimmed);
      await store.writeToken(result.token);
      _state = AuthState.locked;
      _busy = false;
      notifyListeners();
      await unlock();
      return true;
    } on ApiException catch (error) {
      _error = error.message;
      return false;
    } catch (_) {
      _error = 'Pairing failed. Check the backend and try again.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Closes the maintained in-memory session but keeps the stored token for
  /// the next local unlock.
  void lock() {
    if (_state != AuthState.unlocked) return;
    client.setSessionToken(null);
    _state = AuthState.locked;
    _error = null;
    _backgroundedAt = null;
    onSessionClosed?.call();
    notifyListeners();
  }

  /// Revokes the backend session, clears secure storage, and returns to pairing.
  ///
  /// When the backend cannot be reached, local credentials are still removed,
  /// but [AuthController.error] explicitly says that server-side revocation
  /// could not be confirmed.
  Future<void> logout() async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    var revokedRemotely = false;
    try {
      try {
        await client.logout();
        revokedRemotely = true;
      } on ApiException catch (error) {
        // A 401 means the backend already does not accept this token, so there
        // is nothing left to revoke. Any other failure is treated as offline.
        revokedRemotely = error.statusCode == 401;
      } catch (_) {
        revokedRemotely = false;
      }
      await _forgetLocalToken();
      _state = AuthState.pairingRequired;
      if (!revokedRemotely) {
        _error =
            'Signed out on this device. The LORE backend could not confirm '
            'revocation, so the server-side session may remain valid until it '
            'expires. Restart the backend and run python -m app.recovery to '
            'revoke all sessions.';
      }
      onSessionClosed?.call();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Revokes every backend session. Other paired devices must pair again.
  Future<bool> revokeAllSessions() async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await client.revokeAllSessions();
      await _forgetLocalToken();
      _state = AuthState.pairingRequired;
      onSessionClosed?.call();
      return true;
    } on ApiException catch (error) {
      _error = error.message;
      return false;
    } catch (_) {
      _error = 'Unable to revoke sessions. Check the backend connection.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> setAutoLockSeconds(int seconds) async {
    if (seconds < 0) return;
    _autoLockSeconds = seconds;
    notifyListeners();
    await store.writeAutoLockSeconds(seconds);
  }

  void handleAppPaused() {
    if (_state != AuthState.unlocked) return;
    _backgroundedAt = DateTime.now();
    if (_autoLockSeconds == 0) {
      lock();
    }
  }

  void handleAppResumed() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (_state != AuthState.unlocked || since == null) return;
    if (_autoLockSeconds == 0) {
      lock();
      return;
    }
    if (DateTime.now().difference(since).inSeconds >= _autoLockSeconds) {
      lock();
    }
  }

  void handleUnauthorized() {
    if (_state == AuthState.pairingRequired ||
        _state == AuthState.initializing) {
      return;
    }
    client.setSessionToken(null);
    _state = AuthState.pairingRequired;
    _error =
        'The backend rejected this session. Pair this device again using the '
        'code on the LORE backend.';
    unawaited(store.clearToken());
    onSessionClosed?.call();
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<void> _refreshCapability() async {
    try {
      final label = await authenticator.capabilityLabel();
      if (label != _capabilityLabel) {
        _capabilityLabel = label;
        notifyListeners();
      }
    } catch (_) {
      // Keep the previous label; capability is informational.
    }
  }

  void _enterUnlocked() {
    _state = AuthState.unlocked;
    _error = null;
    _backgroundedAt = null;
  }

  Future<void> _forgetLocalToken() async {
    client.setSessionToken(null);
    try {
      await store.clearToken();
    } catch (_) {
      // Secure storage failures are reported by the next pairing attempt.
    }
  }
}
