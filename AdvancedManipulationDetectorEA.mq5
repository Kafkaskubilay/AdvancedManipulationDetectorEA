//+------------------------------------------------------------------+
//|                 AdvancedManipulationDetectorEA.mq5               |
//|                      Copyright 2024, Manus AI                    |
//|                                  https://manus.im                |
//| MT5 Ana Expert Advisor Dosyası                                   |
//+------------------------------------------------------------------+
#property copyright "Manus AI"
#property link      "https://manus.im"
#property version   "1.04"
#property strict

// MT5'e özel implementasyonu dahil et
#include "AdvancedManipulationDetector_MT5.mqh"

//+------------------------------------------------------------------+
//| Global Değişkenler (MT5)                                         |
//+------------------------------------------------------------------+
CTrade      m_trade;        // MT5 İşlem sınıfı
CPositionInfo m_position;   // MT5 Pozisyon bilgisi sınıfı
MqlTick     last_tick;      // Son tick verisi
bool BookAnomalyDetected = false; // Emir defteri anomali bayrağı

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   return OnInit_MT5();
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   OnDeinit_MT5(reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   OnTick_MT5();
}

//+------------------------------------------------------------------+
//| Expert BookEvent function                                        |
//+------------------------------------------------------------------+
void OnBookEvent(const string symbol, const MqlBookInfo &book[])
{
   HandleBookEvent(symbol, book);
}
//+------------------------------------------------------------------+

