/// This package's release, as `version:` in pubspec.yaml states it.
///
/// `tools/compile_style.sh` stamps a consumer style with the release whose
/// templates built it, and `ScreenLineRenderer.loadStyle` compares the
/// stamp with this. The release automation rewrites both on every release,
/// and a test fails when they disagree.
const String techLinesVersion = '0.3.0';
