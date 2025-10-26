//+------------------------------------------------------------------+
//|                 AdvancedManipulationDetector_MT4.mqh             |
//|                      Copyright 2024, Manus AI                    |
//|                                  https://manus.im                |
//| MT4 Platformuna Özel Fonksiyonlar ve Implementasyonlar           |
//+------------------------------------------------------------------+
#property copyright "Manus AI"
#property link      "https://manus.im"
#property version   "1.04"
#property strict

// Ortak kodları dahil et
#include "AdvancedManipulationDetector_Common.mqh"

//+------------------------------------------------------------------+
//| MT4'e Özel Yapılar ve Fonksiyonlar                               |
//+------------------------------------------------------------------+

// MT4'te MqlRates yapısı taklidi
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

//--- Platformdan bağımsız fiyat alma (MT4)
double GetAsk()
{
   return MarketInfo(Symbol(), MODE_ASK);
}

double GetBid()
{
   return MarketInfo(Symbol(), MODE_BID);
}

//--- Lot büyüklüğünü hesaplama (MT4)
double CalculateLotSize(int sl_pips)
{
   if (RiskPercent <= 0.0) return FixedLotSize;

   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_balance * (RiskPercent / 100.0);
   double sl_distance_points = sl_pips * Point;

   // MT4'te Tick Value ve Tick Size hesaplaması biraz farklıdır.
   // Basitleştirilmiş formül:
   double lot_size = risk_amount / (sl_distance_points * MarketInfo(Symbol(), MODE_TICKVALUE));

   double lot_step = MarketInfo(Symbol(), MODE_LOTSTEP);
   lot_size = NormalizeDouble(MathFloor(lot_size / lot_step) * lot_step, 2);

   double min_lot = MarketInfo(Symbol(), MODE_MINLOT);
   double max_lot = MarketInfo(Symbol(), MODE_MAXLOT);
   lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));

   Log("Lot Hesaplandı (MT4): Risk: " + DoubleToString(risk_amount, 2) + ", SL Pips: " + (string)sl_pips + ", Lot: " + DoubleToString(lot_size, 2));
   return lot_size;
}

//--- İşlem açma fonksiyonu (MT4)
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

   int mt4_order_type = (order_type == ORDER_TYPE_BUY) ? OP_BUY : OP_SELL;
   
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
   Log("İşlem Açılıyor (MT4): " + order_type_str + ", Lot: " + DoubleToString(lot, 2) + ", Fiyat: " + DoubleToString(price, Digits) + ", SL: " + DoubleToString(sl_price, Digits) + ", TP: " + DoubleToString(tp_price, Digits));

   int ticket = OrderSend(Symbol(), mt4_order_type, lot, price, (int)(MaxSlippagePips / Point), sl_price, tp_price, comment, MagicNumber, 0, clrNONE);
   if (ticket < 0)
   {
      int error_code = GetLastError();
      Log("HATA: OrderSend başarısız oldu. Hata Kodu: " + (string)error_code);
      if (error_code == 138 || error_code == 4060) ServerBusyMode = true; // Requote or Trade context busy
      return false;
   }
   if (ServerBusyMode) ServerBusyMode = false;
   Log("İŞLEM BAŞARILI (MT4): Ticket: " + (string)ticket);
   return true;
}

//--- Pozisyon yönetimi (MT4)
void ManagePositions()
{
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
      {
         double current_price = (OrderType() == OP_BUY) ? GetBid() : GetAsk();
         double open_price = OrderOpenPrice();
         double sl_price = OrderStopLoss();
         double tp_price = OrderTakeProfit();
         double pips = (OrderType() == OP_BUY) ? (current_price - open_price) / Point : (open_price - current_price) / Point;

         // Süre kontrolü
         if (TimeCurrent() - OrderOpenTime() >= MaxPositionDuration_s)
         {
            Log("POZİSYON KAPANIYOR (SÜRE DOLDU): Ticket: " + (string)OrderTicket());
            OrderClose(OrderTicket(), OrderLots(), current_price, (int)(MaxSlippagePips / Point));
            continue;
         }

         // Kısmi kapama
         if (PartialClosePips > 0 && pips >= PartialClosePips)
         {
            double close_volume = NormalizeDouble(OrderLots() * PartialCloseVolume, 2);
            if (close_volume > 0 && OrderLots() - close_volume >= MarketInfo(Symbol(), MODE_MINLOT))
            {
               Log("POZİSYON KISMİ KAPANIYOR: Ticket: " + (string)OrderTicket() + ", Hacim: " + DoubleToString(close_volume, 2));
               OrderClose(OrderTicket(), close_volume, current_price, (int)(MaxSlippagePips / Point));
            }
         }

         // Break-Even
         if (BreakEvenPips > 0 && pips >= BreakEvenPips && sl_price != open_price)
         {
            Log("POZİSYON BREAK-EVEN'A ÇEKİLİYOR: Ticket: " + (string)OrderTicket());
            OrderModify(OrderTicket(), open_price, open_price, tp_price, 0);
         }

         // Trailing Stop
         if (TrailingStopPips > 0 && pips >= TrailingStopPips)
         {
            double new_sl = 0.0;
            if (OrderType() == OP_BUY)
            {
               new_sl = current_price - TrailingStopPips * Point;
               if (new_sl > sl_price)
               {
                  Log("TRAILING STOP GÜNCELLENDİ (BUY): Ticket: " + (string)OrderTicket() + ", Yeni SL: " + DoubleToString(new_sl, Digits));
                  OrderModify(OrderTicket(), open_price, new_sl, tp_price, 0);
               }
            }
            else // SELL
            {
               new_sl = current_price + TrailingStopPips * Point;
               if (new_sl < sl_price && new_sl > 0) // SL sıfırdan büyük olmalı
               {
                  Log("TRAILING STOP GÜNCELLENDİ (SELL): Ticket: " + (string)OrderTicket() + ", Yeni SL: " + DoubleToString(new_sl, Digits));
                  OrderModify(OrderTicket(), open_price, new_sl, tp_price, 0);
               }
            }
         }
      }
   }
}

//--- Manipülasyon sinyalini tespit etme (MT4)
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

//--- Skor tablosunu güncelleme (MT4)
void UpdateTradeScore(string symbol, double profit, bool is_win)
{
   // MT4'te HistorySelect() ile işlem geçmişine erişim ve skor güncelleme mantığı buraya gelir.
   // Basit bir yer tutucu bırakıyorum.
   Log("Skor Güncellendi (MT4): Sembol: " + symbol + ", Kâr: " + DoubleToString(profit, 2));
}

//--- Ana Olay Fonksiyonları (MT4)

int OnInit_MT4()
{
   Log("EA Başlatıldı (MT4): " + Expert_ID + " v" + (string)Version());
   return(INIT_SUCCEEDED);
}

void OnDeinit_MT4(const int reason)
{
   Log("EA Durduruldu (MT4). Neden: " + (string)reason);
}

void OnTick_MT4()
{
   if (!IsTradingTime() || ServerBusyMode) return;

   ManagePositions();

   if (OrdersTotal() > 0) return;

   ENUM_ORDER_TYPE signal = DetectManipulationSignal(Point, Digits);
   if (signal != (ENUM_ORDER_TYPE)-1)
   {
      double lot = CalculateLotSize(StopLossPips);
      double price = (signal == ORDER_TYPE_BUY) ? GetAsk() : GetBid();
      OpenTrade(signal, lot, price, StopLossPips, TakeProfitPips, "AMD Signal");
   }
}

