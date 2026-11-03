import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

abstract interface class OcrEngine {
  bool get isAvailable;

  Future<String> recognizeFile(String path);

  Future<void> close();
}

class OcrUnavailableException implements Exception {
  const OcrUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OcrProcessingException implements Exception {
  const OcrProcessingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Bundled ML Kit Latin text recognition.
///
/// The Android dependency is `com.google.mlkit:text-recognition`, not the
/// Play-Services-backed variant, so the model ships in the APK and is never
/// downloaded at first use.
class MlKitOcrEngine implements OcrEngine {
  MlKitOcrEngine({TextRecognitionScript script = TextRecognitionScript.latin})
    : _script = script;

  final TextRecognitionScript _script;
  TextRecognizer? _recognizer;

  @override
  bool get isAvailable =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<String> recognizeFile(String path) async {
    if (!isAvailable) {
      throw const OcrUnavailableException(
        'On-device OCR is only available on Android and iOS.',
      );
    }
    final recognizer = _recognizer ??= TextRecognizer(script: _script);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(path),
      );
      return result.text;
    } on PlatformException catch (error) {
      throw OcrProcessingException(
        'On-device OCR failed: ${error.message ?? error.code}.',
      );
    } on OcrProcessingException {
      rethrow;
    } catch (error) {
      throw OcrProcessingException('On-device OCR failed: $error');
    }
  }

  @override
  Future<void> close() async {
    final recognizer = _recognizer;
    _recognizer = null;
    if (recognizer != null) {
      try {
        await recognizer.close();
      } catch (_) {
        // Releasing a recognizer is best-effort during shutdown.
      }
    }
  }
}

class DisabledOcrEngine implements OcrEngine {
  const DisabledOcrEngine();

  @override
  bool get isAvailable => false;

  @override
  Future<String> recognizeFile(String path) {
    throw const OcrUnavailableException(
      'Offline OCR is not available on this platform.',
    );
  }

  @override
  Future<void> close() async {}
}

String normalizeOcrText(String text) {
  return text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .trim();
}
