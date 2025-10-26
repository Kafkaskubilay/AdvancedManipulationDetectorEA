//+------------------------------------------------------------------+
//|                 AdvancedManipulationDetector_Common.mqh          |
//|                      Copyright 2024, Manus AI                    |
//|                                  https://manus.im                |
//|         Ortak Değişkenler, Inputlar ve Sinyal Mantığı (v1.07)      |
//+------------------------------------------------------------------+
#property copyright "Manus AI"
#property link      "https://manus.im"
#property version   "1.07"
#property strict

//+------------------------------------------------------------------+
//| Input Parametreleri                                              |
//+------------------------------------------------------------------+
input group "--- Genel Ayarlar ---'
input string Symbols_List          = "EURUSD,GBPUSD"; // İşlem yapılacak sembol listesi (virgülle ayrılmış)
input string Expert_ID            = "AMD_EA_001"; // EA'nın sihirli numarası ve tanımlayıcısı
input int    MagicNumber          = 12345;        // İşlemleri ayırt etmek için sihirli numara
input double MaxPositionDuration_s= 180.0;        // Maksimum pozisyon tutma süresi (saniye)
input bool   EnableVisualPanel    = true;         // Görsel paneli etkinleştir

input group "--- Risk ve Para Yönetimi ---'
input double RiskPercent          = 1.0;          // Hesap bakiyesinin %'si olarak risk (0.0 - 100.0)
input double FixedLotSize         = 0.01;         // Risk hesaplaması devre dışıysa sabit lot
input int    StopLossPips         = 15;           // Stop Loss mesafesi (Pips)
input int    TakeProfitPips       = 8;            // Take Profit mesafesi (Pips)
input int    PartialClosePips     = 5;            // Kısmi kapama için kâr mesafesi (Pips)
input double PartialCloseVolume   = 0.5;          // Kısmi kapatılacak lot yüzdesi (0.0 - 1.0)
input int    BreakEvenPips        = 5;            // Kârda kaç pip sonra BE'ye çekileceği
input int    TrailingStopPips     = 3;            // Trailing Stop mesafesi (Pips)

input group "--- Manipülasyon Algılama Ayarları ---'
input int    MaxSpreadPips        = 3;            // Maksimum izin verilen spread (Pips)
input double SpikeVolumeThreshold = 2.0;          // Normal hacmin kaç katı hacim artışı spike sayılır
input int    SpikeCandlePips      = 10;           // İğne uzunluğu kaç pip olursa potansiyel spike sayılır (Dinamik eşik için taban)
input bool   Use_ATR_Threshold    = true;         // Spike tespiti için ATR tabanlı dinamik eşik kullan
input double ATR_Multiplier       = 1.5;          // Dinamik eşik için ATR çarpanı
input double MaxSlippagePips      = 1.5;          // Maksimum izin verilen kayma (Pips)

input group "--- Koruma Sistemleri ---'
input int    MaxConsecutiveLosses = 3;            // Maksimum ardışık kayıp limiti
input bool   FilterNews           = false;        // Haber filtresini etkinleştir (Yer tutucu)
input bool   CheckSwapCost        = true;         // Yüksek swap maliyetli gecelerde işlem açmayı kontrol et

input group "--- Zaman Filtreleri ---'
input int    StartHour            = 0;            // İşlem başlangıç saati (0-23)
input int    EndHour              = 23;           // İşlem bitiş saati (0-23)
input bool   TradeMonday          = true;
input bool   TradeTuesday         = true;
input bool   TradeWednesday       = true;
input bool   TradeThursday        = true;
input bool   TradeFriday          = true;

//+------------------------------------------------------------------+
//| Ortak Global Değişkenler ve Yapılar                              |
//+------------------------------------------------------------------+
//--- Koruma Sistemleri için Değişkenler
int ConsecutiveLosses = 0;
bool ServerBusyMode = false; // Sunucu hatası durumunda bekleme modu

//--- Ortak Enum
enum ENUM_ORDER_TYPE
{
   ORDER_TYPE_BUY  = 0,
   ORDER_TYPE_SELL = 1
};

//+------------------------------------------------------------------+
//| Ortak Yardımcı Fonksiyonlar                                      |
//+------------------------------------------------------------------+

//--- Loglama fonksiyonu
void Log(string symbol, string message)
{
   Print(TimeToString(TimeCurrent(), TIME_SECONDS) + " [" + Expert_ID + "] " + symbol + " | " + message);
}

//--- Zaman ve Gün Kontrolü
bool IsTradingTime()
{
   int current_hour = TimeHour(TimeCurrent());
   if (current_hour < StartHour || current_hour > EndHour)
   {
      return false;
   }
   
   int current_day = TimeDayOfWeek(TimeCurrent());
   if ((current_day == MONDAY && !TradeMonday) || (current_day == TUESDAY && !TradeTuesday) || (current_day == WEDNESDAY && !TradeWednesday) || (current_day == THURSDAY && !TradeThursday) || (current_day == FRIDAY && !TradeFriday))
   {
      return false;
   }
   
   if (current_day == SATURDAY || current_day == SUNDAY) return false;
   
   return true;
}

