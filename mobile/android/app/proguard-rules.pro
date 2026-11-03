# google_mlkit_text_recognition references every script-specific recognizer,
# but the app links only the bundled Latin model. Without these rules R8 fails
# on the Chinese, Devanagari, Japanese and Korean classes that are not
# packaged. No behavior is removed; the unused branches are simply unreachable.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
