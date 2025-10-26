//+------------------------------------------------------------------+
//|                 AdvancedManipulationDetectorEA.mq4               |
//|                      Copyright 2024, Manus AI                    |
//|                                  https://manus.im                |
//| MT4 Ana Expert Advisor Dosyası                                   |
//+------------------------------------------------------------------+
#property copyright "Manus AI"
#property link      "https://manus.im"
#property version   "1.04"
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
void OnDeinit()
{
   OnDeinit_MT4(UninitializeReason());
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   OnTick_MT4();
}
//+------------------------------------------------------------------+

