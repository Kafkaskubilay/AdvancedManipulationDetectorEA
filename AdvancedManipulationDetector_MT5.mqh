//+------------------------------------------------------------------+
//|                 AdvancedManipulationDetector_MT5.mqh             |
//|                      Copyright 2024, Manus AI                    |
//|                                  https://manus.im                |
//| MT5 Platformuna Özel Fonksiyonlar ve Implementasyonlar (v1.07)   |
//+------------------------------------------------------------------+
#property copyright "Manus AI"
#property link      "https://manus.im"
#property version   "1.07"
#property strict

// MT5 Gerekli Kütüphaneler
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// Ortak kodları dahil et
#include "AdvancedManipulationDetector_Common.mqh"

//+------------------------------------------------------------------+
//| MT5'e Özel Global Değişkenler ve Sınıflar (Ana Dosyada Tanımlanır)|
//+------------------------------------------------------------------+

// Emir defteri anomalisini OnTick'e iletmek için global değişken (HandleBookEvent'te kullanılır)
extern bool BookAnomalyDetected;

// Ana dosyada tanımlanan global değişkenlere erişim için
extern CTrade m_trade;
extern CPositionInfo m_position;

CTrade& GetTrade() { return m_trade; }
CPositionInfo& GetPosition() { return m_position; }

//+------------------------------------------------------------------+
//| MT5'e Özel Fonksiyonlar                                          |
//+------------------------------------------------------------------+

//--- Platformdan bağımsız fiyat alma (MT5)
double GetAsk(string symbol)
{
   double ask;
   SymbolInfoDouble(symbol, SYMBOL_ASK, ask);
   return ask;
}

double GetBid(string symbol)
{
   double bid;
   SymbolInfoDouble(symbol, SYMBOL_BID, bid);
   return bid;
}

//--- Lot büyüklüğünü hesaplama (MT5)
double CalculateLotSize(string symbol, int sl_pips)
{
   if (RiskPercent <= 0.0) return FixedLotSize;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_amount = equity * (RiskPercent / 100.0);
   
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double sl_distance_points = sl_pips * point;
   
   // Lot hesaplama formülü
   double lot = risk_amount / (sl_distance_points / tick_size * tick_value);

   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   if (step_lot > 0) lot = MathRound(lot / step_lot) * step_lot;
   
   lot = MathMax(min_lot, MathMin(max_lot, lot));

   Log(symbol, "Lot Hesaplandı (MT5): Risk: " + DoubleToString(risk_amount, 2) + ", SL Pips: " + (string)sl_pips + ", Lot: " + DoubleToString(lot, 2));
   return lot;
}

//--- İşlem açma fonksiyonu (MT5) - Retry eklendi
bool OpenTrade(string symbol, ENUM_ORDER_TYPE order_type, double lot, double price, int sl_pips, int tp_pips, string comment)
{
   if (lot <= 0) 
   {
      Log(symbol, "HATA: Lot büyüklüğü sıfır veya negatif. İşlem açılamadı.");
      return false;
   }

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   
   double current_spread_pips = (GetAsk(symbol) - GetBid(symbol)) / point;
   if (current_spread_pips > MaxSpreadPips)
   {
      Log(symbol, "İŞLEM İPTAL: Spread çok yüksek (" + DoubleToString(current_spread_pips, 1) + " Pips). Max limit: " + (string)MaxSpreadPips + " Pips.");
      return false;
   }
   
   MqlTradeRequest request;
   MqlTradeResult result;
   
   ZeroMemory(request);
   request.action = TRADE_ACTION_DEAL;
   request.symbol = symbol;
   request.volume = lot;
   request.type   = (order_type == ORDER_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price  = price;
   
   if (order_type == ORDER_TYPE_BUY)
   {
      request.sl = NormalizeDouble(price - sl_pips * point, digits);
      request.tp = NormalizeDouble(price + tp_pips * point, digits);
   }
   else
   {
      request.sl = NormalizeDouble(price + sl_pips * point, digits);
      request.tp = NormalizeDouble(price - tp_pips * point, digits);
   }
   
   request.deviation= (int)(MaxSlippagePips / point);
   request.magic    = MagicNumber;
   request.comment  = comment;

   string order_type_str = (order_type == ORDER_TYPE_BUY) ? "BUY" : "SELL";
   Log(symbol, "İşlem Açılıyor (MT5): " + order_type_str + ", Lot: " + DoubleToString(lot, 2) + ", Fiyat: " + DoubleToString(price, digits) + ", SL: " + DoubleToString(request.sl, digits) + ", TP: " + DoubleToString(request.tp, digits));

   int retries = 3;
   while (retries > 0)
   {
      if (GetTrade().OrderSend(request, result))
      {
         if (result.retcode == TRADE_RETCODE_DONE)
         {
            if (ServerBusyMode) ServerBusyMode = false;
            Log(symbol, "İŞLEM BAŞARILI (MT5): Ticket: " + (string)result.order);
            return true;
         }
         else
         {
            Log(symbol, "HATA: OrderSend başarısız oldu. Hata Kodu: " + EnumToString((ENUM_TRADE_RETCODE)result.retcode) + ". Tekrar deneniyor... (" + (string)retries + " kaldı)");
            
            if (result.retcode == TRADE_RETCODE_REQUOTE || result.retcode == TRADE_RETCODE_TRADE_CONTEXT_BUSY)
            {
               retries--;
               Sleep(100); // Kısa bekleme
               request.price = (order_type == ORDER_TYPE_BUY) ? GetAsk(symbol) : GetBid(symbol); // Yeni fiyat al
               continue;
            }
            
            if (result.retcode == TRADE_RETCODE_SERVER_BUSY)
            {
               ServerBusyMode = true;
               Log(symbol, "SUNUCU MEŞGUL. Bekleme moduna geçiliyor.");
               return false;
            }
            
            // Diğer hatalar için çık
            break;
         }
      }
      retries--;
   }
   
   return false;
}

//--- Pozisyon yönetimi (MT5)
void ManagePositions(string symbol)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (GetPosition().SelectByIndex(i) && GetPosition().Symbol() == symbol && GetPosition().Magic() == MagicNumber)
      {
         double current_price = (GetPosition().PositionType() == POSITION_TYPE_BUY) ? GetBid(symbol) : GetAsk(symbol);
         double open_price = GetPosition().PriceOpen();
         double sl_price = GetPosition().StopLoss();
         double tp_price = GetPosition().TakeProfit();
         double pips = (GetPosition().PositionType() == POSITION_TYPE_BUY) ? (current_price - open_price) / point : (open_price - current_price) / point;

         // Süre kontrolü
         if ((long)TimeCurrent() - (long)GetPosition().Time() >= MaxPositionDuration_s)
         {
            Log(symbol, "POZİSYON KAPANIYOR (SÜRE DOLDU): ID: " + (string)GetPosition().Ticket());
            GetTrade().PositionClose(GetPosition().Ticket());
            continue;
         }

         // Kısmi kapama
         if (PartialClosePips > 0 && pips >= PartialClosePips)
         {
            double close_volume = NormalizeDouble(GetPosition().Volume() * PartialCloseVolume, 2);
            if (close_volume > 0)
            {
               Log(symbol, "POZİSYON KISMİ KAPANIYOR: ID: " + (string)GetPosition().Ticket() + ", Hacim: " + DoubleToString(close_volume, 2));
               GetTrade().PositionClose(GetPosition().Ticket(), close_volume);
            }
         }

         // Break-Even
         if (BreakEvenPips > 0 && pips >= BreakEvenPips && sl_price != open_price)
         {
            Log(symbol, "POZİSYON BREAK-EVEN'A ÇEKİLİYOR: ID: " + (string)GetPosition().Ticket());
            GetTrade().PositionModify(GetPosition().Ticket(), open_price, tp_price);
         }

         // Trailing Stop
         if (TrailingStopPips > 0 && pips >= TrailingStopPips)
         {
            double new_sl = 0.0;
            if (GetPosition().PositionType() == POSITION_TYPE_BUY)
            {
               new_sl = current_price - TrailingStopPips * point;
               if (new_sl > sl_price)
               {
                  Log(symbol, "TRAILING STOP GÜNCELLENDİ (BUY): ID: " + (string)GetPosition().Ticket() + ", Yeni SL: " + DoubleToString(new_sl, digits));
                  GetTrade().PositionModify(GetPosition().Ticket(), new_sl, tp_price);
               }
            }
            else // SELL
            {
               new_sl = current_price + TrailingStopPips * point;
               if (new_sl < sl_price)
               {
                  Log(symbol, "TRAILING STOP GÜNCELLENDİ (SELL): ID: " + (string)GetPosition().Ticket() + ", Yeni SL: " + DoubleToString(new_sl, digits));
                  GetTrade().PositionModify(GetPosition().Ticket(), new_sl, tp_price);
               }
            }
         }
      }
   }
}

//--- MT5 Emir Defteri Anomali Tespiti
void HandleBookEvent(string symbol, const MqlBookInfo &book[])
{
   if (symbol != Symbol()) return;
   
   // Emir defteri manipülasyonu (Spoofing/Stop Hunt) tespiti
   double current_bid_volume = 0;
   double current_ask_volume = 0;
   
   // Sadece en üst 5 seviyeyi kontrol et
   for (int i = 0; i < MathMin(ArraySize(book), 5); i++)
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
   
   // Basit anomali tespiti: Bir taraftaki hacim, diğerinin 5 katından fazlaysa
   if (current_bid_volume > current_ask_volume * 5 || current_ask_volume > current_bid_volume * 5)
   {
      BookAnomalyDetected = true;
      Log(symbol, "DOM ANOMALİSİ TESPİT EDİLDİ: Bid Hacmi: " + DoubleToString(current_bid_volume, 0) + ", Ask Hacmi: " + DoubleToString(current_ask_volume, 0));
   }
   else
   {
      BookAnomalyDetected = false;
   }
}

//--- Ana Olay Fonksiyonları (MT5)

int OnInit_MT5()
{
   GetTrade().SetExpertMagicNumber(MagicNumber);
   GetTrade().SetMarginMode();
   
   string symbols[];
   int count = StringSplit(Symbols_List, ',', symbols);
   
   for (int i = 0; i < count; i++)
   {
      SymbolSelect(symbols[i], true);
      // Emir defteri olaylarını almak için abone ol
      MarketBookAdd(symbols[i]);
   }
   
   Log("", "EA Başlatıldı (MT5): " + Expert_ID + " v" + (string)Version());
   return(INIT_SUCCEEDED);
}

void OnDeinit_MT5(const int reason)
{
   string symbols[];
   int count = StringSplit(Symbols_List, ',', symbols);
   
   for (int i = 0; i < count; i++)
   {
      MarketBookRelease(symbols[i]);
   }
   
   Log("", "EA Durduruldu (MT5). Neden: " + (string)reason);
}

void OnTick_MT5()
{
   if (!IsTradingTime() || ServerBusyMode) return;

   string symbols[];
   int count = StringSplit(Symbols_List, ',', symbols);
   
   for (int i = 0; i < count; i++)
   {
      string symbol = symbols[i];
      
      // Sembolü seç
      if (!SymbolSelect(symbol, true)) continue;
      
      ManagePositions(symbol);

      // Sadece pozisyon yoksa sinyal ara
      if (PositionsTotal() > 0) continue;

      ENUM_ORDER_TYPE signal = DetectManipulationSignal(symbol);
      
      // MT5'e özel 3. filtre: DOM Anomali Onayı
      if (signal != (ENUM_ORDER_TYPE)-1 && BookAnomalyDetected)
      {
         Log(symbol, "GÜÇLÜ SİNYAL ONAYI: DOM Anomali filtresi de geçti.");
         double lot = CalculateLotSize(symbol, StopLossPips);
         double price = (signal == ORDER_TYPE_BUY) ? GetAsk(symbol) : GetBid(symbol);
         OpenTrade(symbol, signal, lot, price, StopLossPips, TakeProfitPips, "AMD Signal");
      }
      else if (signal != (ENUM_ORDER_TYPE)-1)
      {
         Log(symbol, "SİNYAL ALINDI, ancak DOM Anomali filtresi geçilemedi. İşlem açılmadı.");
      }
   }
}

