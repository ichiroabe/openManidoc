# openManidoc

人間とAIエージェントが協調して知識を構築・活用する **Manidoc** のオープンソース版（Flutter製デスクトップアプリ）。

これまでの壁打ちを通じて見えてきた、`openManidoc` の **「いいところ（圧倒的な強みと価値）」** を要約しました。

大きく分けて以下の5つの価値に集約されます。

---

### 1. 「AIと人間の相互ハブ」という独自の設計思想
従来のメモアプリ（N社やO社）は「人間が書き、AIがたまにサポートする」一方通行のツールでした。
`openManidoc` は、**人間とAIが「Markdownツリー」という同じ共通言語を囲み、互いに読み書き・編集し合う「双方向の知的コラボレーションの場（ハブ）」** です。

### 2. 「ローカル完結」がもたらす絶対的な安全性
すべてのデータ（ツリー、本文、画像）がPCローカルで完結するため、外部のクラウドに社外秘データやプライベート情報が漏洩する心配が一切ありません。極めてセキュアなナレッジベースを構築できます。

### 3. Google ドライブで実現する「自律的同期システム」（実証済み）
独自の複雑な同期システムを開発せずとも、ワークスペースをGoogle ドライブ（同期フォルダ）にするだけで、以下のサイクルがシームレスに回り始めます。
* AI（Claude等）がMCP経由で定期的に情報を自動構築（ダッシュボード化）する。
* 人間がデスクトップアプリでいつでも編集・アノテーションを入れる。
* 最新の知識が自動同期され、移動中に **manidocMobile** で朝チェックする。

### 4. ハルシネーション（嘘）を防ぐ「確実な情報アクセス」
一般的なRAG（生成AIによる曖昧な要約検索）とは異なり、Markdownのツリー構造から正確な「全文検索」で一次ソースを確実に引き出します。
**「確定した正確なソースをAIに分析させ、答えを出力させる」** ため、AIのハルシネーション（もっともらしい嘘）を完全に防ぎつつ、社内情報に安全にアクセスできます。

### 5. 「ビューワー」と「構築ツール」の強力な二面性
* **人が見る「ビューワー」**: マークダウン、マインドマップ、画像アノテーション、美しくカスタムできるテーマジェネレータなど、人間が情報を「一瞬で理解する」ための優れたUIを提供します。
* **AIが動く「構築ツール」**: `manidocMCP` を経由して、メール、カレンダー、Web検索などの単純作業や情報収集をAIに自動で行わせ、ツリーを自律的に成長させます。



### 🧠 AIネイティブなローカル知識循環エコシステム
* **openManidoc (デスクトップ)**: 人間が知識を俯瞰（マインドマップ）し、整理・アノテーション（マークダウン、画像枠線注釈、テーマ生成）するための知識構築・閲覧ツール。
* **manidocMCP**: 外部のAIデスクトップ等から、ローカルに蓄積された安全なデータにアクセスするための **MCP（Model Context Protocol）サーバー**。曖昧な検索（RAG）に依存せず、Markdownで構造化されたツリーから直接、確実な全文検索を実行。その**検索結果をAIが分析・整理して出力**するため、ハルシネーション（もっともらしい嘘）を完全に排除しながら、社内専用の確実な情報へ安全かつスマートにアクセスできます。また、AIにデータを直接操作させてナレッジを自律構築することも可能です。
* **manidocMobile (モバイル)**: 構築された最新のナレッジを、現場や移動先など、いつでもどこでも快適に閲覧・活用。

---

## 特徴

- **ツリー形式の目次管理** — 章・節・項をボタン操作 or ドラッグ&ドロップで並べ替え・階層変更
- **Markdown で本文編集** — 装飾ツールバー(太字/斜体/見出し/リスト/リンク/画像/日付)付き、右ペインにリアルタイムプレビュー(編集中の項目へ自動スクロール同期)
- **画像添付・画像編集** — 各項目に画像を紐付け(プロジェクトフォルダへ自動コピー)、画像エディタでの枠線描画(6色)で注釈
- **補足コメント** — 注意書きスタイルで出力される補足欄
- **マインドマップ表示** — ツリー全体をマインドマップで俯瞰
- **検索・一括置換** — プロジェクト内検索、および全項目一括置換。スタート画面では全プロジェクト横断の全文検索
- **タグ管理** — プロジェクトにタグを付けて整理
- **AI エージェント & MCP 連携** — アプリ内でのGemini/ローカルLLMによる文章・画像生成に加え、外部のAIデスクトップから `manidocMCP` を経由してローカル知識を安全に引き出したり、データを操作したりできる連携に対応
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
- 無料・未署名で配布する場合の起動方法:
  Appleの有料デベロッパー登録を行わずに配布（またはzip等で共有）した場合、受け取った側のMacで起動時に「開発元が未確認のため開けません」というセキュリティ警告が表示されます。これを回避するには、ユーザーに以下のいずれかの手順を行ってもらってください。
  - 右クリックから起動する: アプリを右クリック（または二本指タップ）して「開く」を選択し、表示される確認ダイアログで「開く」をクリックする（初回のみ）。
  - コマンドでセキュリティ解除する: ターミナルで以下のコマンドを実行して隔離属性を解除する。
    ```bash
    xattr -cr open_manidoc.app
    ```
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
