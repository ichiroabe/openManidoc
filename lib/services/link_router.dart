/// エディタ内リンク(AppFlowyのeditorLaunchUrl経由=Ctrl/ダブルクリック)の
/// グローバルなハンドラ。現在アクティブな編集画面が登録し、離れるとクリアする。
/// href が `#node:id` ならノード遷移、http(s) ならブラウザ起動を親側で振り分ける。
void Function(String href)? activeLinkHandler;
