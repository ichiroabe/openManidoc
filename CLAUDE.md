# openManidoc

Flutter 製クロスプラットフォーム（macOS/Windows/Linux）マニュアル作成アプリ。GitHub: github.com/ichiroabe/openManidoc

## リリースは pubspec の version が起点（重要）

リリースは **pubspec 駆動**。`.github/workflows/release.yml` が main への push で `pubspec.yaml` の `version` を読み、対応する `v*` タグが未作成なら自動でタグを切り、DMG/zip/tar をビルドして GitHub Releases にアップロードする。手でタグを打つ必要はない。

- **version を上げずに push した変更はダウンロードに反映されない。** CI は「公開済みバージョン」と判定してスキップする。
- 「リリースして」「◯◯をダウンロードに反映して」等の依頼を受けたら、**pubspec 更新 → `build: vX.Y.Z` コミット → `git push origin main` まで必ず完遂する。** version 更新を省略しない。
- バージョンは 0.0.1 刻み（パッチ +1）。pubspec.yaml の `version:` を上げ、ビルド番号も +1（例 `1.7.3+11` → `1.7.4+12`）。
- タグは CI が push 時点の commit に対して作る。入れたい変更が main に乗ってから push すること。
- 3OS のビルドが全部成功して初めて Release が作られる。1つでも失敗すれば公開されない。
- 手動で `v*` タグを push した場合も従来どおりリリースされる（緊急時の逃げ道）。
- 定型作業なので `/release` スラッシュコマンドを使うのが確実（引数でバージョン指定可、省略時はパッチ自動 +0.0.1）。

## ビルド環境の注意
- Flutter SDK は PATH に無い → `/Users/abeichiro/ai-agent-system/packman/tools/flutter/bin/flutter` を使う。
- ローカル build 時は `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を付ける。
- CI は appflowy_editor 6.2.0 の都合で Flutter 3.38.5 固定。
- 権威 clone は `/Users/abeichiro/ai-agent-system/openManidoc`。`packman/openManidoc` は古い別履歴なので使わない。
