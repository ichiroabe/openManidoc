import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/app_state.dart';
import 'package:open_manidoc/models/manidoc_project.dart';
import 'package:open_manidoc/services/color_utils.dart';
import 'package:open_manidoc/services/workspace_service.dart';

void main() {
  test('hexとColorの往復ができる', () {
    final color = colorFromHex('#1e88e5');
    expect(color, isNotNull);
    expect(hexFromColor(color!), '#1e88e5');
    // '#'なし・rgb()表記も読める。壊れた値はnull。
    expect(hexFromColor(colorFromHex('ff0000')!), '#ff0000');
    expect(hexFromColor(colorFromHex('rgb(0, 128, 255)')!), '#0080ff');
    expect(colorFromHex(''), isNull);
    expect(colorFromHex('#12345'), isNull);
  });

  test('文字色の自動選択はコントラスト比の高い方を選ぶ', () {
    // 中間の明るさの灰色: 輝度の閾値方式だと白を選んでしまうが、比では黒が上
    final gray = colorFromHex('#808080')!;
    expect(hexFromColor(contrastForegroundFor(gray)), '#000000');
    expect(contrastRatio(const Color(0xFF000000), gray),
        greaterThan(contrastRatio(const Color(0xFFFFFFFF), gray)));
    // 黒と白の比は21:1(定義上の最大)
    expect(
        contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)), 21.0);
  });

  test('背景から出す文字色の候補は本文基準(4.5:1)を満たす', () {
    for (final hex in [
      '#1e88e5',
      '#dcfce7',
      '#111827',
      '#7c3aed', // HSL上は明るいが実際は暗い色(探索の向きを間違えると候補が出ない)
      '#fbbf24',
      '#808080',
    ]) {
      final background = colorFromHex(hex)!;
      final suggestions = suggestForegrounds(background);
      // 白・黒に加えて 同系/補色/低彩度 が出る
      expect(suggestions.length, greaterThanOrEqualTo(4), reason: hex);
      expect(suggestions.where((s) => s.recommended).length, 1, reason: hex);
      for (final s in suggestions) {
        // 白黒は基準として常に出す。それ以外は目標を満たすものだけ。
        if (s.kind == 'white' || s.kind == 'black') continue;
        expect(s.ratio, greaterThanOrEqualTo(kReadableContrast), reason: '$hex ${s.kind}');
      }
      // 推奨は白か黒のうち比が高い方
      final recommended = suggestions.firstWhere((s) => s.recommended);
      expect(hexFromColor(recommended.color),
          hexFromColor(contrastForegroundFor(background)),
          reason: hex);
    }
  });

  test('色が未設定ならJSONに出力しない / 設定すれば往復する', () {
    final plain = ManidocProject(name: '色なし');
    final json = plain.toJson();
    expect(json.containsKey('cardForeColor'), false);
    expect(json.containsKey('cardBackColor'), false);

    final colored = ManidocProject(name: '色あり')
      ..cardForeColor = '#ffffff'
      ..cardBackColor = '#1e88e5';
    final restored = ManidocProject.fromJson(colored.toJson());
    expect(restored.cardForeColor, '#ffffff');
    expect(restored.cardBackColor, '#1e88e5');
  });

  test('本家Manidocに色を剥がされてもミラーから復元される', () async {
    final tmp = await Directory.systemTemp.createTemp('om_card_color');
    final ws = WorkspaceService(tmp.path);
    final project = ManidocProject(name: 'ミラー検証')
      ..cardForeColor = '#ffffff'
      ..cardBackColor = '#1e88e5';
    await ws.saveProject(project);
    await ws.updateCardColors([project]);
    expect(File(ws.cardColorsPath).existsSync(), true);

    // 本家Manidoc(未知フィールドを保持しない)が保存し直した状態を作る
    final file = File(ws.projectFilePath(project.id));
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    raw.remove('cardForeColor');
    raw.remove('cardBackColor');
    await file.writeAsString(jsonEncode(raw));

    final loaded = await ws.loadProjects();
    expect(loaded.length, 1);
    expect(loaded.first.cardForeColor, '#ffffff');
    expect(loaded.first.cardBackColor, '#1e88e5');

    // 既定へ戻すとミラーからも消える(エントリが空になればファイルごと削除)
    loaded.first.cardForeColor = '';
    loaded.first.cardBackColor = '';
    await ws.updateCardColors(loaded);
    expect(File(ws.cardColorsPath).existsSync(), false);

    await tmp.delete(recursive: true);
  });

  test('一括色設定は更新日時を動かさない', () async {
    final tmp = await Directory.systemTemp.createTemp('om_card_color_touch');
    final app = AppState()..workspace = WorkspaceService(tmp.path);
    final ws = app.workspace!;
    final older = DateTime(2026, 1, 1);
    final a = ManidocProject(name: 'A', lastModifiedAt: older);
    final b = ManidocProject(name: 'B', lastModifiedAt: older);
    await ws.saveProject(a, touch: false);
    await ws.saveProject(b, touch: false);

    await app.setProjectsCardColor([a, b], back: '#dcfce7');
    expect(app.projects.length, 2);
    for (final p in app.projects) {
      expect(p.cardBackColor, '#dcfce7');
      expect(p.lastModifiedAt, older, reason: '色変更は本文の更新ではない');
    }

    await tmp.delete(recursive: true);
  });

  test('一括削除はバックアップZIPを作ってから消し、失敗は集計される', () async {
    final tmp = await Directory.systemTemp.createTemp('om_bulk_delete');
    final app = AppState()..workspace = WorkspaceService(tmp.path);
    final ws = app.workspace!;
    final keep = ManidocProject(name: '残す');
    final gone = ManidocProject(name: '消す')..cardBackColor = '#000000';
    await ws.saveProject(keep);
    await ws.saveProject(gone);
    await ws.updateCardColors([gone]);
    // 画像フォルダも一緒に消えることを確認する
    final imagesDir = Directory(ws.imagesDirPath(gone.id));
    await imagesDir.create(recursive: true);
    await File('${imagesDir.path}${Platform.pathSeparator}a.png')
        .writeAsBytes([1, 2, 3]);

    final result = await app.deleteProjects([gone]);
    expect(result.deleted, ['消す']);
    expect(result.failed, isEmpty);
    expect(result.backupDir, isNotNull);
    expect(Directory(result.backupDir!).listSync().length, 1,
        reason: 'ZIPが1件作られている');
    expect(File(ws.projectFilePath(gone.id)).existsSync(), false);
    expect(imagesDir.existsSync(), false);
    expect(File(ws.projectFilePath(keep.id)).existsSync(), true);
    // 削除したプロジェクトのミラーは残さない
    expect(await ws.loadCardColors(), isEmpty);
    expect(app.projects.map((p) => p.name), ['残す']);

    await tmp.delete(recursive: true);
  });
}
