# Advanced Manipulation Detector Expert Advisor (AMD EA) - v1.04

## 1. Giriş
**Advanced Manipulation Detector Expert Advisor (AMD EA)**, MetaTrader 4 (MT4) ve MetaTrader 5 (MT5) platformlarında çalışmak üzere tasarlanmış, piyasa manipülasyonlarını (sahte kırılım, stop hunt, spike, spoofing) algılayarak ters yönde işlem açmayı hedefleyen profesyonel bir scalping robotudur.

**Önemli Not:** Önceki versiyonlarda yaşanan derleme hataları, kodun platforma özel dosyalara ayrılarak (v1.04) tamamen giderilmiştir. Kod artık hatasız derlenmektedir.

## 2. Strateji Özeti
AMD EA, temel olarak **"Manipülasyona Karşı İşlem Açma"** mantığıyla çalışır.

| Özellik | Açıklama |
| :--- | :--- |
| **Temel Yöntem** | Scalping. Çok kısa sürede (maksimum 180 saniye) küçük pip kârları hedefler. |
| **Tetikleyiciler** | **1. Spike Mumları:** İğne uzunluğunun gövdeye oranla belirgin bir şekilde uzun olduğu mumlar (`SpikeCandlePips` parametresi ile kontrol edilir). **2. Hacim Anomalisi:** SpikeVolumeThreshold ile hacim onayı. |
| **MT5 Ek Filtre** | **Emir Defteri (DOM):** `OnBookEvent` ile en iyi 5 seviyedeki toplam hacimde ani ve büyük değişimler (Spoofing/Stop Hunt denemeleri) bir sinyal filtresi olarak kullanılır. |
| **İşlem Yönü** | Tespit edilen manipülasyonun tersi yönünde (Yukarı Spike -> SELL, Aşağı Spike -> BUY). |

## 3. Teknik Özellikler ve Kurulum
### 3.1. MT4 ve MT5 Uyumluluğu
EA, platforma özel başlık dosyaları kullanılarak tam uyumluluk sağlar.

*   **Ortak Kodlar:** `AdvancedManipulationDetector_Common.mqh`
*   **MT4 Başlık:** `AdvancedManipulationDetector_MT4.mqh`
*   **MT5 Başlık:** `AdvancedManipulationDetector_MT5.mqh`
*   **MT4 Ana Dosya:** `AdvancedManipulationDetectorEA.mq4`
*   **MT5 Ana Dosya:** `AdvancedManipulationDetectorEA.mq5`

### 3.2. Kurulum
1.  MetaTrader platformunuzu açın.
2.  `Dosya` -> `Veri Klasörünü Aç` (`File` -> `Open Data Folder`) yolunu izleyin.
3.  Açılan klasörde `MQL4` (MT4 için) veya `MQL5` (MT5 için) klasörüne gidin.
4.  Tüm `.mqh`, `.mq4` ve `.mq5` dosyalarını `Experts` klasörüne kopyalayın.
5.  MetaTrader'ı yeniden başlatın veya `Gezgin` (`Navigator`) penceresinde `Expert Advisors` üzerine sağ tıklayıp `Yenile` (`Refresh`) seçeneğini seçin.

## 4. Parametreler (Inputs)
Aşağıdaki tabloda EA'nın tüm ayarlanabilir parametreleri ve açıklamaları yer almaktadır.

| Grup | Parametre | Varsayılan | Açıklama |
| :--- | :--- | :--- | :--- |
| **Genel Ayarlar** | `Expert_ID` | AMD\_EA\_001 | EA'nın loglarda ve yorumlarda kullanılacak tanımlayıcısı. |
| | `MagicNumber` | 12345 | EA'nın açtığı işlemleri diğer işlemlerden ayırmak için kullanılan sihirli numara. |
| | `MaxPositionDuration_s` | 180.0 | Açık pozisyonun otomatik olarak kapatılacağı maksimum süre (saniye). (Scalping stratejisi için kritik). |
| | `EnableVisualPanel` | true | Grafikte durum panelini göster/gizle. |
| **Risk ve Para Yönetimi** | `RiskPercent` | 1.0 | Her işlemde hesap bakiyesinin riske edilecek yüzdesi (0.0 = Sabit Lot). |
| | `FixedLotSize` | 0.01 | `RiskPercent` 0.0 ise kullanılacak sabit lot büyüklüğü. |
| | `StopLossPips` | 10 | Başlangıç Stop Loss mesafesi (pip). |
| | `TakeProfitPips` | 5 | Başlangıç Take Profit mesafesi (pip). |
| | `PartialClosePips` | 5 | Kâr kaç pip'e ulaştığında kısmi kapama yapılacağı. |
| | `PartialCloseVolume` | 0.5 | Kısmi kapatılacak lot yüzdesi (0.0-1.0). |
| | `BreakEvenPips` | 5 | Kâr kaç pip'e ulaştığında Stop Loss'u Açılış Fiyatına (BE) çekeceği. |
| | `TrailingStopPips` | 3 | Trailing Stop'un aktif olacağı mesafe (pip). |
| **Manipülasyon Algılama**| `MaxSpreadPips` | 2 | Maksimum izin verilen spread (pip). Bu değer aşılırsa işlem açılmaz. |
| | `SpikeVolumeThreshold` | 2.0 | Normal hacmin (son mumun) kaç katı hacim artışı spike sayılır. |
| | `SpikeCandlePips` | 10 | Mumun iğne uzunluğu kaç pip olursa potansiyel spike sinyali olarak değerlendirilir. |
| | `MaxSlippagePips` | 1.0 | Maksimum izin verilen kayma (pip). |
| **Koruma Sistemleri** | `MaxConsecutiveLosses` | 5 | Maksimum ardışık kayıp limiti. Bu limite ulaşılırsa EA durur. |
| | `FilterNews` | false | Haber filtresini etkinleştir (Yer tutucu mantığı içerir). |
| | `CheckSwapCost` | true | Yüksek swap maliyetli gecelerde (örn. Çarşamba) işlem açmayı kontrol et. |
| **Zaman Filtreleri** | `StartHour` | 0 | İşlem başlangıç saati (Sunucu Saati). |
| | `EndHour` | 23 | İşlem bitiş saati (Sunucu Saati). |
| | `TradeMonday` - `TradeFriday` | true | Hangi günlerde işlem yapılacağını belirler. |

## 5. Gelişmiş Strateji ve Kod Detayları
### 5.1. Dinamik Lot Hesaplama
EA, kullanıcı tarafından belirlenen `% Risk` (`RiskPercent`) parametresine göre dinamik lot hesaplaması yapar. Bu, her işlemde riskin sabit bir yüzde ile sınırlanmasını sağlar ve Stop Loss mesafesine göre lot büyüklüğünü otomatik ayarlar.

$$
\text{Lot} = \frac{\text{Hesap Bakiyesi} \times (\text{Risk Yüzdesi} / 100)}{\text{SL Mesafesi} \times \text{Pip Değeri}}
$$

### 5.2. MT5 Emir Defteri (OnBookEvent)
MT5'te, `OnBookEvent` fonksiyonu en iyi 5 fiyat seviyesindeki toplam emir hacminde %50'den fazla ani bir değişim tespit ederse (`BookAnomalyDetected` = `true`) olarak işaretler. Bu bilgi, `OnTick` fonksiyonunda sinyal filtresi olarak kullanılmak üzere entegre edilmiştir.

### 5.3. Koruma Sistemleri
EA, sermayeyi korumak ve riskleri yönetmek için bir dizi koruma sistemi içerir:

*   **Maksimum Süre:** `MaxPositionDuration_s` süresi dolan pozisyonlar otomatik kapatılır.
*   **Ardışık Kayıp Limiti:** `MaxConsecutiveLosses` limitine ulaşıldığında EA yeni işlem açmayı durdurur.
*   **Sunucu Hatası Kontrolü:** `OrderSend` hatalarında (bağlantı kesilmesi, sunucu meşgul) `ServerBusyMode` değişkeni ile EA bekleme moduna geçer.
*   **Spread ve Slippage Kontrolü:** İşlem açılmadan önce `MaxSpreadPips` ve `MaxSlippagePips` değerleri kontrol edilir.

### 5.4. Öğrenme/Dinamik Uyum (Skor Tablosu)
EA, her kapanan işlemden sonra `UpdateTradeScore` fonksiyonu ile sembol bazlı bir skor tablosu tutar. Bu tablo, kazanma yüzdesi ve ortalama kâr gibi metrikleri izleyerek, EA'nın hangi koşullarda daha başarılı olduğunu anlamasına yardımcı olur. Bu, gelecekteki **dinamik optimizasyon** için bir temel oluşturur.

## 6. Geliştirme Ortamı ve GitHub
EA'nın kaynak kodları, şeffaflık ve kolay yönetim için GitHub'da bir depo olarak yayınlanmıştır.

*   **GitHub Deposu:** [https://github.com/Kafkaskubilay/AdvancedManipulationDetectorEA](https://github.com/Kafkaskubilay/AdvancedManipulationDetectorEA)

En güncel kodlara ve gelecekteki güncellemelere bu depo üzerinden erişebilirsiniz.

---
*Bu dokümantasyon **Manus AI** tarafından otomatik olarak oluşturulmuştur.*

