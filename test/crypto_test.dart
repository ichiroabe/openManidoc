import 'package:flutter_test/flutter_test.dart';
import 'package:open_manidoc/services/crypto_service.dart';

void main() {
  test('API key encrypts to non-plaintext and decrypts back', () {
    const key = 'AIzaSy-EXAMPLE-secret-key-1234567890';
    final enc = CryptoService.encryptText(key);
    expect(enc, isNotEmpty);
    expect(enc, isNot(contains(key))); // 平文が含まれない
    expect(CryptoService.decryptText(enc), key);
  });

  test('empty stays empty and broken cipher yields empty', () {
    expect(CryptoService.encryptText(''), '');
    expect(CryptoService.decryptText(''), '');
    expect(CryptoService.decryptText('not-valid-base64-@@@'), '');
  });
}
