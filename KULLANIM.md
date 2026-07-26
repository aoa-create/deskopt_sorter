# Masaüstü Proje ve Tür Düzenleyici

Uygulama masaüstündeki doğrudan dosya ve klasörleri şu hedef altında
düzenler:

`C:\Users\aoa02\Documents\Masaustu_Duzenlenmis`

## Çalışma biçimi

- Dosyalar önce proje adına, sonra dosya türüne göre ayrılır.
- Proje klasörlerinin iç yapısı parçalanmaz; klasör tek parça taşınır.
- Dosya silinmez ve var olan hedefin üzerine yazılmaz.
- Aynı ad varsa `__Masaustu_1`, `__Masaustu_2` biçiminde yeni ad üretilir.
- Dosya taşındıktan sonra SHA-256 değeri doğrulanır.
- Klasörlerde dosya sayısı ve toplam bayt değeri önce/sonra karşılaştırılır.
- Her gerçek işlem için CSV manifest ve JSON özet oluşturulur.
- Uygulamadaki **Son İşlemi Geri Al** düğmesi son taşıma manifestini tersine
  uygular.
- Reparse point/junction klasörleri güvenlik nedeniyle taşınmaz.

## Masaüstü uygulaması

Masaüstündeki `Masaustunu_Duzenle` kısayolunu açın.

Uygulamada:

1. **Önizlemeyi Yenile** hangi öğenin nereye gideceğini gösterir.
2. **Masaüstünü Düzenle** güvenli taşıma işlemini başlatır.
3. **Son İşlemi Geri Al** son taşıma işlemini geri çevirir.
4. **Belgeleri Yönet** proje/uzantı düzenleme, yinelenen ve atık klasör
   temizliği ekranını açar.
5. **Hedef Klasörü Aç** düzenlenen dosyaları gösterir.

## Komut satırından önizleme

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\Masaustu_Duzenleyici.ps1" `
  -Mode Preview
```

Gerçek taşıma için `-Mode Move`, geri alma için `-Mode UndoLast` kullanılır.
Etkileşimsiz çalışma ancak bilinçli otomasyon için `-NonInteractive`
parametresiyle etkinleştirilir.
