import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';

import '../app_state.dart';
import '../l10n/strings.dart';
import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';
import '../services/plain_text.dart';
import '../services/voicevox_service.dart';

/// プロジェクト選択の「没入ビュー」。
/// 球の中心視点で、プロジェクトのタイルが本棚状にまわりを囲む。
/// - 放置中はゆっくり自転(速度はバーで調整)
/// - ドラッグで上下左右に見回す / ポインタが乗っている間は自転停止
/// - タイルにホバーでプロジェクト名の全体をツールチップ表示
/// - タイルをタップでそのプロジェクトを開く
/// - タグ / 期間(N日以内) / 並び順 / 名前検索で絞り込み
/// - 最終更新日で「同心円の層(N圏)」に配置: 近い圏ほど最近更新で大きい
class ImmersiveProjectView extends StatefulWidget {
  final AppState app;
  final List<ManidocProject> projects;
  final void Function(ManidocProject project) onOpen;
  final void Function(ManidocProject project, String nodeId) onOpenNode;

  const ImmersiveProjectView({
    super.key,
    required this.app,
    required this.projects,
    required this.onOpen,
    required this.onOpenNode,
  });

  @override
  State<ImmersiveProjectView> createState() => _ImmersiveProjectViewState();
}

class _ImmersiveProjectViewState extends State<ImmersiveProjectView>
    with SingleTickerProviderStateMixin {
  double viewAz = 0;
  double viewEl = 0;

  // 投影・タイル
  static const double focal = 520;  // 投影の広がり(小さいほど広角)
  static const double baseW = 150;  // タイル基準サイズ
  static const double baseH = 110;
  static const double zNear = 0.32; // これより端(約±71°)は描かない
  static const double tilt = 0.55;  // 面の傾き強さ(0=常に正面/1=球面追従)

  // 自転
  static const Duration idle = Duration(milliseconds: 1400);
  double _spinSpeed = 0.12; // ラジアン/秒(バーで調整)
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  DateTime _lastInteract =
      DateTime.now().subtract(const Duration(seconds: 10));
  Offset? _pointer;       // シーン内のカーソル位置(なければnull)
  bool _overTile = false; // カーソルがいずれかのタイルに重なっているか

  // 絞り込み・並べ替え・圏数
  String _tag = '';        // '' = すべて
  int _periodDays = 0;     // 0 = 全期間
  String _sort = 'LastModifiedAt';
  String _search = '';
  int _rings = 3;          // 同心円の圏数
  final _searchCtl = TextEditingController();

  // ホバーメニュー
  String? _hoverId;        // カーソル下のプロジェクトID(最前面)
  bool _overMenu = false;  // カーソルがメニュー上にあるか

  // 読み上げセッション(VOICEVOX)。2プレイヤーのダブルバッファで境界を無継ぎ目に。
  final List<AudioPlayer> _players = [AudioPlayer(), AudioPlayer()];
  final List<StreamSubscription<void>> _subs = [];
  int _active = 0; // 再生中のプレイヤー
  bool _reading = false;
  List<_Chunk> _chunks = [];   // 文単位のチャンク
  int _chunkIndex = 0;
  List<ManidocNode> _readNodes = []; // プロジェクトの全ノード(輪表示用)
  ManidocProject? _readProject;
  String? _readMessage; // 未起動/エラー等の通知(読み上げ中でない時に表示)
  String? _readSpeakerName; // クレジット表示用の話者(キャラ)名
  String? _curPath;   // active が再生中のファイル
  String? _nextPath;  // inactive に setSource 済みの次ファイル
  int _nextIndex = -1; // _nextPath が対応するチャンク番号

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    // 両プレイヤーの完了を監視。完了したのが現 active なら次へ進む。
    for (var i = 0; i < 2; i++) {
      final idx = i;
      _subs.add(_players[i].onPlayerComplete.listen((_) {
        if (idx == _active) _advance();
      }));
    }
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt > 0 &&
        _spinSpeed > 0 &&
        !_overTile &&
        !_reading && // 読み上げ中は背景の自転を止める(隠れた二重描画を避ける)
        DateTime.now().difference(_lastInteract) >= idle) {
      setState(() => viewAz = (viewAz + _spinSpeed * dt) % (2 * math.pi));
    }
  }

  void _touch() => _lastInteract = DateTime.now();

  @override
  void dispose() {
    _ticker.dispose();
    _searchCtl.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    for (final p in _players) {
      p.dispose();
    }
    super.dispose();
  }

  // ---------------- 読み上げ(VOICEVOX) ----------------

  // ノード1件の読み上げテキスト(タイトル＋本文＋コメント)
  String _nodeText(ManidocNode n) {
    final parts = <String>[];
    if (n.title.trim().isNotEmpty) parts.add(n.title.trim());
    final body = markdownToPlain(n.article);
    if (body.isNotEmpty) parts.add(body);
    final comment = markdownToPlain(n.comment);
    if (comment.isNotEmpty) parts.add(comment);
    return parts.join('。 ');
  }

  // 本文を文単位のチャンクに分割(短すぎる断片は結合)。末尾詰まり対策。
  List<String> _sentences(String text) {
    final parts = text.split(RegExp(r'(?<=[。．！？!?\n])'));
    final out = <String>[];
    final buf = StringBuffer();
    for (final part in parts) {
      final t = part.trim();
      if (t.isEmpty) continue;
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(t);
      if (buf.length >= 40 || RegExp(r'[。．！？!?]$').hasMatch(t)) {
        out.add(buf.toString());
        buf.clear();
      }
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out.isEmpty ? [text] : out;
  }

  // 1チャンクを合成して一時WAVに書き出しパスを返す(失敗時null)。
  Future<String?> _synthToFile(String text) async {
    final s = widget.app.settings;
    final svc = VoicevoxService(s.voicevoxEndpoint);
    try {
      final wav = await svc.synthesize(text, s.voicevoxSpeaker,
          speed: s.voicevoxSpeed);
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}${Platform.pathSeparator}'
          'vv_${DateTime.now().microsecondsSinceEpoch}.wav');
      await f.writeAsBytes(wav);
      return f.path;
    } catch (_) {
      return null;
    }
  }

  void _safeDelete(String? path) {
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  // クラッシュ/中断で残った一時WAV(vv_*.wav)を掃除
  Future<void> _sweepTempWavs() async {
    try {
      final dir = await getTemporaryDirectory();
      for (final f in dir.listSync()) {
        if (f is File &&
            f.uri.pathSegments.last.startsWith('vv_') &&
            f.path.endsWith('.wav')) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> _startReading(ManidocProject p) async {
    _touch();
    setState(() {
      _hoverId = null;
      _overMenu = false;
    });
    unawaited(_sweepTempWavs()); // 残った一時WAVを掃除
    final svc = VoicevoxService(widget.app.settings.voicevoxEndpoint);
    if (!await svc.isAvailable()) {
      if (mounted) setState(() => _readMessage = L.t('vv_unavailable'));
      return;
    }
    // クレジット用に話者(キャラ)名を解決(best-effort)
    try {
      final sp = await svc.speakers();
      final match =
          sp.where((e) => e.id == widget.app.settings.voicevoxSpeaker);
      _readSpeakerName =
          match.isNotEmpty ? match.first.name.split(' / ').first : null;
    } catch (_) {
      _readSpeakerName = null;
    }
    final nodes = <ManidocNode>[];
    void walk(List<ManidocNode> ns) {
      for (final n in ns) {
        if (_nodeText(n).trim().isNotEmpty) nodes.add(n);
        walk(n.children);
      }
    }

    walk(p.rootNodes);
    if (nodes.isEmpty) {
      if (mounted) setState(() => _readMessage = L.t('vv_no_text'));
      return;
    }
    final chunks = <_Chunk>[];
    for (var ni = 0; ni < nodes.length; ni++) {
      for (final s in _sentences(_nodeText(nodes[ni]))) {
        chunks.add(_Chunk(nodes[ni], ni, nodes.length, s));
      }
    }
    setState(() {
      _reading = true;
      _readProject = p;
      _readNodes = nodes;
      _chunks = chunks;
      _chunkIndex = 0;
      _readMessage = null;
      _active = 0;
      _curPath = null;
      _nextPath = null;
      _nextIndex = -1;
    });
    _playFirst();
  }

  // 最初のチャンクを active で再生し、次を inactive へ先読みロード
  Future<void> _playFirst() async {
    final path = await _synthToFile(_chunks[0].text);
    if (!_reading || !mounted) {
      _safeDelete(path);
      return;
    }
    if (path == null) {
      _advance(); // 合成失敗は飛ばす
      return;
    }
    _curPath = path;
    await _players[_active].play(DeviceFileSource(path));
    _preload(1);
  }

  // 次チャンクを inactive プレイヤーへ合成＆ロード(境界で即 resume できるように)
  Future<void> _preload(int index) async {
    if (!_reading || index >= _chunks.length) {
      _nextPath = null;
      _nextIndex = -1;
      return;
    }
    final path = await _synthToFile(_chunks[index].text);
    if (!_reading || !mounted) {
      _safeDelete(path);
      return;
    }
    if (path == null) {
      _nextPath = null;
      _nextIndex = -1;
      return;
    }
    try {
      await _players[1 - _active].setSource(DeviceFileSource(path));
      _nextPath = path;
      _nextIndex = index;
    } catch (_) {
      _safeDelete(path);
      _nextPath = null;
      _nextIndex = -1;
    }
  }

  void _advance() {
    if (!_reading) return;
    final target = _chunkIndex + 1;
    if (target >= _chunks.length) {
      _stopReading();
      return;
    }
    _safeDelete(_curPath);
    _curPath = null;
    if (_nextPath != null && _nextIndex == target) {
      // ロード済みの inactive へ切替 → 即 resume(継ぎ目ゼロ)
      _active = 1 - _active;
      _chunkIndex = target;
      _curPath = _nextPath;
      _nextPath = null;
      _nextIndex = -1;
      setState(() {}); // 中央の画像/タイトル・輪のハイライト更新
      _players[_active].resume();
      _preload(target + 1);
    } else {
      _playNow(target); // 先読み未完 → その場で合成再生(フォールバック)
    }
  }

  Future<void> _playNow(int index) async {
    if (!_reading) return;
    _active = 1 - _active;
    _chunkIndex = index;
    setState(() {});
    final path = await _synthToFile(_chunks[index].text);
    if (!_reading || !mounted) {
      _safeDelete(path);
      return;
    }
    if (path == null) {
      _advance();
      return;
    }
    _curPath = path;
    await _players[_active].stop();
    await _players[_active].play(DeviceFileSource(path));
    _preload(index + 1);
  }

  Future<void> _stopReading() async {
    for (final p in _players) {
      await p.stop();
    }
    _safeDelete(_curPath);
    _curPath = null;
    _safeDelete(_nextPath);
    _nextPath = null;
    _nextIndex = -1;
    if (mounted) {
      setState(() {
        _reading = false;
        _chunks = [];
        _readNodes = [];
        _readProject = null;
        _chunkIndex = 0;
      });
    }
  }

  int _countNodes(List<ManidocNode> nodes) =>
      nodes.fold(0, (sum, n) => sum + 1 + _countNodes(n.children));

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  // プロジェクトIDから決定的に色相を作る
  Color _colorFor(ManidocProject p) {
    var h = 0;
    for (final c in p.id.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.42, 0.52).toColor();
  }

  // 全プロジェクトから重複なしのタグ一覧(絞り込みUI用に安定)
  List<String> _allTags() {
    final set = <String>{};
    for (final p in widget.projects) {
      if (p.tag.isNotEmpty) set.add(p.tag);
    }
    final list = set.toList()..sort();
    return list;
  }

  // 絞り込み+並べ替え後の表示対象
  List<ManidocProject> _visible() {
    final now = DateTime.now();
    final q = _search.toLowerCase();
    final list = widget.projects.where((p) {
      if (_tag.isNotEmpty && p.tag != _tag) return false;
      if (_periodDays > 0 &&
          now.difference(p.lastModifiedAt).inDays > _periodDays) {
        return false;
      }
      if (q.isNotEmpty && !p.name.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
    list.sort((a, b) {
      switch (_sort) {
        case 'CreatedAt':
          return b.createdAt.compareTo(a.createdAt);
        case 'Name':
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        default:
          return b.lastModifiedAt.compareTo(a.lastModifiedAt);
      }
    });
    return list;
  }

  // 最終更新日の新しい順ランクで、各プロジェクトを 0..N-1 の圏に割り当てる
  Map<String, int> _ringOf(List<ManidocProject> visible) {
    final rings = math.max(1, _rings);
    final byDate = [...visible]
      ..sort((a, b) => b.lastModifiedAt.compareTo(a.lastModifiedAt));
    final n = byDate.length;
    final map = <String, int>{};
    for (var i = 0; i < n; i++) {
      final ring = n <= 1 ? 0 : (i * rings) ~/ n;
      map[byDate[i].id] = ring.clamp(0, rings - 1);
    }
    return map;
  }

  // 圏ごとの大きさ倍率(近い圏=大きい)
  double _ringScale(int ring) =>
      _rings <= 1 ? 1.0 : _lerp(1.15, 0.64, ring / (_rings - 1));

  // 圏ごとの明るさ(近い圏=明るい)
  double _ringBright(int ring) =>
      _rings <= 1 ? 1.0 : _lerp(1.0, 0.6, ring / (_rings - 1));

  // n個のタイルを球面(段×列)に配置する角度。phaseで圏ごとに回してシェルを重ねない。
  // 段ごとのタイル数をラウンドロビンで均等化し、上下対称に散らす
  // (下から詰めると最下段だけ満杯になり下部に偏るため)。
  List<({double az, double el})> _layout(int n, double phase) {
    const rowGap = 0.5;
    final rows = n <= 4
        ? 1
        : n <= 12
            ? 2
            : n <= 24
                ? 3
                : 4;
    // 各タイルを段へラウンドロビンで割り当て → 段ごとのタイル数が揃う
    final rowOf = List<int>.generate(n, (i) => i % rows);
    final perRow = List<int>.filled(rows, 0);
    for (final r in rowOf) {
      perRow[r]++;
    }
    final placedInRow = List<int>.filled(rows, 0);
    final out = <({double az, double el})>[];
    for (var i = 0; i < n; i++) {
      final r = rowOf[i];
      final cnt = perRow[r];
      final k = placedInRow[r]++;
      final el = (r - (rows - 1) / 2) * rowGap;
      final az = cnt <= 1
          ? phase
          : k * (2 * math.pi / cnt) + (r.isOdd ? math.pi / cnt : 0) + phase;
      out.add((az: az, el: el));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.9,
          colors: [Color(0xFF1C1E28), Color(0xFF0B0C10)],
        ),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              _filterBar(context),
              // 読み上げ中は背景タイルを描かない(隠れているのに毎フレーム
              // 描く二重描画=GPU負荷/VRAM消費を避ける)
              Expanded(
                child: (_reading || _readMessage != null)
                    ? const SizedBox.expand()
                    : _scene(context),
              ),
            ],
          ),
          if (_reading || _readMessage != null) _readOverlay(context),
        ],
      ),
    );
  }

  Widget _scene(BuildContext context) {
    final visible = _visible();
    if (visible.isEmpty) {
      return Center(
        child: Text(L.t('immersive_empty'),
            style: const TextStyle(color: Colors.white54)),
      );
    }
    final ringOf = _ringOf(visible);
    // 圏ごとに配置(各圏が自分のシェルを持つ)
    final byRing = <int, List<ManidocProject>>{};
    for (final p in visible) {
      (byRing[ringOf[p.id]!] ??= []).add(p);
    }
    final entries = <_Entry>[];
    for (final e in byRing.entries) {
      final layout = _layout(e.value.length, e.key * 0.4);
      for (var i = 0; i < e.value.length; i++) {
        entries.add(_Entry(e.value[i], layout[i].az, layout[i].el, e.key));
      }
    }

    return MouseRegion(
      onHover: (e) => setState(() => _pointer = e.localPosition),
      onExit: (_) => setState(() => _pointer = null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _touch(),
        onPanUpdate: (d) => setState(() {
          _touch();
          viewAz -= d.delta.dx * 0.004;
          viewEl = (viewEl + d.delta.dy * 0.004).clamp(-1.1, 1.1);
        }),
        onPanEnd: (_) => _touch(),
        child: LayoutBuilder(builder: (context, c) {
          final cx = c.maxWidth / 2;
          final cy = c.maxHeight / 2;

          final placed = <_Placed>[];
          for (final entry in entries) {
            var a = entry.az - viewAz;
            a = math.atan2(math.sin(a), math.cos(a)); // [-π,π]
            final el = entry.el - viewEl;

            final x = math.cos(el) * math.sin(a);
            final y = math.sin(el);
            final z = math.cos(el) * math.cos(a);
            if (z < zNear) continue; // 視野外

            final sx = cx + focal * x / z;
            final sy = cy - focal * y / z;
            final depth = ((z - zNear) / (1 - zNear)).clamp(0.0, 1.0);
            placed.add(_Placed(entry.project, entry.ring, sx, sy, a, el, z, depth));
          }
          // 描画順: 遠い圏を先に(大きい圏index先)→圏内は端(小z)を先に→最後にindex
          placed.sort((p, q) {
            if (p.ring != q.ring) return q.ring.compareTo(p.ring);
            final r = p.z.compareTo(q.z);
            return r != 0 ? r : p.project.id.compareTo(q.project.id);
          });

          // カーソル下の最前面タイルを判定(メニュー表示と自転停止に使う)
          final hover = _pointer == null ? null : _hitTop(placed, _pointer!);
          _overTile = hover != null || _overMenu;
          if (hover != null) {
            _hoverId = hover.project.id;
          } else if (!_overMenu) {
            _hoverId = null;
          }
          // メニュー対象(hoverが外れても_overMenu中はIDで探して維持)
          _Placed? menuFor = hover;
          if (menuFor == null && _hoverId != null) {
            for (final t in placed) {
              if (t.project.id == _hoverId) {
                menuFor = t;
                break;
              }
            }
          }

          return Stack(
            children: [
              for (final t in placed) _tile(context, t),
              if (menuFor != null)
                _hoverMenu(context, menuFor, c.maxWidth, c.maxHeight),
              Positioned(
                left: 0, right: 0, bottom: 16,
                child: Text(L.t('immersive_hint'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            ],
          );
        }),
      ),
    );
  }

  // カーソル下の最前面(最後に描かれた=手前)のタイルを返す
  _Placed? _hitTop(List<_Placed> placed, Offset p) {
    for (var i = placed.length - 1; i >= 0; i--) {
      final t = placed[i];
      final s = (0.82 + 0.18 * t.depth) * _ringScale(t.ring);
      final hw = baseW * s / 2;
      final hh = baseH * s / 2;
      if ((p.dx - t.sx).abs() <= hw && (p.dy - t.sy).abs() <= hh) return t;
    }
    return null;
  }

  // タイル上に重ねて出すホバーメニュー(フル名＋開く＋内容の確認)
  Widget _hoverMenu(BuildContext context, _Placed t, double maxW, double maxH) {
    const mw = 240.0;
    const mh = 120.0;
    final left =
        (t.sx - mw / 2).clamp(8.0, math.max(8.0, maxW - mw - 8)).toDouble();
    final top =
        (t.sy - mh / 2).clamp(8.0, math.max(8.0, maxH - mh - 8)).toDouble();
    final p = t.project;
    return Positioned(
      left: left,
      top: top,
      width: mw,
      child: MouseRegion(
        onEnter: (_) => setState(() => _overMenu = true),
        onExit: (_) => setState(() => _overMenu = false),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xF223252E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 18,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => widget.onOpen(p),
                        icon: const Icon(Icons.open_in_new, size: 15),
                        label: Text(L.t('vv_open')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _startReading(p),
                        icon: const Icon(Icons.volume_up, size: 15),
                        label: Text(L.t('vv_read')),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, _Placed t) {
    // 拡大縮小は Transform 側で行い、カードは常に baseW×baseH で
    // レイアウトする(箱を縮めると中身がはみ出すため)。
    final s = (0.82 + 0.18 * t.depth) * _ringScale(t.ring);
    final shade = (0.55 + 0.45 * t.depth) * _ringBright(t.ring);
    final col = Color.lerp(Colors.black, _colorFor(t.project), shade)!;
    final opacity = t.depth < 0.12 ? (t.depth / 0.12) : 1.0;

    final m = Matrix4.identity()
      ..setEntry(3, 2, 0.0011)
      ..rotateY(-t.a * tilt)
      ..rotateX(t.el * tilt)
      ..scaleByDouble(s, s, 1, 1);

    // Opacityウィジェット(=saveLayer/専用VRAM消費)は使わず、alphaを色に畳む。
    return Positioned(
      left: t.sx - baseW / 2,
      top: t.sy - baseH / 2,
      width: baseW,
      height: baseH,
      child: Transform(
        alignment: Alignment.center,
        transform: m,
        child: GestureDetector(
          onTap: () {
            _touch();
            widget.onOpen(t.project);
          },
          child: _Card(
            title: t.project.name,
            nodeCount: _countNodes(t.project.rootNodes),
            color: col,
            alpha: opacity,
          ),
        ),
      ),
    );
  }

  // ---------------- 読み上げオーバーレイ ----------------

  Widget _readOverlay(BuildContext context) {
    final size = MediaQuery.of(context).size;
    Widget body;
    if (!_reading) {
      // 未起動/本文なし等の通知
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, color: Colors.white70, size: 30),
          const SizedBox(height: 14),
          Text(_readMessage ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => setState(() => _readMessage = null),
            child: Text(L.t('close')),
          ),
        ],
      );
    } else {
      final chunk =
          _chunkIndex < _chunks.length ? _chunks[_chunkIndex] : null;
      final node = chunk?.node;
      final proj = _readProject;
      String? imgPath;
      if (node != null && proj != null && node.imagePath.isNotEmpty) {
        final abs =
            widget.app.workspace?.resolveImagePath(proj.id, node.imagePath);
        if (abs != null && File(abs).existsSync()) imgPath = abs;
      }
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SaturnReadingView(
            nodes: _readNodes,
            currentId: node?.id ?? '',
            currentTitle: node?.title ?? '',
            imagePath: imgPath,
            fieldW: size.width,
            fieldH: size.height,
            maxImageH: size.height * 0.34,
            maxImageW: size.width * 0.42,
            onOpenNode: (nodeId) {
              final project = proj;
              if (project == null) return;
              _stopReading();
              widget.onOpenNode(project, nodeId);
            },
          ),
          const SizedBox(height: 10),
          Text('${(chunk?.nodeIndex ?? 0) + 1} / ${chunk?.nodeTotal ?? 0}',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _stopReading,
            icon: const Icon(Icons.stop, size: 18),
            label: Text(L.t('vv_stop')),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          ),
          const SizedBox(height: 14),
          Text(
              (_readSpeakerName != null && _readSpeakerName!.isNotEmpty)
                  ? 'VOICEVOX:${_readSpeakerName!}'
                  : 'Powered by VOICEVOX',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      );
    }
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.82),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: body,
      ),
    );
  }

  // ---------------- フィルターバー ----------------

  Widget _filterBar(BuildContext context) {
    final tags = _allTags();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.black.withValues(alpha: 0.28),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _searchField(),
          if (tags.isNotEmpty) _tagDropdown(tags),
          _periodDropdown(),
          _sortDropdown(),
          _ringsDropdown(),
          _spinControl(),
        ],
      ),
    );
  }

  Widget _labeled(String label, Widget child) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(width: 6),
        child,
      ],
    );
  }

  DropdownMenuItem<T> _item<T>(T value, String label) => DropdownMenuItem<T>(
        value: value,
        child: Text(label, style: const TextStyle(fontSize: 13)),
      );

  Widget _dropdown<T>(T value, List<DropdownMenuItem<T>> items,
      ValueChanged<T?> onChanged) {
    return DropdownButton<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      isDense: true,
      dropdownColor: const Color(0xFF23252E),
      iconEnabledColor: Colors.white70,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      underline: const SizedBox.shrink(),
    );
  }

  Widget _searchField() {
    return SizedBox(
      width: 180,
      child: TextField(
        controller: _searchCtl,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          isDense: true,
          hintText: L.t('im_search'),
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
          prefixIcon: const Icon(Icons.search, size: 16, color: Colors.white54),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 28, minHeight: 28),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.08),
          contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          suffixIcon: _search.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 14, color: Colors.white54),
                  onPressed: () {
                    _searchCtl.clear();
                    setState(() => _search = '');
                  },
                ),
        ),
        onChanged: (v) => setState(() => _search = v),
      ),
    );
  }

  Widget _tagDropdown(List<String> tags) {
    return _labeled(
      L.t('im_tag'),
      _dropdown<String>(
        _tag,
        [
          _item('', L.t('im_all')),
          for (final t in tags) _item(t, t),
        ],
        (v) => setState(() => _tag = v ?? ''),
      ),
    );
  }

  Widget _periodDropdown() {
    return _labeled(
      L.t('im_period'),
      _dropdown<int>(
        _periodDays,
        [
          _item(0, L.t('im_period_all')),
          _item(7, L.t('im_days', [7])),
          _item(30, L.t('im_days', [30])),
          _item(90, L.t('im_days', [90])),
          _item(365, L.t('im_days', [365])),
        ],
        (v) => setState(() => _periodDays = v ?? 0),
      ),
    );
  }

  Widget _sortDropdown() {
    return _labeled(
      L.t('im_sort'),
      _dropdown<String>(
        _sort,
        [
          _item('LastModifiedAt', L.t('sort_modified')),
          _item('CreatedAt', L.t('sort_created')),
          _item('Name', L.t('sort_name')),
        ],
        (v) => setState(() => _sort = v ?? 'LastModifiedAt'),
      ),
    );
  }

  Widget _ringsDropdown() {
    return _labeled(
      L.t('im_rings'),
      _dropdown<int>(
        _rings,
        [for (var n = 1; n <= 5; n++) _item(n, L.t('im_rings_n', [n]))],
        (v) => setState(() => _rings = v ?? 3),
      ),
    );
  }

  Widget _spinControl() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.threesixty, size: 16, color: Colors.white60),
        const SizedBox(width: 4),
        Text(L.t('im_spin'),
            style: const TextStyle(color: Colors.white60, fontSize: 12)),
        SizedBox(
          width: 120,
          child: Slider(
            value: _spinSpeed,
            min: 0,
            max: 0.4,
            onChanged: (v) => setState(() => _spinSpeed = v),
          ),
        ),
      ],
    );
  }
}

// 読み上げ中の演出: 中央に「読み上げ中ノード」、そのまわりを
// プロジェクトの全ノードの題名が土星の輪のように楕円軌道で回る。
// 手前=大きく明るく、奥=小さく暗く、惑星の裏側(輪の奥半分)は中心に隠れる。
// 現在ノードは色付き・強調。各題名をタップでそのノードへジャンプ。
class _SaturnReadingView extends StatefulWidget {
  final List<ManidocNode> nodes; // プロジェクトの全ノード(読み上げ対象)
  final String currentId;        // 読み上げ中ノードID
  final String currentTitle;
  final String? imagePath;       // 中心(読み上げ中ノード)の画像
  final double fieldW;           // 描画に使える画面幅
  final double fieldH;
  final double maxImageH;
  final double maxImageW;
  final void Function(String nodeId) onOpenNode;
  const _SaturnReadingView({
    required this.nodes,
    required this.currentId,
    required this.currentTitle,
    required this.imagePath,
    required this.fieldW,
    required this.fieldH,
    required this.maxImageH,
    required this.maxImageW,
    required this.onOpenNode,
  });

  @override
  State<_SaturnReadingView> createState() => _SaturnReadingViewState();
}

class _SaturnReadingViewState extends State<_SaturnReadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 30))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  String _short(String t) {
    final s = t.trim().replaceAll('\n', ' ');
    return s.runes.length <= 10
        ? s
        : '${String.fromCharCodes(s.runes.take(10))}…';
  }

  Widget _label(ManidocNode node, double x, double y, double s) {
    final depth = s * 0.5 + 0.5; // 0=奥 1=手前
    final isCur = node.id == widget.currentId;
    final scale = (0.6 + 0.5 * depth) * (isCur ? 1.35 : 1.0);
    var opacity = 0.22 + 0.78 * depth;
    if (isCur) opacity = math.max(opacity, 0.95);
    return Positioned(
      left: x,
      top: y,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => widget.onOpenNode(node.id),
            child: Tooltip(
              message: node.title,
              // Opacityウィジェットは使わず、alphaを文字色に畳む(saveLayer回避)
              child: Transform.scale(
                scale: scale,
                child: Text(
                  _short(node.title),
                  style: TextStyle(
                    color: (isCur ? const Color(0xFFFFC857) : Colors.white)
                        .withValues(alpha: opacity),
                    fontSize: 14,
                    fontWeight: isCur ? FontWeight.w800 : FontWeight.w600,
                    shadows: const [
                      Shadow(color: Colors.black87, blurRadius: 6)
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nodes = widget.nodes;
    final n = nodes.length;

    // 画面幅を使って大きめに。ノード数で輪の本数を決める(1輪≈10, 最大6本)
    final boxW = math.min(widget.fieldW * 0.92, 1200.0);
    const flat = 0.30; // 輪の平たさ(縦/横)
    final aOuter = boxW / 2 - 80;
    final bOuter = aOuter * flat;
    final rings = (n / 10).ceil().clamp(1, 6);
    final aInner = aOuter * (rings == 1 ? 0.7 : 0.42);
    double aFor(int r) =>
        rings == 1 ? aInner : _lerp(aInner, aOuter, r / (rings - 1));

    final planetMaxH = math.min(widget.maxImageH, bOuter * 1.7);
    final boxH = math.max(bOuter * 2 + 100, planetMaxH + 48);

    // round-robinで各輪へ均等割り当て
    final ringMembers = List.generate(rings, (_) => <int>[]);
    for (var i = 0; i < n; i++) {
      ringMembers[i % rings].add(i);
    }

    final Widget planet = widget.imagePath != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(File(widget.imagePath!), fit: BoxFit.contain),
          )
        : Container(
            padding: const EdgeInsets.all(14),
            alignment: Alignment.center,
            child: Text(
              widget.currentTitle,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700),
            ),
          );

    // ポインタが輪の領域にある間は回転を止める(題名を狙ってクリックしやすく)
    return MouseRegion(
      onEnter: (_) => _c.stop(),
      onExit: (_) {
        if (mounted && !_c.isAnimating) _c.repeat();
      },
      child: SizedBox(
      width: boxW,
      height: boxH,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final back = <Widget>[];
          final front = <Widget>[];
          for (var r = 0; r < rings; r++) {
            final members = ringMembers[r];
            final cnt = members.length;
            if (cnt == 0) continue;
            final ar = aFor(r);
            final br = ar * flat;
            // 輪ごとに速度と位相をずらしてパララックス
            final spin = _c.value * 2 * math.pi * (1 + r * 0.10) + r * 0.6;
            for (var k = 0; k < cnt; k++) {
              final node = nodes[members[k]];
              final ang = (k / cnt) * 2 * math.pi + spin;
              final s = math.sin(ang);
              final x = boxW / 2 + ar * math.cos(ang);
              final y = boxH / 2 + br * s;
              (s < 0 ? back : front).add(_label(node, x, y, s));
            }
          }
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              ...back,
              Center(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: widget.currentId.isEmpty
                        ? null
                        : () => widget.onOpenNode(widget.currentId),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: planetMaxH,
                        maxWidth: math.min(widget.maxImageW, aInner * 1.5),
                      ),
                      child: planet,
                    ),
                  ),
                ),
              ),
              ...front,
            ],
          );
        },
      ),
    ),
    );
  }
}

// 読み上げチャンク(文単位)。nodeIndex/nodeTotalは進捗表示用
class _Chunk {
  final ManidocNode node;
  final int nodeIndex;
  final int nodeTotal;
  final String text;
  _Chunk(this.node, this.nodeIndex, this.nodeTotal, this.text);
}

// 配置前のエントリ(方向+圏)
class _Entry {
  final ManidocProject project;
  final double az, el;
  final int ring;
  _Entry(this.project, this.az, this.el, this.ring);
}

// 画面に投影済みのタイル
class _Placed {
  final ManidocProject project;
  final int ring;
  final double sx, sy, a, el, z, depth;
  _Placed(this.project, this.ring, this.sx, this.sy, this.a, this.el, this.z,
      this.depth);
}

class _Card extends StatelessWidget {
  final String title;
  final int nodeCount;
  final Color color;
  final double alpha; // フェード(Opacityの代わりに色のalphaへ畳む)
  const _Card(
      {required this.title,
      required this.nodeCount,
      required this.color,
      this.alpha = 1.0});

  @override
  Widget build(BuildContext context) {
    final a = alpha.clamp(0.0, 1.0);
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: a),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.45 * a),
              blurRadius: 14,
              offset: const Offset(0, 8)),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.15 * a)),
      ),
      padding: const EdgeInsets.all(11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_rounded,
              color: Colors.white.withValues(alpha: 0.7 * a), size: 22),
          const Spacer(),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: a),
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          const SizedBox(height: 3),
          Text('${L.t('items')}: $nodeCount',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75 * a),
                  fontSize: 10)),
        ],
      ),
    );
  }
}
