---
description: openManidoc を 0.0.1 刻みでリリース（pubspec更新→build:vXコミット→タグ→タグpushでCIビルド起動）
argument-hint: "[バージョン 例 1.8.0 省略時はパッチ+0.0.1]"
allowed-tools: Bash, Read, Edit
---

openManidoc をリリースする。**タグを打って push するまでが必須**（タグ push が GitHub Actions の release.yml を起動し DMG/zip/tar をビルドする。タグを打たないとダウンロードに反映されない）。

このリポジトリのルート（`git rev-parse --show-toplevel`）で作業する。OS を問わず動くよう、絶対パスは決め打ちしない。

手順（必ず全部やる。途中で止めない）:

1. **同期と確認**
   - `git pull --ff-only origin main`
   - `git status`（作業ツリーがクリーンか。未コミットの変更があれば止めてユーザーに確認）
   - `git log origin/main..HEAD --oneline` が空＝全部push済みであることを確認。リリースに入れたい変更が origin/main に乗っているか確認する。

2. **バージョン決定**
   - 引数 `$1` があればそれを新バージョンにする（例 `1.8.0`）。
   - 無ければ pubspec.yaml の `version:` を読み、**パッチを +0.0.1**、ビルド番号を +1 する（例 `1.7.2+10` → `1.7.3+11`）。
   - 既存タグと衝突しないこと（`git tag` で確認）。

3. **pubspec 更新とコミット**
   - pubspec.yaml の `version:` 行だけを新バージョンに書き換える。
   - `git commit -am "build: vX.Y.Z"`

4. **タグ作成（★ここを絶対に飛ばさない）**
   - `git tag vX.Y.Z`

5. **push（main とタグを両方。タグは別 push が必須）**
   - `git push origin main`
   - `git push origin vX.Y.Z`

6. **CI起動を確認して報告**
   - `curl -s "https://api.github.com/repos/ichiroabe/openManidoc/actions/workflows/release.yml/runs?per_page=1"`（`gh` は未認証でも公開repoなのでAPIで確認可）
   - タグ・コミット・ビルドURL・「ダウンロードに反映される変更」をユーザーに簡潔に報告する。

注意:
- `git push origin main` だけではリリースは起きない。**タグの push が起点**。
- タグは「そのコミットの状態」でビルドされる。入れたい変更が入ったコミットの上でタグを切ること。
- タグをやり直す場合: `git tag -d vX.Y.Z` と `git push origin :vX.Y.Z` で削除してから切り直す。
