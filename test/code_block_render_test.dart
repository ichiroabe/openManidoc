import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/widgets/code_block_component.dart';
import 'package:open_manidoc/widgets/code_block_markdown.dart';

void main() {
  testWidgets('code block renders its content in the editor', (tester) async {
    const md = '```json\n{\n  "hello": 1\n}\n```';
    final doc = markdownToDocument(md,
        markdownParsers: const [CodeBlockMarkdownParser()]);
    final editorState = EditorState(document: doc);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppFlowyEditor(
            editorState: editorState,
            editable: false,
            blockComponentBuilders: {
              ...standardBlockComponentBuilderMap,
              'code': CodeBlockComponentBuilder(),
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // コード本文と言語ラベルが画面に描画されていること
    expect(find.textContaining('"hello": 1'), findsOneWidget);
    expect(find.text('json'), findsOneWidget);
  });

  testWidgets('edit dialog updates code and markdown output', (tester) async {
    const md = '```text\nold code\n```';
    final doc = markdownToDocument(md,
        markdownParsers: const [CodeBlockMarkdownParser()]);
    final editorState = EditorState(document: doc);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppFlowyEditor(
            editorState: editorState,
            editable: true,
            blockComponentBuilders: {
              ...standardBlockComponentBuilderMap,
              'code': CodeBlockComponentBuilder(),
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ✏️ 編集アイコンをタップ → ダイアログが開く
    // (親にonDoubleTapがあるためシングルタップ確定までダブルタップ猶予300msを要する)
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    // コード本文を書き換えて適用
    final codeField = find.byType(TextField).last;
    await tester.enterText(codeField, 'new code line');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // 画面とMarkdown出力の両方に反映される
    expect(find.textContaining('new code line'), findsOneWidget);
    final back = documentToMarkdown(editorState.document);
    expect(back, contains('```text\nnew code line\n```'));
  });
}
