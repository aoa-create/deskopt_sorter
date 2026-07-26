# Desktop and Documents Organizer

Windows masaüstü ve Belgeler klasörünü sade biçimde yönetmek için PowerShell
araçları.

## Kullanım

`Masaustu_Duzenleyici.ps1` kullanıcı arayüzünü açar. Arayüzde:

- Masaüstünü Düzenle: masaüstündeki projeleri ve bağımsız dosyaları ayırır.
- Belgeleri Yönet: Belgeler düzenleyicisini açar.
- Projeleri Sadeleştir: projeleri `GitHub_Projeleri` altında, bağımsız
  dosyaları `DOSYA_KOKENLI_ARSIV` altında toplar.

Silinebilir içerikler mümkün olduğunda Geri Dönüşüm Kutusu'na gönderilir.
Gerçek işlemden önce `Sade_Belgeler_Proje_Duzenleyici.ps1 -Mode Preview`
ile önizleme alınabilir.
