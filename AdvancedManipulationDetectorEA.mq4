//+------------------------------------------------------------------+
//|                                AdvancedManipulationDetectorEA.mq4|
//|                      Copyright 2024, Manus AI                     |
//|                                  https://manus.im                 |
//+------------------------------------------------------------------+
#property copyright "Manus AI"
#property link      "https://manus.im"
#property version   "1.02"
#property description "MetaTrader 4 için Gelişmiş Manipülasyon Algılayıcı Expert Advisor"

// Ortak kodları ve ayarları içeren başlık dosyası
#include "AdvancedManipulationDetectorEA.mqh"

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   return OnInit_Common();
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   OnDeinit_Common(reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   OnTick_Common();
}

