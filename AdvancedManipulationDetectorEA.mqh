//+------------------------------------------------------------------+
//|                                AdvancedManipulationDetectorEA.mqh|
//|                      Copyright 2024, Manus AI                     |
//|                                  https://manus.im                 |
//+------------------------------------------------------------------+
#property copyright "Manus AI"
#property link      "https://manus.im"
#property version   "1.02"
#property strict

//--- Gerekli kütüphaneleri içe aktar
#ifdef __MQL5__
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#endif

//+------------------------------------------------------------------+
//| Input Parametreleri                                              |
//+------------------------------------------------------------------+
input group "--- Genel Ayarlar ---"
input string Expert_ID            = "AMD_EA_001"; // EA'nın sihirli numarası ve tanımlayıcısı
input int    MagicNumber          = 12345;        // İşlemleri ayırt etmek için sihirli numara
input double MaxPositionDuration_s= 180.0;        // Maksimum pozisyon tutma süresi (saniye)
input bool   EnableVisualPanel    = true;         // Görsel paneli etkinleştir

input group "--- Risk ve Para Yönetimi ---"
input double RiskPercent          = 1.0;          // Hesap bakiyesinin %'si olarak risk (0.0 - 100.0)
input double FixedLotSize         = 0.01;         // Risk hesaplaması devre dışıysa sabit lot
input int    StopLossPips         = 10;           // Stop Loss mesafesi (Pips)
input int    TakeProfitPips       = 5;            // Take Profit mesafesi (Pips)
input int    PartialClosePips     = 5;            // Kısmi kapama için kâr mesafesi (Pips)
input double PartialCloseVolume   = 0.5;          // Kısmi kapatılacak lot yüzdesi (0.0 - 1.0)
input int    BreakEvenPips        = 5;            // Kârda kaç pip sonra BE'ye çekileceği
input int    TrailingStopPips     = 3;            // Trailing Stop mesafesi (Pips)

input group "--- Manipülasyon Algılama Ayarları ---"
input int    MaxSpreadPips        = 2;            // Maksimum izin verilen spread (Pips)
input double SpikeVolumeThreshold = 2.0;          // Normal hacmin kaç katı hacim artışı spike sayılır
input int    SpikeCandlePips      = 10;           // İğne uzunluğu kaç pip olursa potansiyel spike sayılır
input double MaxSlippagePips      = 1.0;          // Maksimum izin verilen kayma (Pips)

input group "--- Koruma Sistemleri ---"
input int    MaxConsecutiveLosses = 5;            // Maksimum ardışık kayıp limiti
input bool   FilterNews           = false;        // Haber filtresini etkinleştir
input bool   CheckSwapCost        = true;         // Yüksek swap maliyetli gecelerde işlem açmayı kontrol et

input group "--- Zaman Filtreleri ---"
input int    StartHour            = 0;            // İşlem başlangıç saati (0-23)
input int    EndHour              = 23;           // İşlem bitiş saati (0-23)
input bool   TradeMonday          = true;
input bool   TradeTuesday         = true;
input bool   TradeWednesday       = true;
input bool   TradeThursday        = true;
input bool   TradeFriday          = true;

//+------------------------------------------------------------------+
//| Global Değişkenler ve Sınıflar                                   |
//+------------------------------------------------------------------+
#ifdef __MQL5__
   CTrade      m_trade;        // MT5 İşlem sınıfı
   CPositionInfo m_position;   // MT5 Pozisyon bilgisi sınıfı
   MqlTick     last_tick;      // Son tick verisi
#endif

//--- Öğrenme/Dinamik Uyum için Skor Tablosu
struct TradeScore
{
   string symbol;
   int    total_trades;
   int    winning_trades;
   double total_profit;
   double average_profit;
};
TradeScore SymbolScores[10]; // Basit skor tablosu

//--- Koruma Sistemleri için Değişkenler
int ConsecutiveLosses = 0;
bool ServerBusyMode = false; // Sunucu hatası durumunda bekleme modu

//--- Görsel Panel için
string PanelText = "";

//+------------------------------------------------------------------+
//| MT4 için Gerekli Taklitler/Tanımlar                              |
//+------------------------------------------------------------------+
#ifdef __MQL4__

// MT4'te MqlRates yapısı
struct MqlRates
{
   datetime time;
   double open;
   double high;
   double low;
   double close;
   long tick_volume;
   int spread;
   long real_volume;
};

// MT4'te ENUM_ORDER_TYPE
enum ENUM_ORDER_TYPE
{
   ORDER_TYPE_BUY  = OP_BUY,
   ORDER_TYPE_SELL = OP_SELL
};

#define WRONG_VALUE -1

// MT4'te CopyRates taklidi
int CopyRates(string symbol, int timeframe, int start_pos, int count, MqlRates &rates[])
{
   if(ArraySize(rates) < count) ArrayResize(rates, count);

   for(int i = 0; i < count; i++)
   {
      rates[i].time = iTime(symbol, timeframe, i + start_pos);
      rates[i].open = iOpen(symbol, timeframe, i + start_pos);
      rates[i].high = iHigh(symbol, timeframe, i + start_pos);
      rates[i].low = iLow(symbol, timeframe, i + start_pos);
      rates[i].close = iClose(symbol, timeframe, i + start_pos);
      rates[i].tick_volume = (long)iVolume(symbol, timeframe, i + start_pos);
   }
   return count;
}

#endif

//+------------------------------------------------------------------+
//| Ortak Yardımcı Fonksiyonlar                                      |
//+------------------------------------------------------------------+

//--- Loglama fonksiyonu
void Log(string message)
{
   Print(TimeToString(TimeCurrent(), TIME_SECONDS) + " [" + Expert_ID + "] " + _Symbol + " | " + message);
}

//--- Platformdan bağımsız fiyat alma
double GetAsk()
{
#ifdef __MQL5__
   return SymbolInfoDouble(_Symbol, SYMBOL_ASK);
#else
   return MarketInfo(_Symbol, MODE_ASK);
#endif
}

double GetBid()
{
#ifdef __MQL5__
   return SymbolInfoDouble(_Symbol, SYMBOL_BID);
#else
   return MarketInfo(_Symbol, MODE_BID);
#endif
}

//+------------------------------------------------------------------+
//| Çekirdek EA Fonksiyonları                                        |
//+------------------------------------------------------------------+

//--- Lot büyüklüğünü hesaplama
double CalculateLotSize(int sl_pips)
{
   if (RiskPercent <= 0.0) return FixedLotSize;

   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_balance * (RiskPercent / 100.0);
   double sl_distance_points = sl_pips * _Point;

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tick_size == 0) return 0.01; // Bölme hatasını önle

   double value_per_point = tick_value / tick_size;
   double lot = risk_amount / (sl_distance_points * value_per_point);

   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / lot_step) * lot_step;

   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lot = MathMax(min_lot, MathMin(max_lot, lot));

   Log("Lot Hesaplandı: Risk: " + DoubleToString(risk_amount, 2) + ", SL Pips: " + (string)sl_pips + ", Lot: " + DoubleToString(lot, 2));
   return lot;
}

//--- İşlem açma fonksiyonu
bool OpenTrade(ENUM_ORDER_TYPE order_type, double lot, double price, int sl_pips, int tp_pips, string comment)
{
   if (lot <= 0) 
   {
      Log("HATA: Lot büyüklüğü sıfır veya negatif. İşlem açılamadı.");
      return false;
   }

   double current_spread_pips = (GetAsk() - GetBid()) / _Point;
   if (current_spread_pips > MaxSpreadPips)
   {
      Log("İŞLEM İPTAL: Spread çok yüksek (" + DoubleToString(current_spread_pips, 1) + " Pips). Max limit: " + (string)MaxSpreadPips + " Pips.");
      return false;
   }

   double sl_price = 0.0;
   double tp_price = 0.0;

   if (order_type == ORDER_TYPE_BUY)
   {
      sl_price = price - sl_pips * _Point;
      tp_price = price + tp_pips * _Point;
   }
   else if (order_type == ORDER_TYPE_SELL)
   {
      sl_price = price + sl_pips * _Point;
      tp_price = price - tp_pips * _Point;
   }

   sl_price = NormalizeDouble(sl_price, (int)_Digits);
   tp_price = NormalizeDouble(tp_price, (int)_Digits);

   string order_type_str = (order_type == ORDER_TYPE_BUY) ? "BUY" : "SELL";
   Log("İşlem Açılıyor: " + order_type_str + ", Lot: " + DoubleToString(lot, 2) + ", Fiyat: " + DoubleToString(price, (int)_Digits) + ", SL: " + DoubleToString(sl_price, (int)_Digits) + ", TP: " + DoubleToString(tp_price, (int)_Digits));

#ifdef __MQL5__
   MqlTradeRequest request={0};
   MqlTradeResult  result={0};

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.volume   = lot;
   request.type     = order_type;
   request.price    = price;
   request.sl       = sl_price;
   request.tp       = tp_price;
   request.deviation= (int)(MaxSlippagePips / _Point);
   request.magic    = MagicNumber;
   request.comment  = comment;

   if (!OrderSend(request, result))
   {
      Log("HATA: OrderSend başarısız oldu. Hata Kodu: " + (string)result.retcode);
      if (result.retcode == TRADE_RETCODE_NO_CONNECTION || result.retcode == TRADE_RETCODE_SERVER_BUSY) ServerBusyMode = true;
      return false;
   }
   if (ServerBusyMode) ServerBusyMode = false;
   Log("İŞLEM BAŞARILI: Pozisyon ID: " + (string)result.deal + ", Sonuç Kodu: " + (string)result.retcode);
   return true;

#else
   int ticket = OrderSend(_Symbol, order_type, lot, price, (int)(MaxSlippagePips / _Point), sl_price, tp_price, comment, MagicNumber, 0, clrNONE);
   if (ticket < 0)
   {
      int error_code = GetLastError();
      Log("HATA: OrderSend başarısız oldu. Hata Kodu: " + (string)error_code);
      if (error_code == 138 || error_code == 4060) ServerBusyMode = true; // Requote or Trade context busy
      return false;
   }
   if (ServerBusyMode) ServerBusyMode = false;
   Log("İŞLEM BAŞARILI: Ticket: " + (string)ticket);
   return true;
#endif
}

//--- Pozisyon yönetimi
void ManagePositions()
{
#ifdef __MQL5__
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (m_position.SelectByIndex(i) && m_position.Symbol() == _Symbol && m_position.Magic() == MagicNumber)
      {
         double current_price = (m_position.PositionType() == POSITION_TYPE_BUY) ? GetBid() : GetAsk();
         double open_price = m_position.PriceOpen();
         double sl_price = m_position.StopLoss();
         double tp_price = m_position.TakeProfit();
         double pips = (m_position.PositionType() == POSITION_TYPE_BUY) ? (current_price - open_price) / _Point : (open_price - current_price) / _Point;

         if (TimeCurrent() - (datetime)m_position.Time() >= MaxPositionDuration_s)
         {
            Log("POZİSYON KAPANIYOR (SÜRE DOLDU): ID: " + (string)m_position.Ticket());
            m_trade.PositionClose(m_position.Ticket());
            continue;
         }

         if (pips >= PartialClosePips && PartialCloseVolume > 0.0 && m_position.Volume() > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
         {
            double close_volume = m_position.Volume() * PartialCloseVolume;
            if (m_trade.PositionClosePartial(m_position.Ticket(), close_volume))
            {
               Log("POZİSYON KISMİ KAPANDI: ID: " + (string)m_position.Ticket());
               if (pips >= BreakEvenPips && sl_price != open_price)
               {
                  if (m_trade.PositionModify(m_position.Ticket(), open_price, tp_price)) Log("POZİSYON BE'YE ÇEKİLDİ: ID: " + (string)m_position.Ticket());
               }
            }
         }

         if (pips >= TrailingStopPips && TrailingStopPips > 0)
         {
            double new_sl = (m_position.PositionType() == POSITION_TYPE_BUY) ? current_price - TrailingStopPips * _Point : current_price + TrailingStopPips * _Point;
            if ((m_position.PositionType() == POSITION_TYPE_BUY && new_sl > sl_price) || (m_position.PositionType() == POSITION_TYPE_SELL && new_sl < sl_price))
            {
               if (m_trade.PositionModify(m_position.Ticket(), new_sl, tp_price)) Log("TRAILING STOP: ID: " + (string)m_position.Ticket() + ", Yeni SL: " + DoubleToString(new_sl, (int)_Digits));
            }
         }
      }
   }
#else
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == _Symbol && OrderMagicNumber() == MagicNumber)
      {
         double current_price = (OrderType() == OP_BUY) ? GetBid() : GetAsk();
         double open_price = OrderOpenPrice();
         double sl_price = OrderStopLoss();
         double pips = (OrderType() == OP_BUY) ? (current_price - open_price) / _Point : (open_price - current_price) / _Point;

         if (TimeCurrent() - OrderOpenTime() >= MaxPositionDuration_s)
         {
            Log("POZİSYON KAPANIYOR (SÜRE DOLDU): Ticket: " + (string)OrderTicket());
            OrderClose(OrderTicket(), OrderLots(), current_price, (int)(MaxSlippagePips / _Point));
            continue;
         }

         if (pips >= PartialClosePips && PartialCloseVolume > 0.0 && OrderLots() > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
         {
            double close_volume = OrderLots() * PartialCloseVolume;
            if (OrderClose(OrderTicket(), close_volume, current_price, (int)(MaxSlippagePips / _Point)))
            {
               Log("POZİSYON KISMİ KAPANDI: Ticket: " + (string)OrderTicket());
               if (pips >= BreakEvenPips && sl_price != open_price)
               {
                  if (OrderModify(OrderTicket(), open_price, open_price, OrderTakeProfit(), 0)) Log("POZİSYON BE'YE ÇEKİLDİ: Ticket: " + (string)OrderTicket());
               }
            }
         }

         if (pips >= TrailingStopPips && TrailingStopPips > 0)
         {
            double new_sl = (OrderType() == OP_BUY) ? current_price - TrailingStopPips * _Point : current_price + TrailingStopPips * _Point;
            if ((OrderType() == OP_BUY && new_sl > sl_price) || (OrderType() == OP_SELL && new_sl < sl_price))
            {
               if (OrderModify(OrderTicket(), open_price, new_sl, OrderTakeProfit(), 0)) Log("TRAILING STOP: Ticket: " + (string)OrderTicket() + ", Yeni SL: " + DoubleToString(new_sl, (int)_Digits));
            }
         }
      }
   }
#endif
}

//--- Manipülasyon Algılama Çekirdek Fonksiyonu
bool DetectManipulationSignal(ENUM_ORDER_TYPE &signal_type)
{
   MqlRates rates[2];
#ifdef __MQL5__
   if (CopyRates(_Symbol, _Period, 0, 2, rates) < 2) return false;
#else
   if (CopyRates(_Symbol, PERIOD_CURRENT, 0, 2, rates) < 2) return false;
#endif

   MqlRates current_candle = rates[0];
   double candle_range = MathAbs(current_candle.high - current_candle.low) / _Point;
   double body_range = MathAbs(current_candle.open - current_candle.close) / _Point;

   if (candle_range > SpikeCandlePips)
   {
      double upper_wick = (current_candle.high - MathMax(current_candle.open, current_candle.close)) / _Point;
      double lower_wick = (MathMin(current_candle.open, current_candle.close) - current_candle.low) / _Point;

      if (upper_wick > SpikeCandlePips && upper_wick > lower_wick * 2)
      {
         Log("MANİPÜLASYON TESPİTİ: Yukarı Spike (Satış Sinyali). İğne: " + DoubleToString(upper_wick, 1) + " Pips.");
         signal_type = ORDER_TYPE_SELL;
         return true;
      }

      if (lower_wick > SpikeCandlePips && lower_wick > upper_wick * 2)
      {
         Log("MANİPÜLASYON TESPİTİ: Aşağı Spike (Alış Sinyali). İğne: " + DoubleToString(lower_wick, 1) + " Pips.");
         signal_type = ORDER_TYPE_BUY;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| MT5 için OnBookEvent Handler                                     |
//+------------------------------------------------------------------+
// Bu fonksiyon, MT5'teki AdvancedManipulationDetectorEA.mq5 dosyasından çağrılır.
#ifdef __MQL5__
// Emir defteri anomalisini OnTick'e iletmek için global değişken
bool BookAnomalyDetected = false;

void OnBookEvent(const string symbol, const MqlBookInfo &book[])
{
   if (symbol != _Symbol) return;
   
   // Emir defteri manipülasyonu (Spoofing/Stop Hunt) tespiti
   static double prev_bid_volume = 0.0;
   static double prev_ask_volume = 0.0;
   
   double current_bid_volume = 0.0;
   double current_ask_volume = 0.0;
   
   // En iyi fiyat (Top of Book) hacmini hesapla (Sadece ilk 5 seviye)
   for (int i = 0; i < ArraySize(book) && i < 5; i++)
   {
      if (book[i].type == BOOK_TYPE_BUY)
      {
         current_bid_volume += book[i].volume;
      }
      else if (book[i].type == BOOK_TYPE_SELL)
      {
         current_ask_volume += book[i].volume;
      }
   }
   
   // Hacim değişim yüzdesi (Ani hacim çekilmesi/eklenmesi)
   double bid_change = (prev_bid_volume > 0) ? MathAbs(current_bid_volume - prev_bid_volume) / prev_bid_volume : 0.0;
   double ask_change = (prev_ask_volume > 0) ? MathAbs(current_ask_volume - prev_ask_volume) / prev_ask_volume : 0.0;
   
   // %50'den fazla ani hacim değişimi (Spoofing/Stop Hunt denemesi)
   if (bid_change > 0.50 || ask_change > 0.50)
   {
      Log("EMİR DEFTERİ ANOMALİSİ TESPİT EDİLDİ: Bid Hacim Değişimi: " + DoubleToString(bid_change*100, 0) + "%" + 
          ", Ask Hacim Değişimi: " + DoubleToString(ask_change*100, 0) + "%");
          
      // Anomaliyi OnTick'e ilet
      BookAnomalyDetected = true;
   }
   else
   {
      BookAnomalyDetected = false;
   }
   
   prev_bid_volume = current_bid_volume;
   prev_ask_volume = current_ask_volume;
}
#endif

//+------------------------------------------------------------------+
//| Ana Olay Fonksiyonları (Wrapper)                                 |
//+------------------------------------------------------------------+

int OnInit_Common()
{
#ifdef __MQL5__
   if (!m_trade.Init()) { Log("CTrade başlatılamadı."); return(INIT_FAILED); }
   if (!MarketBookAdd(_Symbol)) { Log("UYARI: Emir Defteri aboneliği başarısız oldu."); }
#endif
   Log("Expert Advisor Başlatıldı. ID: " + Expert_ID);
   return(INIT_SUCCEEDED);
}

void OnDeinit_Common(const int reason)
{
   Log("Expert Advisor Kapatılıyor. Sebep: " + (string)reason);
   Comment("");
#ifdef __MQL5__
   MarketBookRelease(_Symbol);
#endif
}

void OnTick_Common()
{
   // Görsel Panel, Pozisyon Yönetimi, vb. buraya gelecek.
   ManagePositions();

   // Sinyal kontrolü ve işlem açma
#ifdef __MQL5__
   if (PositionsTotal() == 0)
#else
   if (OrdersTotal() == 0)
#endif
   {
      ENUM_ORDER_TYPE signal = WRONG_VALUE;
      if (DetectManipulationSignal(signal))
      {
         double lot = CalculateLotSize(StopLossPips);
         double price = (signal == ORDER_TYPE_BUY) ? GetAsk() : GetBid();
         OpenTrade(signal, lot, price, StopLossPips, TakeProfitPips, "Manipulation_Counter");
      }
   }
}

