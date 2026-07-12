# openManidoc Project Rules

## Windows Build
- Windows環境でビルドまたは `flutter pub get` を実行する際は、`pubspec.yaml` の `dependency_overrides` にある `appflowy_editor`（ローカルパス参照）をコメントアウトすること。
  - macOS側では Sandboxバグ対応のためローカルパスが使われているが、その実体（`third_party/appflowy_editor`）は `.gitignore` されており、Windows側には存在しないため。
