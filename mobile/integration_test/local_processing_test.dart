import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'probe_runner.dart';

/// On-device probe for the Phase 3.2 local pipeline.
///
/// Disable Wi-Fi and mobile data before running so a successful OCR run proves
/// the recognition model ships with the APK.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('local processing runs without any network access', (
    tester,
  ) async {
    final report = await runLocalProcessingProbe();
    // ignore: avoid_print
    print(report.summary);
    expect(report.checks, isNotEmpty);
    for (final check in report.checks) {
      expect(check.passed, isTrue, reason: '$check');
    }
  });
}
