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
}
