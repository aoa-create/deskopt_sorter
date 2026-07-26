# Belgeler Proje, Tür ve Yinelenen Düzenleyici

Bu araç `Documents`/`Belgeler` klasörünün doğrudan içindeki öğeleri şu
yapıya taşır:

- `PROJE_ARSIVI`: Projeler ve aynı projenin ayrı sürüm klasörleri
- `DOSYA_TURU_ARSIVI`: Uzantıya göre toplanan klasörler ve bağımsız dosyalar
- `ARSIV_VE_YEDEKLER`: Eski yedek ve işlem kayıtları
- `GENEL_KLASORLER`: Proje veya uzantı klasörü olmayan genel klasörler
- `_BELGELER_DUZENLEME_KAYITLARI`: CSV/JSON işlem kanıtları

## Korunan alanlar

Çalışan sistemlerin bozulmaması için şu klasörler taşınmaz ve
tekilleştirilmez:

- `Codex`
- `Masaustu_Duzenlenmis`
- `Masaustu_Duzenleyici_Uygulamasi`
- `WindowsPowerShell`
- `GitHub_Projeleri`
- etkin sistem günlüğü olduğu için kilitli `pclog.CSV`

## Yinelenen güvenliği

Yinelenen silme yalnız `DOSYA_TURU_ARSIVI` altında yapılır. Dosyalar:

1. önce aynı boyuta göre adaylaştırılır,
2. sonra SHA-256 değerleri karşılaştırılır,
3. yalnız birebir aynı olan ek kopyalar Geri Dönüşüm Kutusu'na gönderilir.

Proje sürüm klasörlerinin içindeki aynı destek dosyaları silinmez; her sürüm
çalışabilir bütün olarak korunur. Sıfır baytlık dosyalar otomatik
tekilleştirilmez.

## Yeniden üretilebilir atık klasörleri

Tam düzenleme aşağıdaki açıkça yeniden üretilebilir klasör adlarını Geri
Dönüşüm Kutusu'na gönderir:

- `.venv`, `venv`
- `__pycache__`
- `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `.tox`
- `.ipynb_checkpoints`
- `node_modules`
- `.cache`, `htmlcov`
- uzantı arşivindeki `CACHE` ve `PYC`

`.git`, proje kaynakları, ZIP yedekleri, `build` ve `dist` sürüm çıktıları bu
atık listesine dahil değildir.

## Komutlar

Salt okunur plan:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\Belgeler_Duzenleyici.ps1" -Mode Preview
```

Tam düzenleme:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\Belgeler_Duzenleyici.ps1" -Mode Full
```

Yalnız yinelenen önizlemesi için `-Mode DedupePreview`, son proje/uzantı
taşımasını geri almak için `-Mode UndoOrganize` kullanılır. Geri Dönüşüm
Kutusu'na gönderilen yinelenenler gerekirse Windows Geri Dönüşüm Kutusu'ndan
geri yüklenebilir.
