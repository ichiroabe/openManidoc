import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/mcp_service.dart';

/// mcp_servers.json の簡易エディタ。
/// - ファイルが無ければ雛形を表示(保存時に作成)
/// - 保存時にJSON構造を検証し、不正なら保存せずエラー表示
/// - 保存するとMCPサーバーは停止され、次回のAI呼び出しで新設定により再起動される
Future<void> showMcpConfigDialog(BuildContext context) async {
  final raw = await McpConfig.readRaw();
  final controller =
      TextEditingController(text: raw ?? McpConfig.template.trim());
  final path = await McpConfig.configPath();
  if (!context.mounted) return;

  String? error;

  void openFolder() {
    final dir = File(path).parent.path;
    if (Platform.isWindows) {
      Process.run('explorer.exe', [dir]);
    } else if (Platform.isMacOS) {
      Process.run('open', [dir]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [dir]);
    }
  }

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(L.t('mcp_editor_title')),
        content: SizedBox(
          width: 680,
          height: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 設定ファイルのフルパス(どこに保存されるか常に見えるように)
              SelectableText(path,
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.outline)),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontFamilyFallback: ['Menlo', 'monospace'],
                      fontSize: 13),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(10),
                  ),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12)),
                ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.folder_open, size: 18),
            label: Text(L.t('mcp_open_folder')),
            onPressed: openFolder,
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L.t('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final text = controller.text;
              final err = McpConfig.validate(text);
              if (err != null) {
                setState(() => error = L.t('mcp_invalid', [err]));
                return;
              }
              await McpConfig.writeRaw(text);
              // 稼働中サーバーを止め、次回のAI呼び出しで新設定により再起動
              McpRegistry.instance.stopAll();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(L.t('mcp_saved'))));
              }
            },
            child: Text(L.t('save')),
          ),
        ],
      ),
    ),
  );
}
