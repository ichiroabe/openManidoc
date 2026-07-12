# openManidoc

操作マニュアル作成支援ツール **Manidoc** のオープンソース版。
Flutter 製で **Windows / macOS / Linux** に対応するデスクトップアプリです。

スクリーンショットや説明文を階層構造(ツリー)で整理し、目次付きのモダンな
HTML マニュアルとして出力できます。

---

## 特徴

- **ツリー形式の目次管理** — 章・節・項をボタン操作 or ドラッグ&ドロップで並べ替え・階層変更
- **Markdown で本文編集** — 装飾ツールバー(太字/斜体/見出し/リスト/リンク/画像/日付)付き、右ペインにリアルタイムプレビュー(編集中の項目へ自動スクロール同期)
- **画像添付・画像編集** — 各項目に画像を紐付け(プロジェクトフォルダへ自動コピー)、枠線描画(6色)で注釈
- **補足コメント** — 注意書きスタイルで出力される補足欄
- **マインドマップ表示** — ツリー全体をマインドマップで俯瞰
- **検索・一括置換** — プロジェクト内検索、および全項目一括置換。スタート画面では全プロジェクト横断の全文検索
- **タグ管理** — プロジェクトにタグを付けて整理
- **AI エージェント** — Gemini / ローカル LLM(LM Studio・Ollama 等)と連携。会話からマニュアルを生成し **ワンクリックでプロジェクトに取り込み**。Gemini では **Web 検索(grounding)** も利用可
- **インポート** — Markdown / HTML ファイル / Web ページからプロジェクトを生成
- **出力** — HTML 一括出力(ハンバーガー目次・レスポンシブ・ダークモード対応)、Markdown 出力、複数プロジェクトを一覧化する **Web ポータル一括出力**
- **テーマ** — HTML 出力用のテーマ CSS 選択と、色・フォントを指定して CSS を作るテーマジェネレータ
- **音声読み上げ / 画像最適化** — 出力 HTML に読み上げボタンを付与、画像の縮小・再圧縮に対応
- **バックアップ** — プロジェクトを ZIP でバックアップ / 復元
- **日本語 / 英語 UI 切替**
- **API キーの暗号化保存** — Gemini API キーは openManidoc 専用鍵で AES 暗号化して保存(平文では保存しません)
- **旧 Manidoc 互換** — Windows 版 Manidoc のワークスペース(`{projectId}.json` + `{projectId}/images/`)をそのまま開けます

---

## データ構造

```
ワークスペースフォルダ/
├── {projectId}.json      # プロジェクトデータ(ツリー・本文・コメント)
├── {projectId}/
│   └── images/           # 添付画像
├── themes/               # テーマCSS
├── exports/              # HTML / Markdown 出力先
├── backups/              # ZIPバックアップ
└── web_portal_*/         # Web一括出力
```

---

## 必要環境

- **Flutter SDK 3.38 以降**(Dart 3.10 以降) — <https://docs.flutter.dev/get-started/install>
- デスクトップターゲットの有効化(通常はデフォルトで有効):
  ```bash
  flutter config --enable-windows-desktop --enable-macos-desktop --enable-linux-desktop
  ```
- `flutter doctor` を実行し、対象 OS の項目に問題がないことを確認してください。

各 OS で必要なツールチェーン:

| OS | 必要なもの |
|----|-----------|
| **Windows** | Visual Studio 2022(C++「デスクトップ開発」ワークロード) |
| **macOS** | Xcode + コマンドラインツール(`xcode-select --install`)、CocoaPods(`sudo gem install cocoapods`) |
| **Linux** | `clang cmake ninja-build pkg-config libgtk-3-dev`(Debian/Ubuntu の例) |

> クロスコンパイルはできません。**Windows 版は Windows 上で、macOS 版は macOS 上で、Linux 版は Linux 上で**ビルドします。

---

## セットアップ

```bash
git clone <このリポジトリ>
cd openManidoc
flutter pub get
```

## 開発中の実行

```bash
flutter run -d windows   # Windows
flutter run -d macos     # macOS
flutter run -d linux     # Linux
```

実行中に `r` でホットリロード、`R` でホットリスタート、`q` で終了。

## テスト / 静的解析

```bash
flutter analyze
flutter test
```

---

## OS 別ビルド手順

### Windows

```bash
flutter build windows --release
```

- 出力先: `build\windows\x64\runner\Release\`
- 配布時は **このフォルダごと**コピーしてください(`open_manidoc.exe` 単体では動きません。隣接の DLL と `data\` フォルダが必要です)。
- インストーラーを作る場合は [Inno Setup](https://jrsoftware.org/isinfo.php) 等で `Release` フォルダ一式をパッケージ化します。

### macOS

```bash
flutter build macos --release
```

- 出力先: `build/macos/Build/Products/Release/open_manidoc.app`
- 配布(公証)する場合は Apple Developer 証明書で署名・notarize が必要です:
  ```bash
  codesign --deep --force --options runtime \
    --sign "Developer ID Application: <あなたの名前>" \
    build/macos/Build/Products/Release/open_manidoc.app
  # 必要に応じて xcrun notarytool で公証
  ```
- `.dmg` 化は `hdiutil` や `create-dmg` を利用します。

### Linux

```bash
flutter build linux --release
```

- 出力先: `build/linux/x64/release/bundle/`
- 実行ファイルは `bundle/open_manidoc`。配布時は `bundle` フォルダ一式が必要です。
- パッケージ化の例:
  - **AppImage** — `appimagetool` で `bundle` を包む
  - **.deb** — `bundle` を `/opt/open_manidoc/` に配置する control ファイルを作成
  - **Flatpak / Snap** — 各マニフェストで `bundle` を同梱

> 32bit や arm64 が必要な場合は、それぞれのアーキテクチャのマシン上で同じコマンドを実行してください。

---

## AI 連携の設定

スタート画面の **⚙ 設定** から:

- **Gemini**: API キーとモデル名(既定 `gemini-2.5-flash`)を設定。Web 検索(grounding)が使えます。
- **ローカル LLM**: OpenAI 互換エンドポイントを設定
  - LM Studio: `http://localhost:1234/v1`(モデル名は空で可)
  - Ollama: `http://<ホスト>:11434/v1`(モデル名の指定が必要)

AI エージェント画面で会話し、回答の下に出る **「＋ この内容でプロジェクト作成」** ボタンで新規プロジェクトに取り込めます。**MD モード**を ON にすると、マニュアル向けの Markdown 形式で出力させて取り込みやすくなります。

> API キーは openManidoc 専用鍵で暗号化して保存されます(旧 Manidoc とは別の鍵)。

---

## ライセンス

**GNU General Public License v3.0 (GPLv3)**

```
openManidoc — 操作マニュアル作成支援ツール
Copyright (C) 2026 Ichiro Abe

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
```

本ソフトウェアを改変して再配布する場合、その改変版も GPLv3 の下でソースコードを
公開する必要があります(コピーレフト)。ライセンス全文は [LICENSE](LICENSE) を参照してください。
