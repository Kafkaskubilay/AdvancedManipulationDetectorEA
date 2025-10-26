//+------------------------------------------------------------------+
//|                 AdvancedManipulationDetector_Common.mqh          |
//|                      Copyright 2024, Manus AI                    |
//|                                  https://manus.im                |
//| MT4 & MT5 Ortak Fonksiyonlar ve Değişkenler (v1.07)              |
//+------------------------------------------------------------------+
#property copyright "Manus AI"
#property link      "https://manus.im"
#property version   "1.07"
#property strict

//--- Platformdan bağımsız loglama fonksiyonu
void Log(string symbol, string message);

//--- Platformdan bağımsız fiyat alma (MT4 ve MT5'te ayrı ayrı tanımlanacak)
double GetAsk(string symbol);
double GetBid(string symbol);

//--- Platformdan bağımsız lot hesaplama (MT4 ve MT5'te ayrı ayrı tanımlanacak)
double CalculateLotSize(string symbol, int sl_pips);

//--- Platformdan bağımsız işlem açma (MT4 ve MT5'te ayrı ayrı tanımlanacak)
bool OpenTrade(string symbol, ENUM_ORDER_TYPE order_type, double lot, double price, int sl_pips, int tp_pips, string comment);

//--- Platformdan bağımsız pozisyon yönetimi (MT4 ve MT5'te ayrı ayrı tanımlanacak)
void ManagePositions(string symbol);

//--- Platformdan bağımsız OnInit, OnDeinit, OnTick (MT4 ve MT5'te ayrı ayrı tanımlanacak)
int OnInit_MT4();
void OnDeinit_MT4(const int reason);
void OnTick_MT4();

int OnInit_MT5();
void OnDeinit_MT5(const int reason);
void OnTick_MT5();

//--- MT5'e özel OnBookEvent handler (MT5'te ayrı tanımlanacak)
#ifdef __MQL5__
void HandleBookEvent(string symbol, const MqlBookInfo &book[]);
#endif

//+------------------------------------------------------------------+
//| Giriş Parametreleri - Tüm ayarlar buradan kontrol edilir          |
//+------------------------------------------------------------------+
input group "=== GENEL AYARLAR ===";
input int MagicNumber = 20240118;              // EA'nın işlemlerini tanımlamak için sihirli numara
input string Symbols_List = "EURUSD,GBPUSD";    // İşlem yapılacak sembollerin virgülle ayrılmış listesi
input int StopLossPips = 15;                   // Başlangıç Stop Loss mesafesi (pip)
input int TakeProfitPips = 3;                  // Başlangıç Take Profit mesafesi (pip)

input group "=== RİSK YÖNETİMİ ===";
input double RiskPercent = 1.0;                // İşlem başına risk yüzdesi (%)
input double FixedLotSize = 0.01;              // RiskPercent=0 ise kullanılacak sabit lot
input int MaxConsecutiveLoss = 3;              // Ardışık kayıp limiti (bu sayıya ulaşılırsa EA durur)
input int MaxSlippagePips = 5;                 // Maksimum kayma (slippage) toleransı (pip)

input group "=== STRATEJİ AYARLARI ===";
input int MaxSpreadPips = 2;                   // Maksimum spread eşiği (pip)
input int MaxPositionDuration_s = 180;         // Maksimum pozisyon tutma süresi (saniye)
input bool UseATRFilter = true;                // ATR tabanlı dinamik spike eşiği kullanılsın mı?
input double ATRMultiplier = 1.5;              // ATR'nin kaç katı spike olarak kabul edilsin?
input int SpikeCandlePips = 10;                // Sabit spike eşiği (ATR kullanılmazsa)
input double VolumeAnomalyMultiplier = 2.0;     // Ortalama hacmin kaç katı anomali sayılsın?
input int MinSignalFilters = 2;                // İşlem açmak için geçilmesi gereken minimum filtre sayısı (Spike, Hacim, DOM)

input group "=== POZİSYON YÖNETİMİ ===";
input int PartialClosePips = 1;                // Kısmi kar alma mesafesi (pip)
input double PartialCloseVolume = 0.5;         // Kısmi kapatılacak hacim oranı (0.0 - 1.0)
input int BreakEvenPips = 2;                   // Break-Even'a çekme mesafesi (pip)
input int TrailingStopPips = 5;                // Trailing Stop mesafesi (pip)

input group "=== ZAMAN VE KORUMA FİLTRELERİ ===";
input string TradingHours = "00:00-23:59";     // İşlem saatleri (ör: 09:00-17:00)
input string TradingDays = "1,2,3,4,5";        // İşlem günleri (1=Pzt, 5=Cuma)
input bool AvoidSwapNight = true;              // Swap gecesi pozisyon açmayı engelle
input int SwapAvoidanceHour = 22;              // Swap gecesi başlangıç saati (genellikle 22 veya 23)

//+------------------------------------------------------------------+
//| Global Değişkenler (Ortak)                                       |
//+------------------------------------------------------------------+
extern bool ServerBusyMode = false;             // Sunucu meşgul hatası alınca bekleme modu
extern int ConsecutiveLosses = 0;               // Ardışık kayıp sayacı
extern datetime LastTradeTime = 0;              // Son işlem zamanı
extern double SymbolScores[];                   // Öğrenme/Dinamik Uyum için sembol skorları
extern string g_symbols[];                      // Symbols_List'ten ayrılmış semboller
extern int g_symbol_count = 0;                  // Sembol sayısı

//+------------------------------------------------------------------+
//| Yardımcı Fonksiyonlar                                            |
//+------------------------------------------------------------------+

//--- Loglama fonksiyonu
void Log(string symbol, string message)
{
   Print(TimeToString(TimeCurrent(), TIME_SECONDS) + " [" + (string)MagicNumber + "] " + symbol + " | " + message);
}

//--- Sembolün indeksini bulur (Çoklu Sembol Desteği için)
int GetSymbolIndex(string symbol)
{
   for (int i = 0; i < g_symbol_count; i++)
   {
      if (StringFind(g_symbols[i], symbol) != -1) return i;
   }
   return -1;
}

//--- İşlem Saatleri Kontrolü
bool IsTradingTime()
{
   // Gün kontrolü
   int current_day = TimeDayOfWeek(TimeCurrent());
   string days[];
   int day_count = StringSplit(TradingDays, ',', days);
   bool day_ok = false;
   for (int i = 0; i < day_count; i++)
   {
      if (StringToInteger(days[i]) == current_day)
      {
         day_ok = true;
         break;
      }
   }
   if (!day_ok) return false;

   // Saat kontrolü
   int start_hour = StringToInteger(StringSubstr(TradingHours, 0, 2));
   int end_hour = StringToInteger(StringSubstr(TradingHours, 6, 2));
   int current_hour = TimeHour(TimeCurrent());

   if (start_hour <= end_hour)
   {
      return (current_hour >= start_hour && current_hour < end_hour);
   }
   else // Gece yarısını geçen saatler (ör: 22:00-04:00)
   {
      return (current_hour >= start_hour || current_hour < end_hour);
   }
}

//--- Swap Gecesi Kontrolü
bool IsSwapNight()
{
   if (!AvoidSwapNight) return false;
   
   // Cuma gecesi 22:00-23:59 arası (Swap gecesi)
   if (TimeDayOfWeek(TimeCurrent()) == 5 && TimeHour(TimeCurrent()) >= SwapAvoidanceHour) return true;
   
   return false;
}

//--- Ardışık Kayıp Kontrolü
bool IsMaxLossReached()
{
   if (ConsecutiveLosses >= MaxConsecutiveLoss)
   {
      Log("", "MAKSİMUM ARDIŞIK KAYIP LİMİTİNE ULAŞILDI (" + (string)MaxConsecutiveLoss + "). EA DURDURULDU.");
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Sinyal Tespiti (Strateji Çekirdeği)                              |
//+------------------------------------------------------------------+

//--- Fiyat Spike Tespiti (ATR Dinamik Eşikli)
// Not: Bu fonksiyon MT4/MT5'te CopyRates/CopyTickVolume kullanır.
bool DetectPriceSpike(string symbol, ENUM_TIMEFRAME tf, int bars_back, double &spike_pips)
{
   MqlRates rates[];
   if (CopyRates(symbol, tf, 1, bars_back + 1, rates) != bars_back + 1) return false;
   
   double current_candle_range = rates[bars_back].high - rates[bars_back].low;
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   
   // ATR Hesaplama (M15'te 14 periyot)
   double atr_values[];
   if (iATR(symbol, PERIOD_M15, 14, atr_values) <= 0) return false;
   double atr_value = atr_values[0];
   
   // Dinamik Eşik: ATR * Çarpan veya Sabit Eşik
   double pip_size = point * (digits == 5 || digits == 3 ? 10 : 1);
   double dynamic_threshold = UseATRFilter ? (atr_value * ATRMultiplier) : (SpikeCandlePips * pip_size);
   
   if (current_candle_range > dynamic_threshold)
   {
      spike_pips = current_candle_range / pip_size;
      Log(symbol, "Fiyat Spike Tespit Edildi (Dinamik Eşik): Range: " + DoubleToString(spike_pips, 1) + " pips. Eşik: " + DoubleToString(dynamic_threshold / pip_size, 1) + " pips.");
      return true;
   }
   return false;
}

//--- Hacim Anomali Tespiti
bool DetectVolumeAnomaly(string symbol, ENUM_TIMEFRAME tf, int bars_back)
{
   long volumes[];
   if (CopyTickVolume(symbol, tf, 1, bars_back + 1, volumes) != bars_back + 1) return false;
   
   long current_volume = volumes[bars_back];
   long avg_volume = 0;
   
   // Son 10 mumun ortalama hacmini al (0. mum hariç)
   for (int i = 0; i < bars_back; i++)
   {
      avg_volume += volumes[i];
   }
   avg_volume /= bars_back;
   
   if ((double)current_volume > (double)avg_volume * VolumeAnomalyMultiplier)
   {
      Log(symbol, "Hacim Anomali Tespit Edildi: Mevcut Hacim: " + (string)current_volume + ", Ortalama: " + (string)avg_volume);
      return true;
   }
   return false;
}

//--- Ana Sinyal Tespiti (Çoklu Filtre Onayı)
ENUM_ORDER_TYPE DetectManipulationSignal(string symbol)
{
   // Sadece son kapanan mumda sinyal ara (M1)
   ENUM_TIMEFRAME tf = PERIOD_M1;
   int bars_back = 1;
   
   double spike_pips = 0.0;
   int signal_count = 0;
   
   // 1. Fiyat Spike Filtresi
   bool price_spike = DetectPriceSpike(symbol, tf, bars_back, spike_pips);
   if (price_spike) signal_count++;
   
   // 2. Hacim Anomali Filtresi
   bool volume_anomaly = DetectVolumeAnomaly(symbol, tf, bars_back);
   if (volume_anomaly) signal_count++;
   
   // 3. Emir Defteri Anomali Filtresi (Sadece MT5)
   #ifdef __MQL5__
      extern bool BookAnomalyDetected;
      if (BookAnomalyDetected) signal_count++;
   #endif
   
   // Minimum filtre sayısını kontrol et
   if (signal_count < MinSignalFilters)
   {
      if (price_spike || volume_anomaly) Log(symbol, "Sinyal Zayıf: Sadece " + (string)signal_count + " filtre geçti. Min: " + (string)MinSignalFilters);
      return (ENUM_ORDER_TYPE)-1;
   }
   
   // Sinyal Yönü: Spike'ın tersi (Reversal)
   MqlRates rates[];
   if (CopyRates(symbol, tf, 1, bars_back + 1, rates) != bars_back + 1) return (ENUM_ORDER_TYPE)-1;
   
   // Mumun kapanışı açılışından yüksekse (yeşil mum), spike yukarıdır, SELL sinyali
   if (rates[bars_back].close > rates[bars_back].open)
   {
      Log(symbol, "GÜÇLÜ SİNYAL: SELL (Yukarı Spike Reversal)");
      return ORDER_TYPE_SELL;
   }
   // Mumun kapanışı açılışından düşükse (kırmızı mum), spike aşağıdır, BUY sinyali
   else if (rates[bars_back].close < rates[bars_back].open)
   {
      Log(symbol, "GÜÇLÜ SİNYAL: BUY (Aşağı Spike Reversal)");
      return ORDER_TYPE_BUY;
   }
   
   // Doji veya belirsiz mum
   return (ENUM_ORDER_TYPE)-1;
}

