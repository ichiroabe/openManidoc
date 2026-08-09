---
description: openManidoc を 0.0.1 刻みでリリース（pubspec更新→build:vXコミット→main push でCIが自動タグ＆リリース）
argument-hint: "[バージョン 例 1.8.0 省略時はパッチ+0.0.1]"
allowed-tools: Bash, Read, Edit
---

openManidoc をリリースする。**リリースの起点は pubspec.yaml の `version`**。main に push すると `.github/workflows/release.yml` が version を読み、対応する `v*` タグが未作成なら自動でタグを切って DMG/zip/tar を Releases に公開する。手でタグを打つ必要はない。

このリポジトリのルート（`git rev-parse --show-toplevel`）で作業する。OS を問わず動くよう、絶対パスは決め打ちしない。

手順（必ず全部やる。途中で止めない）:

1. **同期と確認**
   - `git pull --ff-only origin main`
   - `git status`（作業ツリーがクリーンか。未コミットの変更があれば止めてユーザーに確認）
   - リリースに入れたい変更が main に乗っているか確認する。

2. **バージョン決定**
   - 引数 `$1` があればそれを新バージョンにする（例 `1.8.0`）。
   - 無ければ pubspec.yaml の `version:` を読み、**パッチを +0.0.1**、ビルド番号を +1 する（例 `1.7.3+11` → `1.7.4+12`）。
   - 既存タグと衝突しないこと（`git tag` で確認）。衝突しているとCIがスキップされ、リリースされない。

3. **pubspec 更新とコミット**
   - pubspec.yaml の `version:` 行だけを新バージョンに書き換える。
   - `git commit -am "build: vX.Y.Z"`

4. **push（これが起点）**
   - `git push origin main`

5. **CI起動を確認して報告**
   - `curl -s "https://api.github.com/repos/ichiroabe/openManidoc/actions/workflows/release.yml/runs?per_page=1"`（`gh` は未認証でも公開repoなのでAPIで確認可）
   - タグ・コミット・ビルドURL・「ダウンロードに反映される変更」をユーザーに簡潔に報告する。

注意:
- **pubspec の version を上げ忘れた push はリリースされない。** CI は「そのバージョンは公開済み」と判定してスキップする（Actions のログに notice が出る）。コード変更だけを push した場合はダウンロードに反映されないので、配布したいときは必ず version を上げる。
- タグは CI が push 時点の commit に対して作る。入れたい変更が main に乗ってから push すること。
- 3OS のビルドが全部成功して初めて Release が作られる。1つでも失敗すると公開されない。
- やり直す場合: `git tag -d vX.Y.Z` と `git push origin :vX.Y.Z` でタグを消し、Release も削除してから再 push する。
