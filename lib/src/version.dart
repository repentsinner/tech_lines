/// This package's release, as `version:` in pubspec.yaml states it.
///
/// [StyleTemplateException] names it, so a mismatched style says which
/// release's `tools/compile_style.sh` to rebuild it with. The release
/// automation rewrites it on every release, and a test fails when it and
/// pubspec.yaml disagree.
const String techLinesVersion = '0.3.0';
