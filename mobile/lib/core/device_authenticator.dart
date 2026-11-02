import 'package:local_auth/local_auth.dart';

class DeviceAuthOutcome {
  final bool authenticated;

  /// True when the device has no usable biometric or device credential.
  /// The app cannot raise an OS prompt in that case and reports it honestly.
  final bool unavailable;
  final String? message;

  const DeviceAuthOutcome.authenticated()
    : authenticated = true,
      unavailable = false,
      message = null;

  const DeviceAuthOutcome.failed(String this.message)
    : authenticated = false,
      unavailable = false;

  const DeviceAuthOutcome.unavailable([this.message])
    : authenticated = false,
      unavailable = true;
}

/// Gate in front of the local app session.
///
/// This protects the unlocked UI on the device. It is not the backend API
/// boundary; the bearer token independently protects remote data.
abstract class DeviceAuthenticator {
  Future<bool> isSupported();
  Future<String> capabilityLabel();
  Future<DeviceAuthOutcome> authenticate({required String reason});
}

class LocalDeviceAuthenticator implements DeviceAuthenticator {
  LocalDeviceAuthenticator({LocalAuthentication? localAuth})
    : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  @override
  Future<bool> isSupported() => _localAuth.isDeviceSupported();

  @override
  Future<String> capabilityLabel() async {
    try {
      if (!await _localAuth.isDeviceSupported()) {
        return 'Device authentication unavailable';
      }
      final types = await _localAuth.getAvailableBiometrics();
      if (types.isEmpty) return 'Device PIN, pattern, or password';
      final labels = types.map((type) {
        switch (type) {
          case BiometricType.face:
            return 'Face';
          case BiometricType.fingerprint:
            return 'Fingerprint';
          case BiometricType.strong:
            return 'Strong biometrics';
          case BiometricType.weak:
            return 'Weak biometrics';
          case BiometricType.iris:
            return 'Iris';
        }
      }).toSet();
      return labels.join(', ');
    } catch (_) {
      return 'Device authentication';
    }
  }

  @override
  Future<DeviceAuthOutcome> authenticate({required String reason}) async {
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (ok) return const DeviceAuthOutcome.authenticated();
      return const DeviceAuthOutcome.failed(
        'Authentication was cancelled. LORE stays locked.',
      );
    } on LocalAuthException catch (error) {
      switch (error.code) {
        case LocalAuthExceptionCode.noCredentialsSet:
        case LocalAuthExceptionCode.noBiometricHardware:
        case LocalAuthExceptionCode.noBiometricsEnrolled:
        case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
          return const DeviceAuthOutcome.unavailable(
            'This device has no biometric or screen lock configured, so LORE '
            'cannot ask Android to confirm your identity.',
          );
        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.systemCanceled:
        case LocalAuthExceptionCode.timeout:
          return const DeviceAuthOutcome.failed(
            'Authentication was cancelled. LORE stays locked.',
          );
        case LocalAuthExceptionCode.temporaryLockout:
        case LocalAuthExceptionCode.biometricLockout:
          return const DeviceAuthOutcome.failed(
            'Device authentication is temporarily locked. Try again later or '
            'use your device PIN.',
          );
        case LocalAuthExceptionCode.authInProgress:
          return const DeviceAuthOutcome.failed(
            'An authentication prompt is already open.',
          );
        default:
          return DeviceAuthOutcome.failed(
            error.description ?? 'Device authentication failed.',
          );
      }
    } catch (_) {
      return const DeviceAuthOutcome.failed(
        'Device authentication failed. LORE stays locked.',
      );
    }
  }
}
