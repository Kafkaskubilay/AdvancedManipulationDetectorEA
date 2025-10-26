//+------------------------------------------------------------------+
//|                 AdvancedManipulationDetector_MT5.mqh             |
//|                      Copyright 2024, Manus AI                    |
//|                                  https://manus.im                |
//| MT5 Platformuna Özel Fonksiyonlar ve Implementasyonlar           |
//+------------------------------------------------------------------+
#property copyright "Manus AI"
#property link      "https://manus.im"
#property version   "1.04"
#property strict

// Ortak kodları dahil et
#include "AdvancedManipulationDetector_Common.mqh"

// MT5 Gerekli Kütüphaneler
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| MT5'e Özel Global Değişkenler ve Sınıflar (Ana Dosyada Tanımlanır)|
//+------------------------------------------------------------------+

// Emir defteri anomalisini OnTick'e iletmek için global değişken (HandleBookEvent'te kullanılır)
extern bool BookAnomalyDetected;

// CTrade ve CPositionInfo sınıfları için fonksiyon deklarasyonları
// Bunlar ana dosyada tanımlanmalıdır.
// CTrade& GetTrade();
// CPositionInfo& GetPosition();

//+------------------------------------------------------------------+
//| MT5'e Özel Fonksiyonlar                                          |
//+------------------------------------------------------------------+

//--- Platformdan bağımsız fiyat alma (MT5)
double GetAsk()
{
   return SymbolInfoDouble(Symbol(), SYMBOL_ASK);
}

double GetBid()
{
   return SymbolInfoDouble(Symbol(), SYMBOL_BID);
}

//--- Lot büyüklüğünü hesaplama (MT5)
double CalculateLotSize(int sl_pips)
{
   if (RiskPercent <= 0.0) return FixedLotSize;

   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_balance * (RiskPercent / 100.0);
   double sl_distance_points = sl_pips * Point;

   double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   if (tick_size == 0) return 0.01; // Bölme hatasını önle

   double value_per_point = tick_value / tick_size;
   double lot = risk_amount / (sl_distance_points * value_per_point);

   double lot_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / lot_step) * lot_step;

   double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   lot = MathMax(min_lot, MathMin(max_lot, lot));

   Log("Lot Hesaplandı (MT5): Risk: " + DoubleToString(risk_amount, 2) + ", SL Pips: " + (string)sl_pips + ", Lot: " + DoubleToString(lot, 2));
   return lot;
}

//--- İşlem açma fonksiyonu (MT5)
bool OpenTrade(ENUM_ORDER_TYPE order_type, double lot, double price, int sl_pips, int tp_pips, string comment)
{
   if (lot <= 0) 
   {
      Log("HATA: Lot büyüklüğü sıfır veya negatif. İşlem açılamadı.");
      return false;
   }

   double current_spread_pips = (GetAsk() - GetBid()) / Point;
   if (current_spread_pips > MaxSpreadPips)
   {
      Log("İŞLEM İPTAL: Spread çok yüksek (" + DoubleToString(current_spread_pips, 1) + " Pips). Max limit: " + (string)MaxSpreadPips + " Pips.");
      return false;
   }

   double sl_price = 0.0;
   double tp_price = 0.0;

   if (order_type == ORDER_TYPE_BUY)
   {
      sl_price = price - sl_pips * Point;
      tp_price = price + tp_pips * Point;
   }
   else if (order_type == ORDER_TYPE_SELL)
   {
      sl_price = price + sl_pips * Point;
      tp_price = price - tp_pips * Point;
   }

   sl_price = NormalizeDouble(sl_price, Digits);
   tp_price = NormalizeDouble(tp_price, Digits);

   string order_type_str = (order_type == ORDER_TYPE_BUY) ? "BUY" : "SELL";
   Log("İşlem Açılıyor (MT5): " + order_type_str + ", Lot: " + DoubleToString(lot, 2) + ", Fiyat: " + DoubleToString(price, Digits) + ", SL: " + DoubleToString(sl_price, Digits) + ", TP: " + DoubleToString(tp_price, Digits));

   MqlTradeRequest request={0};
   MqlTradeResult  result={0};

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = Symbol();
   request.volume   = lot;
   request.type     = (ENUM_ORDER_TYPE)order_type; // MT5'te ENUM_ORDER_TYPE'a cast etme
   request.price    = price;
   request.sl       = sl_price;
   request.tp       = tp_price;
   request.deviation= (int)(MaxSlippagePips * Point);
   request.magic    = MagicNumber;
   request.comment  = comment;

   if (!GetTrade().OrderSend(request, result))
   {
      Log("HATA: OrderSend başarısız oldu. Hata Kodu: " + EnumToString(result.retcode));
      if (result.retcode == TRADE_RETCODE_NO_CONNECTION || result.retcode == TRADE_RETCODE_SERVER_BUSY) ServerBusyMode = true;
      return false;
   }
   if (ServerBusyMode) ServerBusyMode = false;
   Log("İŞLEM BAŞARILI (MT5): Pozisyon ID: " + (string)result.deal + ", Sonuç Kodu: " + EnumToString(result.retcode));
   return true;
}

//--- Pozisyon yönetimi (MT5)
void ManagePositions()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (GetPosition().SelectByIndex(i) && GetPosition().Symbol() == Symbol() && GetPosition().Magic() == MagicNumber)
      {
         double current_price = (GetPosition().PositionType() == POSITION_TYPE_BUY) ? GetBid() : GetAsk();
         double open_price = GetPosition().PriceOpen();
         double sl_price = GetPosition().StopLoss();
         double tp_price = GetPosition().TakeProfit();
         double pips = (GetPosition().PositionType() == POSITION_TYPE_BUY) ? (current_price - open_price) / Point : (open_price - current_price) / Point;

         // Süre kontrolü
         if ((long)TimeCurrent() - (long)GetPosition().Time() >= MaxPositionDuration_s)
         {
            Log("POZİSYON KAPANIYOR (SÜRE DOLDU): ID: " + (string)GetPosition().Ticket());
            GetTrade().PositionClose(GetPosition().Ticket());
            continue;
         }

         // Kısmi kapama
         if (PartialClosePips > 0 && pips >= PartialClosePips)
         {
            double close_volume = NormalizeDouble(GetPosition().Volume() * PartialCloseVolume, 2);
            if (close_volume > 0)
            {
               Log("POZİSYON KISMİ KAPANIYOR: ID: " + (string)GetPosition().Ticket() + ", Hacim: " + DoubleToString(close_volume, 2));
               GetTrade().PositionClose(GetPosition().Ticket(), close_volume);
            }
         }

         // Break-Even
         if (BreakEvenPips > 0 && pips >= BreakEvenPips && sl_price != open_price)
         {
            Log("POZİSYON BREAK-EVEN'A ÇEKİLİYOR: ID: " + (string)GetPosition().Ticket());
            GetTrade().PositionModify(GetPosition().Ticket(), open_price, tp_price);
         }

         // Trailing Stop
         if (TrailingStopPips > 0 && pips >= TrailingStopPips)
         {
            double new_sl = 0.0;
            if (GetPosition().PositionType() == POSITION_TYPE_BUY)
            {
               new_sl = current_price - TrailingStopPips * Point;
               if (new_sl > sl_price)
               {
                  Log("TRAILING STOP GÜNCELLENDİ (BUY): ID: " + (string)GetPosition().Ticket() + ", Yeni SL: " + DoubleToString(new_sl, Digits));
                  GetTrade().PositionModify(GetPosition().Ticket(), new_sl, tp_price);
               }
            }
            else // SELL
            {
               new_sl = current_price + TrailingStopPips * Point;
               if (new_sl < sl_price)
               {
                  Log("TRAILING STOP GÜNCELLENDİ (SELL): ID: " + (string)GetPosition().Ticket() + ", Yeni SL: " + DoubleToString(new_sl, Digits));
                  GetTrade().PositionModify(GetPosition().Ticket(), new_sl, tp_price);
               }
            }
         }
      }
   }
}

//--- Manipülasyon sinyalini tespit etme (MT5)
ENUM_ORDER_TYPE DetectManipulationSignal(double point_value, int digits)
{
   MqlRates rates[2];
   if (CopyRates(Symbol(), PERIOD_CURRENT, 0, 2, rates) < 2) return((ENUM_ORDER_TYPE)-1);

   double candle_high = rates[1].high;
   double candle_low = rates[1].low;
   double candle_open = rates[1].open;
   double candle_close = rates[1].close;
   double candle_body = MathAbs(candle_open - candle_close);
   double upper_wick = candle_high - MathMax(candle_open, candle_close);
   double lower_wick = MathMin(candle_open, candle_close) - candle_low;

   // İğneli mum tespiti (Spike)
   if (upper_wick > SpikeCandlePips * point_value && upper_wick > candle_body * 2)
   {
      Log("SİNYAL: Yukarı Spike Mumu Tespit Edildi. İğne: " + DoubleToString(upper_wick / point_value, 1) + " Pips.");
      return ORDER_TYPE_SELL;
   }
   if (lower_wick > SpikeCandlePips * point_value && lower_wick > candle_body * 2)
   {
      Log("SİNYAL: Aşağı Spike Mumu Tespit Edildi. İğne: " + DoubleToString(lower_wick / point_value, 1) + " Pips.");
      return ORDER_TYPE_BUY;
   }

   return((ENUM_ORDER_TYPE)-1);
}

//--- Skor tablosunu güncelleme (MT5)
void UpdateTradeScore(string symbol, double profit, bool is_win)
{
   // MT5'te HistorySelect() ile işlem geçmişine erişim ve skor güncelleme mantığı buraya gelir.
   // Basit bir yer tutucu bırakıyorum.
   Log("Skor Güncellendi (MT5): Sembol: " + symbol + ", Kâr: " + DoubleToString(profit, 2));
}

//+------------------------------------------------------------------+
//| MT5 Ana Olay Fonksiyonları                                       |
//+------------------------------------------------------------------+

// Ana dosyada tanımlanan global değişkenlere erişim için
extern CTrade m_trade;
extern CPositionInfo m_position;

CTrade& GetTrade() { return m_trade; }
CPositionInfo& GetPosition() { return m_position; }

int OnInit_MT5()
{
   GetTrade().SetExpertMagicNumber(MagicNumber);
   GetTrade().SetMarginMode();
   GetTrade().SetTypeFillingBySymbol(Symbol());
   SymbolSelect(Symbol(), true);
   // Emir defteri olaylarını almak için abone ol
   MarketBookAdd(Symbol());
   
   Log("EA Başlatıldı (MT5): " + Expert_ID + " v" + (string)Version());
   return(INIT_SUCCEEDED);
}

void OnDeinit_MT5(const int reason)
{
   // Emir defteri aboneliğini kaldır
   MarketBookRelease(Symbol());
   Log("EA Durduruldu (MT5). Neden: " + (string)reason);
}

void OnTick_MT5()
{
   if (!IsTradingTime() || ServerBusyMode) return;

   ManagePositions();

   if (PositionsTotal() > 0) return;

   ENUM_ORDER_TYPE signal = DetectManipulationSignal(Point, Digits);
   if (signal != (ENUM_ORDER_TYPE)-1)
   {
      // MT5'e özel Emir Defteri Anomali Kontrolü
      if (BookAnomalyDetected)
      {
         Log("EMİR DEFTERİ ANOMALİSİ ONAYLANDI. Sinyal Güçlendirildi.");
      }
      
      double lot = CalculateLotSize(StopLossPips);
      double price = (signal == ORDER_TYPE_BUY) ? GetAsk() : GetBid();
      OpenTrade(signal, lot, price, StopLossPips, TakeProfitPips, "AMD Signal");
   }
}

//+------------------------------------------------------------------+
//| MT5 OnBookEvent Handler                                          |
//+------------------------------------------------------------------+
void HandleBookEvent(const string symbol, const MqlBookInfo &book[])
{
   if (symbol != Symbol()) return;
   
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

