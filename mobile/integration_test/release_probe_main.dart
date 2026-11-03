import 'dart:async';

import 'package:flutter/material.dart';

import 'probe_runner.dart';

/// Release-mode entrypoint for the Phase 3.2 Android probe.
///
/// Build with
/// `flutter build apk --release --target=integration_test/release_probe_main.dart`,
/// disable networking, launch the activity and read the `LORE_PROBE` lines
/// from logcat. The regular app entrypoint is untouched.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ProbeApp());
  unawaited(_run());
}

Future<void> _run() async {
  try {
    final report = await runLocalProcessingProbe(
      log: (line) => debugPrint(line),
    );
    debugPrint(report.summary);
  } catch (error, stackTrace) {
    debugPrint('LORE_PROBE_DONE FAIL uncaught=$error');
    debugPrint(stackTrace.toString());
  }
}

class _ProbeApp extends StatelessWidget {
  const _ProbeApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('LORE local processing probe'),
        ),
      ),
    );
  }
}
