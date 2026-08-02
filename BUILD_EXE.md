# Windows EXE derleme ve test

Bu depo, `Masaustu_Duzenleyici.ps1` kaynağını GitHub Actions üzerindeki `windows-latest` çalıştırıcısında PS2EXE ile derler.

## Üretilen dosyalar

- `Masaustu_Duzenleyici.exe`: konsolsuz GUI RELEASE sürümü
- `Masaustu_Duzenleyici_DEBUG.exe`: konsollu tanılama sürümü
- `SHA256SUMS.txt`: EXE SHA-256 doğrulama değerleri
- `Masaustu_Duzenleyici.ps1`: derlenen kaynak

## Otomatik testler

1. PowerShell 5.1 sözdizimi ayrıştırma testi
2. Kaynak PS1 ile Preview testi; kaynak dosyaların yerinde kaldığının doğrulanması
3. Move testi; dosya ve proje klasörlerinin hedefe taşındığının doğrulanması
4. UndoLast testi; son taşımanın geri alındığının doğrulanması
5. DEBUG EXE ile aynı uçtan uca smoke test
6. Her EXE için Windows PE `MZ` imza kontrolü
7. SHA-256 checksum üretimi

Testler yalnız GitHub Windows runner içindeki geçici klasörlerde çalışır; kullanıcının gerçek dosyalarına erişmez.
