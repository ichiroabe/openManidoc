import 'package:encrypt/encrypt.dart';

/// APIキー等の機微情報をAES暗号化する。
/// 鍵は **openManidoc専用**(旧Manidocとは別物)。設定ファイルに平文を残さない。
class CryptoService {
  // openManidoc固有の32バイト鍵と16バイトIV(Manidocのものとは異なる)
  static final _key = Key.fromUtf8('0penManid0c_Fl4tt3r_AES_Key_2026');
  static final _iv = IV.fromUtf8('0penManidocIV016');
  static final _encrypter = Encrypter(AES(_key, mode: AESMode.cbc));

  static String encryptText(String plain) {
    if (plain.isEmpty) return '';
    return _encrypter.encrypt(plain, iv: _iv).base64;
  }

  static String decryptText(String cipherBase64) {
    if (cipherBase64.isEmpty) return '';
    try {
      return _encrypter.decrypt64(cipherBase64, iv: _iv);
    } catch (_) {
      return ''; // 復号できない(鍵違い・破損)場合は空扱い
    }
  }
}
