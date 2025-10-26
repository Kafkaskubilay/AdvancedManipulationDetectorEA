//+------------------------------------------------------------------+
//|                 AdvancedManipulationDetector_MT4.mqh             |
//|                      Copyright 2024, Manus AI                    |
//|                                  https://manus.im                |
//| MT4 Platformuna Özel Fonksiyonlar ve Implementasyonlar (v1.07)   |
//+------------------------------------------------------------------+
#property copyright "Manus AI"
#property link      "https://manus.im"
#property version   "1.07"
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
double GetAsk(string symbol)
{
   return MarketInfo(symbol, MODE_ASK);
}

double GetBid(string symbol)
{
   return MarketInfo(symbol, MODE_BID);
}

//--- Lot büyüklüğünü hesaplama (MT4)
double CalculateLotSize(string symbol, int sl_pips)
{
   if (RiskPercent <= 0.0) return FixedLotSize;

   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_balance * (RiskPercent / 100.0);
   double sl_distance_points = sl_pips * MarketInfo(symbol, MODE_POINT);

   double lot_size = risk_amount / (sl_distance_points * MarketInfo(symbol, MODE_TICKVALUE));

   double lot_step = MarketInfo(symbol, MODE_LOTSTEP);
   lot_size = NormalizeDouble(MathFloor(lot_size / lot_step) * lot_step, 2);

   double min_lot = MarketInfo(symbol, MODE_MINLOT);
   double max_lot = MarketInfo(symbol, MODE_MAXLOT);
   lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));

   Log(symbol, "Lot Hesaplandı (MT4): Risk: " + DoubleToString(risk_amount, 2) + ", SL Pips: " + (string)sl_pips + ", Lot: " + DoubleToString(lot_size, 2));
   return lot_size;
}

//--- İşlem açma fonksiyonu (MT4) - Retry eklendi
bool OpenTrade(string symbol, ENUM_ORDER_TYPE order_type, double lot, double price, int sl_pips, int tp_pips, string comment)
{
   if (lot <= 0) 
   {
      Log(symbol, "HATA: Lot büyüklüğü sıfır veya negatif. İşlem açılamadı.");
      return false;
   }

   double point = MarketInfo(symbol, MODE_POINT);
   int digits = MarketInfo(symbol, MODE_DIGITS);
   
   double current_spread_pips = (GetAsk(symbol) - GetBid(symbol)) / point;
   if (current_spread_pips > MaxSpreadPips)
   {
      Log(symbol, "İŞLEM İPTAL: Spread çok yüksek (" + DoubleToString(current_spread_pips, 1) + " Pips). Max limit: " + (string)MaxSpreadPips + " Pips.");
      return false;
   }

   int mt4_order_type = (order_type == ORDER_TYPE_BUY) ? OP_BUY : OP_SELL;
   
   double sl_price = 0.0;
   double tp_price = 0.0;

   if (order_type == ORDER_TYPE_BUY)
   {
      sl_price = price - sl_pips * point;
      tp_price = price + tp_pips * point;
   }
   else if (order_type == ORDER_TYPE_SELL)
   {
      sl_price = price + sl_pips * point;
      tp_price = price - tp_pips * point;
   }

   sl_price = NormalizeDouble(sl_price, digits);
   tp_price = NormalizeDouble(tp_price, digits);

   string order_type_str = (order_type == ORDER_TYPE_BUY) ? "BUY" : "SELL";
   Log(symbol, "İşlem Açılıyor (MT4): " + order_type_str + ", Lot: " + DoubleToString(lot, 2) + ", Fiyat: " + DoubleToString(price, digits) + ", SL: " + DoubleToString(sl_price, digits) + ", TP: " + DoubleToString(tp_price, digits));

   int retries = 3;
   while (retries > 0)
   {
      int ticket = OrderSend(symbol, mt4_order_type, lot, price, (int)(MaxSlippagePips / point), sl_price, tp_price, comment, MagicNumber, 0, clrNONE);
      if (ticket > 0)
      {
         if (ServerBusyMode) ServerBusyMode = false;
         Log(symbol, "İŞLEM BAŞARILI (MT4): Ticket: " + (string)ticket);
         return true;
      }
      
      int error_code = GetLastError();
      Log(symbol, "HATA: OrderSend başarısız oldu. Hata Kodu: " + (string)error_code + ". Tekrar deneniyor... (" + (string)retries + " kaldı)");
      
      if (error_code == 138 || error_code == 4060) // Requote or Trade context busy
      {
         retries--;
         Sleep(100); // Kısa bekleme
         price = (order_type == ORDER_TYPE_BUY) ? GetAsk(symbol) : GetBid(symbol); // Yeni fiyat al
         continue;
      }
      
      if (error_code == 4) // Trade server busy
      {
         ServerBusyMode = true;
         Log(symbol, "SUNUCU MEŞGUL. Bekleme moduna geçiliyor.");
         return false;
      }
      
      // Diğer hatalar için çık
      break;
   }
   
   return false;
}

//--- Pozisyon yönetimi (MT4)
void ManagePositions(string symbol)
{
   double point = MarketInfo(symbol, MODE_POINT);
   int digits = MarketInfo(symbol, MODE_DIGITS);
   
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == symbol && OrderMagicNumber() == MagicNumber)
      {
         double current_price = (OrderType() == OP_BUY) ? GetBid(symbol) : GetAsk(symbol);
         double open_price = OrderOpenPrice();
         double sl_price = OrderStopLoss();
         double tp_price = OrderTakeProfit();
         double pips = (OrderType() == OP_BUY) ? (current_price - open_price) / point : (open_price - current_price) / point;

         // Süre kontrolü
         if (TimeCurrent() - OrderOpenTime() >= MaxPositionDuration_s)
         {
            Log(symbol, "POZİSYON KAPANIYOR (SÜRE DOLDU): Ticket: " + (string)OrderTicket());
            OrderClose(OrderTicket(), OrderLots(), current_price, (int)(MaxSlippagePips / point));
            continue;
         }

         // Kısmi kapama
         if (PartialClosePips > 0 && pips >= PartialClosePips)
         {
            double close_volume = NormalizeDouble(OrderLots() * PartialCloseVolume, 2);
            if (close_volume > 0 && OrderLots() - close_volume >= MarketInfo(symbol, MODE_MINLOT))
            {
               Log(symbol, "POZİSYON KISMİ KAPANIYOR: Ticket: " + (string)OrderTicket() + ", Hacim: " + DoubleToString(close_volume, 2));
               OrderClose(OrderTicket(), close_volume, current_price, (int)(MaxSlippagePips / point));
            }
         }

         // Break-Even
         if (BreakEvenPips > 0 && pips >= BreakEvenPips && sl_price != open_price)
         {
            Log(symbol, "POZİSYON BREAK-EVEN'A ÇEKİLİYOR: Ticket: " + (string)OrderTicket());
            OrderModify(OrderTicket(), open_price, open_price, tp_price, 0);
         }

         // Trailing Stop
         if (TrailingStopPips > 0 && pips >= TrailingStopPips)
         {
            double new_sl = 0.0;
            if (OrderType() == OP_BUY)
            {
               new_sl = current_price - TrailingStopPips * point;
               if (new_sl > sl_price)
               {
                  Log(symbol, "TRAILING STOP GÜNCELLENDİ (BUY): Ticket: " + (string)OrderTicket() + ", Yeni SL: " + DoubleToString(new_sl, digits));
                  OrderModify(OrderTicket(), open_price, new_sl, tp_price, 0);
               }
            }
            else // SELL
            {
               new_sl = current_price + TrailingStopPips * point;
               if (new_sl < sl_price && new_sl > 0) // SL sıfırdan büyük olmalı
               {
                  Log(symbol, "TRAILING STOP GÜNCELLENDİ (SELL): Ticket: " + (string)OrderTicket() + ", Yeni SL: " + DoubleToString(new_sl, digits));
                  OrderModify(OrderTicket(), open_price, new_sl, tp_price, 0);
               }
            }
         }
      }
   }
}

//--- Manipülasyon sinyalini tespit etme (MT4)
ENUM_ORDER_TYPE DetectManipulationSignal(string symbol)
{
   double point = MarketInfo(symbol, MODE_POINT);
   int digits = MarketInfo(symbol, MODE_DIGITS);
   
   MqlRates rates[2];
   if (CopyRates(symbol, PERIOD_CURRENT, 0, 2, rates) < 2) return((ENUM_ORDER_TYPE)-1);

   double candle_high = rates[1].high;
   double candle_low = rates[1].low;
   double candle_open = rates[1].open;
   double candle_close = rates[1].close;
   double candle_body = MathAbs(candle_open - candle_close);
   double upper_wick = candle_high - MathMax(candle_open, candle_close);
   double lower_wick = MathMin(candle_open, candle_close) - candle_low;
   
   // ATR (Average True Range) ile dinamik eşik hesaplama
   double atr_value = iATR(symbol, PERIOD_M1, 14, 1); // 1 dakikalık ATR
   double dynamic_spike_threshold = (Use_ATR_Threshold && atr_value > 0) ? atr_value * ATR_Multiplier : SpikeCandlePips * point;

   int signal_count = 0;
   ENUM_ORDER_TYPE final_signal = (ENUM_ORDER_TYPE)-1;

   // 1. İğneli Mum Tespiti (Spike) - Dinamik Eşik Kullanımı
   if (upper_wick > dynamic_spike_threshold && upper_wick > candle_body * 2)
   {
      Log(symbol, "FİLTRE 1/3: Yukarı Spike Mumu Tespit Edildi. İğne: " + DoubleToString(upper_wick / point, 1) + " Pips.");
      signal_count++;
      final_signal = ORDER_TYPE_SELL;
   }
   else if (lower_wick > dynamic_spike_threshold && lower_wick > candle_body * 2)
   {
      Log(symbol, "FİLTRE 1/3: Aşağı Spike Mumu Tespit Edildi. İğne: " + DoubleToString(lower_wick / point, 1) + " Pips.");
      signal_count++;
      final_signal = ORDER_TYPE_BUY;
   }

   // 2. Hacim Anomalisi Tespiti
   long current_volume = rates[1].tick_volume;
   long avg_volume = 0;
   
   // Son 10 mumun ortalama hacmini hesapla
   MqlRates history_rates[11];
   if (CopyRates(symbol, PERIOD_M1, 1, 10, history_rates) == 10)
   {
      for (int i = 0; i < 10; i++)
      {
         avg_volume += history_rates[i].tick_volume;
      }
      avg_volume /= 10;
   }
   
   if ((double)current_volume > (double)avg_volume * SpikeVolumeThreshold)
   {
      Log(symbol, "FİLTRE 2/3: Hacim Anomalisi Tespiti. Güncel Hacim: " + (string)current_volume + " (Ort: " + (string)avg_volume + ")");
      signal_count++;
   }
   
   // Güçlü Sinyal Onayı: En az 2 filtre geçtiyse sinyal ver
   if (signal_count >= 2)
   {
      Log(symbol, "GÜÇLÜ SİNYAL ONAYI: " + (string)signal_count + "/3 filtre geçti. Sinyal: " + (final_signal == ORDER_TYPE_BUY ? "BUY" : "SELL"));
      return final_signal;
   }

   return((ENUM_ORDER_TYPE)-1);
}

//--- Ana Olay Fonksiyonları (MT4)

int OnInit_MT4()
{
   Log("", "EA Başlatıldı (MT4): " + Expert_ID + " v" + (string)Version());
   return(INIT_SUCCEEDED);
}

void OnDeinit_MT4(const int reason)
{
   Log("", "EA Durduruldu (MT4). Neden: " + (string)reason);
}

void OnTick_MT4()
{
   if (!IsTradingTime() || ServerBusyMode) return;

   string symbols[];
   int count = StringSplit(Symbols_List, ',', symbols);
   
   for (int i = 0; i < count; i++)
   {
      string symbol = symbols[i];
      
      // Sembolü seç
      if (!MarketInfo(symbol, MODE_POINT)) continue;
      
      ManagePositions(symbol);

      // Sadece pozisyon yoksa sinyal ara
      if (OrdersTotal() > 0) continue;

      ENUM_ORDER_TYPE signal = DetectManipulationSignal(symbol);
      if (signal != (ENUM_ORDER_TYPE)-1)
      {
         double lot = CalculateLotSize(symbol, StopLossPips);
         double price = (signal == ORDER_TYPE_BUY) ? GetAsk(symbol) : GetBid(symbol);
         OpenTrade(symbol, signal, lot, price, StopLossPips, TakeProfitPips, "AMD Signal");
      }
   }
}

