//+------------------------------------------------------------------+
//|                 AdvancedManipulationDetectorEA.mq4               |
//|                      Copyright 2024, Manus AI                    |
//|                                  https://manus.im                |
//| Multi-Symbol Expert Advisor (v1.07)                              |
//+------------------------------------------------------------------+
#property copyright "Manus AI"
#property link      "https://manus.im"
#property version   "1.07"
#property strict

// MT4'e özel implementasyonu dahil et
#include "AdvancedManipulationDetector_MT4.mqh"

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   return OnInit_MT4();
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   OnDeinit_MT4(reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   OnTick_MT4();
}
//+------------------------------------------------------------------+

