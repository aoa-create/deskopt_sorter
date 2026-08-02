# Build status — 2026-08-02

## GitHub Actions sonucu

- Workflow: `Build and test Windows EXE`
- Run ID: `30766209808`
- Sonuç: `success`
- Windows runner: `windows-latest`
- Kaynak commit: `37b93a6491fc45bd240b78346e816d5f5a5de126`
- Birleştirme commit'i: `ceb8faec6fd1d87853f64abab443049f79b45e1b`

Başarılı adımlar:

1. PowerShell kaynak sözdizimi ayrıştırma
2. Kaynak PS1 Preview/Move/UndoLast smoke testi
3. PS2EXE kurulumu
4. DEBUG ve RELEASE Windows x64 EXE derlemesi
5. PE `MZ` imza doğrulaması
6. Derlenmiş DEBUG EXE Preview/Move/UndoLast smoke testi
7. SHA-256 checksum üretimi
8. GitHub artifact yükleme

## Artifact

- Artifact ID: `8839019942`
- Artifact adı: `Masaustu-Duzenleyici-Windows-x64`
- Artifact ZIP SHA-256: `30c018b2d08d3aa0582b45705b46f43dcd12191dbe4565a653ef86cc72d0ed15`

Paket içeriği:

- `Masaustu_Duzenleyici.exe`
- `Masaustu_Duzenleyici_DEBUG.exe`
- `Masaustu_Duzenleyici.ps1`
- `README.md`
- `SHA256SUMS.txt`

EXE SHA-256 değerleri:

- RELEASE: `9943DCDA77AAD42269AC61C6B7DCB37CBFBF4D7CE2C2681E80793D5909140399`
- DEBUG: `24A90DB0CA8968C918F136B30701160C0C3D4017778190C4A8A01B9AA6ADC74F`

## İmza durumu

EXE dosyaları SHA-256 ile doğrulanmıştır ancak ticari Authenticode sertifikasıyla kod imzalanmamıştır. Windows SmartScreen ilk açılışta uyarı gösterebilir.
