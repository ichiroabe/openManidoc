# openManidoc

Flutter 製クロスプラットフォーム（macOS/Windows/Linux）マニュアル作成アプリ。GitHub: github.com/ichiroabe/openManidoc

## リリースは必ずタグを打つこと（重要）

リリースは **タグ駆動**。`.github/workflows/release.yml` が `v*` タグの push をトリガーに DMG/zip/tar をビルドして GitHub Releases にアップロードする。

- **`git push origin main` だけではダウンロードに反映されない。** タグを push して初めてビルドが走る。
- 「リリースして」「◯◯をダウンロードに反映して」等の依頼を受けたら、**pubspec 更新 → `build: vX.Y.Z` コミット → `git tag vX.Y.Z` → `git push origin main && git push origin vX.Y.Z` まで必ず完遂する。** タグ push を省略しない。
- タグは「そのコミットの状態」でビルドされる。入れたい変更が origin/main に乗っていることを確認してからタグを切る。
- バージョンは 0.0.1 刻み（パッチ +1）。pubspec.yaml の `version:` を上げ、ビルド番号も +1（例 `1.7.2+10` → `1.7.3+11`）。
- 定型作業なので `/release` スラッシュコマンドを使うのが確実（引数でバージョン指定可、省略時はパッチ自動 +0.0.1）。

## ビルド環境の注意
- Flutter SDK は PATH に無い → `/Users/abeichiro/ai-agent-system/packman/tools/flutter/bin/flutter` を使う。
- ローカル build 時は `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を付ける。
- CI は appflowy_editor 6.2.0 の都合で Flutter 3.38.5 固定。
- 権威 clone は `/Users/abeichiro/ai-agent-system/openManidoc`。`packman/openManidoc` は古い別履歴なので使わない。
