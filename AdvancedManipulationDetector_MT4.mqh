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

// MT4 Gerekli Kütüphaneler
#include <Trade\Trade.mqh>

// Ortak kodları dahil et
#include "AdvancedManipulationDetector_Common.mqh"

// MT4'te ENUM_ORDER_TYPE yok, taklit edelim
#ifndef __MQL5__
#define ORDER_TYPE_BUY  OP_BUY
#define ORDER_TYPE_SELL OP_SELL
#endif

//+------------------------------------------------------------------+
//| MT4'e Özel Global Değişkenler                                    |
//+------------------------------------------------------------------+
// MT4'te CTrade sınıfı yok, MQL4 Trade fonksiyonlarını kullanacağız.
// MT4'te CPositionInfo sınıfı yok, MQL4 PositionSelect/PositionGetInteger kullanacağız.

//+------------------------------------------------------------------+
//| MT4'e Özel Fonksiyonlar                                          |
//+------------------------------------------------------------------+

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

   double equity = AccountInfoDouble(ACCOUNT_BALANCE); // MT4'te ACCOUNT_EQUITY yerine BALANCE kullanmak daha yaygın
   double risk_amount = equity * (RiskPercent / 100.0);
   
   double point = MarketInfo(symbol, MODE_POINT);
   double tick_value = MarketInfo(symbol, MODE_TICKVALUE);
   
   // Lot hesaplama formülü
   double lot = risk_amount / (sl_pips * point * tick_value);

   double min_lot = MarketInfo(symbol, MODE_MINLOT);
   double max_lot = MarketInfo(symbol, MODE_MAXLOT);
   double step_lot = MarketInfo(symbol, MODE_LOTSTEP);
   
   if (step_lot > 0) lot = NormalizeDouble(MathRound(lot / step_lot) * step_lot, 2);
   
   lot = MathMax(min_lot, MathMin(max_lot, lot));

   Log(symbol, "Lot Hesaplandı (MT4): Risk: " + DoubleToString(risk_amount, 2) + ", SL Pips: " + (string)sl_pips + ", Lot: " + DoubleToString(lot, 2));
   return lot;
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
   int digits = (int)MarketInfo(symbol, MODE_DIGITS);
   
   double current_spread_pips = (GetAsk(symbol) - GetBid(symbol)) / point;
   if (current_spread_pips > MaxSpreadPips * point) // MT4'te spread point cinsinden, pips değil
   {
      Log(symbol, "İŞLEM İPTAL: Spread çok yüksek (" + DoubleToString(current_spread_pips/point, 1) + " Pips). Max limit: " + (string)MaxSpreadPips + " Pips.");
      return false;
   }
   
   int retries = 3;
   while (retries > 0)
   {
      int ticket = -1;
      double sl_price = 0.0;
      double tp_price = 0.0;
      
      if (order_type == ORDER_TYPE_BUY)
      {
         sl_price = NormalizeDouble(price - sl_pips * point, digits);
         tp_price = NormalizeDouble(price + tp_pips * point, digits);
         ticket = OrderSend(symbol, OP_BUY, lot, price, MaxSlippagePips, sl_price, tp_price, comment, MagicNumber, 0, clrGreen);
      }
      else
      {
         sl_price = NormalizeDouble(price + sl_pips * point, digits);
         tp_price = NormalizeDouble(price - tp_pips * point, digits);
         ticket = OrderSend(symbol, OP_SELL, lot, price, MaxSlippagePips, sl_price, tp_price, comment, MagicNumber, 0, clrRed);
      }

      if (ticket > 0)
      {
         if (ServerBusyMode) ServerBusyMode = false;
         Log(symbol, "İŞLEM BAŞARILI (MT4): Ticket: " + (string)ticket);
         return true;
      }
      else
      {
         int error_code = GetLastError();
         Log(symbol, "HATA: OrderSend başarısız oldu. Hata Kodu: " + (string)error_code + ". Tekrar deneniyor... (" + (string)retries + " kaldı)");
         
         if (error_code == 138 || error_code == 4060) // Requote veya Trade Context Busy
         {
            retries--;
            Sleep(100); // Kısa bekleme
            price = (order_type == ORDER_TYPE_BUY) ? GetAsk(symbol) : GetBid(symbol); // Yeni fiyat al
            continue;
         }
         
         if (error_code == 4) // Server Busy
         {
            ServerBusyMode = true;
            Log(symbol, "SUNUCU MEŞGUL. Bekleme moduna geçiliyor.");
            return false;
         }
         
         // Diğer hatalar için çık
         break;
      }
   }
   
   return false;
}

//--- Pozisyon yönetimi (MT4)
void ManagePositions(string symbol)
{
   double point = MarketInfo(symbol, MODE_POINT);
   int digits = (int)MarketInfo(symbol, MODE_DIGITS);
   
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if (OrderSymbol() == symbol && OrderMagicNumber() == MagicNumber)
         {
            double current_price = (OrderType() == OP_BUY) ? GetBid(symbol) : GetAsk(symbol);
            double open_price = OrderOpenPrice();
            double sl_price = OrderStopLoss();
            double tp_price = OrderTakeProfit();
            double pips = (OrderType() == OP_BUY) ? (current_price - open_price) / point : (open_price - current_price) / point;

            // Süre kontrolü
            if ((TimeCurrent() - OrderOpenTime()) >= MaxPositionDuration_s)
            {
               Log(symbol, "POZİSYON KAPANIYOR (SÜRE DOLDU): Ticket: " + (string)OrderTicket());
               OrderClose(OrderTicket(), OrderLots(), current_price, MaxSlippagePips, clrNONE);
               continue;
            }

            // Kısmi kapama
            if (PartialClosePips > 0 && pips >= PartialClosePips)
            {
               double close_volume = NormalizeDouble(OrderLots() * PartialCloseVolume, 2);
               if (close_volume > 0)
               {
                  Log(symbol, "POZİSYON KISMİ KAPANIYOR: Ticket: " + (string)OrderTicket() + ", Hacim: " + DoubleToString(close_volume, 2));
                  OrderClose(OrderTicket(), close_volume, current_price, MaxSlippagePips, clrNONE);
               }
            }

            // Break-Even
            if (BreakEvenPips > 0 && pips >= BreakEvenPips && sl_price != open_price)
            {
               double new_sl = open_price;
               if (OrderType() == OP_BUY) new_sl = NormalizeDouble(open_price + 1 * point, digits); // 1 point kâr
               else new_sl = NormalizeDouble(open_price - 1 * point, digits); // 1 point kâr

               Log(symbol, "POZİSYON BREAK-EVEN'A ÇEKİLİYOR: Ticket: " + (string)OrderTicket());
               OrderModify(OrderTicket(), OrderOpenPrice(), new_sl, tp_price, 0, clrNONE);
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
                     OrderModify(OrderTicket(), OrderOpenPrice(), new_sl, tp_price, 0, clrNONE);
                  }
               }
               else // OP_SELL
               {
                  new_sl = current_price + TrailingStopPips * point;
                  if (new_sl < sl_price)
                  {
                     Log(symbol, "TRAILING STOP GÜNCELLENDİ (SELL): Ticket: " + (string)OrderTicket() + ", Yeni SL: " + DoubleToString(new_sl, digits));
                     OrderModify(OrderTicket(), OrderOpenPrice(), new_sl, tp_price, 0, clrNONE);
                  }
               }
            }
         }
      }
   }
}

//--- Ana Olay Fonksiyonları (MT4)

int OnInit_MT4()
{
   // Symbols_List'i ayrıştır
   g_symbol_count = StringSplit(Symbols_List, ',', g_symbols);
   ArrayResize(SymbolScores, g_symbol_count);
   
   Log("", "EA Başlatıldı (MT4): " + (string)MagicNumber + " v" + (string)Version());
   
   // Tüm sembollere abone ol
   for (int i = 0; i < g_symbol_count; i++)
   {
      SymbolSelect(g_symbols[i], true);
   }
   
   return(INIT_SUCCEEDED);
}

void OnDeinit_MT4(const int reason)
{
   Log("", "EA Durduruldu (MT4). Neden: " + (string)reason);
}

void OnTick_MT4()
{
   if (!IsTradingTime() || IsSwapNight() || IsMaxLossReached() || ServerBusyMode) return;

   for (int i = 0; i < g_symbol_count; i++)
   {
      string symbol = g_symbols[i];
      
      // Sembolü seç
      if (!SymbolSelect(symbol, true)) continue;
      
      // Spread kontrolü (Ortak fonksiyonda yapılacak)
      
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

