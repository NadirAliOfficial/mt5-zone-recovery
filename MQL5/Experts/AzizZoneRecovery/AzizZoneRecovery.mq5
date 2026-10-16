#property strict
#property version "1.00"
#property description "Two-level recovery EA. Hedging account required. Trading outside tester disabled by default."
#include <Trade/Trade.mqh>
#include <AzizZoneRecovery/Core.mqh>

input group "Entry and volume"
input double InpStartingLot=0.01;
input bool   InpAutoLot=false;
input double InpCapitalPerLotUnit=1000.0; // Account BALANCE per lot unit
input double InpLotUnit=0.01;
input double InpMultiplier=2.0;
input double InpGridPoints=200.0; // Broker points, not pips
input double InpInitialTPPoints=200.0;
input group "Basket target"
input BasketTargetMode InpTargetMode=TARGET_DOLLARS;
input double InpBasketDollars=2.0; // Requires USD account except points-only mode
input double InpBasketPoints=200.0; // Net P/L divided by value of one point at starting lot
input double InpExitCommissionPerLot=0.0; // Estimated remaining close cost, account currency/lot
input group "Limits and execution"
input int    InpMaxTrades=5;
input double InpMaxLot=1.0;
input double InpMaxSpreadPoints=50.0; // Blocks entries only, never exits
input ulong  InpDeviationPoints=20;
input ulong  InpMagic=16102026;
input uint   InpRandomSeed=42; // 0 = time seed; fixed nonzero seed for reproducible tests
input bool   InpEnableTradingOutsideTester=false;

CTrade trade;
string key;
double upper=0,lower=0,base_lot=0,last_lot=0,gross_lots=0;
int last_direction=0,opened=0;
bool closing=false,blocked=false,halted=false;
long instance_chart=0;
uint rng=1;
datetime entry_retry_after=0;
datetime last_state_flush=0;
struct Basket
{
   int count;
   double net;
   double volume;
};
bool OwnPosition(ulong ticket)
{
   return PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL)==_Symbol &&
          (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic;
}
Basket ReadBasket()
{
   Basket b; b.count=0; b.net=0; b.volume=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!OwnPosition(ticket)) continue;
      b.count++;
      b.volume+=PositionGetDouble(POSITION_VOLUME);
      b.net+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      // Entry commissions/fees are realized deals, not POSITION_PROFIT.
      if(HistorySelectByPosition(id))
      {
         for(int j=0;j<HistoryDealsTotal();j++)
         {
            ulong deal=HistoryDealGetTicket(j);
            b.net+=HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
         }
      }
   }
   b.net-=b.volume*InpExitCommissionPerLot;
   return b;
}
void SaveState()
{
   GlobalVariableSet(key+"upper",upper); GlobalVariableSet(key+"lower",lower);
   GlobalVariableSet(key+"gross",gross_lots);
   GlobalVariableSet(key+"base",base_lot); GlobalVariableSet(key+"lastlot",last_lot);
   GlobalVariableSet(key+"dir",last_direction); GlobalVariableSet(key+"count",opened);
   GlobalVariableSet(key+"closing",closing); GlobalVariableSet(key+"blocked",blocked);
   GlobalVariableSet(key+"halted",halted); GlobalVariableSet(key+"rng",(double)rng);
   GlobalVariablesFlush();
   last_state_flush=TimeCurrent();
}
void ResetBasket()
{
   upper=0; lower=0; base_lot=0; last_lot=0; gross_lots=0; last_direction=0;
   opened=0; closing=false; blocked=false;
   SaveState();
}
bool LoadState()
{
   if(!GlobalVariableCheck(key+"count")) return false;
   upper=GlobalVariableGet(key+"upper"); lower=GlobalVariableGet(key+"lower");
   gross_lots=GlobalVariableGet(key+"gross");
   base_lot=GlobalVariableGet(key+"base"); last_lot=GlobalVariableGet(key+"lastlot");
   last_direction=(int)GlobalVariableGet(key+"dir"); opened=(int)GlobalVariableGet(key+"count");
   closing=GlobalVariableGet(key+"closing")>0; blocked=GlobalVariableGet(key+"blocked")>0;
   halted=GlobalVariableGet(key+"halted")>0;
   rng=(uint)GlobalVariableGet(key+"rng");
   return base_lot>0 && upper>lower && (last_direction==1 || last_direction==-1);
}
void Halt(string reason)
{
   if(!halted) Print("HALT: ",reason,". Entries disabled; manual inspection required.");
   halted=true; SaveState();
}
void Block(string reason)
{
   if(!blocked) Print("LIMIT: ",reason,". No further recovery entries in this basket.");
   blocked=true; SaveState();
}
bool Executed(bool requested)
{
   uint code=trade.ResultRetcode();
   if(requested && (code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL)) return true;
   PrintFormat("Trade rejected: %u %s",code,trade.ResultRetcodeDescription());
   return false;
}
bool OpenLeg(int direction,double lots)
{
   int before=ReadBasket().count;
   bool ok=direction==1 ? trade.Buy(lots,_Symbol,0,0,0,"Aziz recovery") :
                          trade.Sell(lots,_Symbol,0,0,0,"Aziz recovery");
   if(!Executed(ok))
   {
      uint code=trade.ResultRetcode();
      entry_retry_after=TimeCurrent()+5;
      if(code==TRADE_RETCODE_NO_MONEY || code==TRADE_RETCODE_LIMIT_VOLUME || code==TRADE_RETCODE_LIMIT_POSITIONS)
         Block("broker margin/volume/position limit");
      if(code==TRADE_RETCODE_TIMEOUT || code==TRADE_RETCODE_CONNECTION || code==TRADE_RETCODE_PLACED)
         Halt("entry outcome uncertain; inspect broker orders/positions before resuming");
      return false;
   }
   if(ReadBasket().count!=before+1)
   {
      Halt("unexpected position count after entry"); return false;
   }
   last_lot=trade.ResultVolume();
   if(last_lot<=0) { Halt("missing confirmed fill volume"); return false; }
   last_direction=direction; opened++; gross_lots+=last_lot;
   PrintFormat("LEG %d direction=%d lots=%.4f fill=%.8f",opened,direction,last_lot,trade.ResultPrice());
   if(trade.ResultRetcode()==TRADE_RETCODE_DONE_PARTIAL) blocked=true;
   return true;
}
void CloseBasket()
{
   // Latch persisted before first close: retries may not start a fresh basket.
   closing=true; SaveState();
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(OwnPosition(ticket)) Executed(trade.PositionClose(ticket,InpDeviationPoints));
   }
   if(ReadBasket().count==0) ResetBasket();
}
double PointValue()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || base_lot<=0) return 0;
   double profit=0;
   if(!OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,base_lot,tick.bid,tick.bid+_Point,profit)) return 0;
   return MathAbs(profit);
}
bool CanEnter(MqlTick &tick)
{
   return !halted && !blocked && TimeCurrent()>=entry_retry_after && tick.ask>=tick.bid && tick.bid>0 &&
          (tick.ask-tick.bid)/_Point<=InpMaxSpreadPoints;
}
int OnInit()
{
   if(InpStartingLot<=0 || InpCapitalPerLotUnit<=0 || InpLotUnit<=0 || InpMultiplier<=1 ||
      InpGridPoints<=0 || InpInitialTPPoints<=0 || InpBasketDollars<=0 || InpBasketPoints<=0 ||
      InpMaxTrades<1 || InpMaxLot<=0 || InpMaxSpreadPoints<=0 || InpExitCommissionPerLot<0)
      return INIT_PARAMETERS_INCORRECT;
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   { Print("A hedging account is required; netting is unsupported."); return INIT_FAILED; }
   if(InpTargetMode!=TARGET_POINTS && AccountInfoString(ACCOUNT_CURRENCY)!="USD")
   { Print("Dollar targets require USD account currency. Use points-only for other currencies."); return INIT_FAILED; }
   if(!MQLInfoInteger(MQL_TESTER) && !InpEnableTradingOutsideTester)
   { Print("Trading outside tester is disabled. Enable explicitly only after testing."); return INIT_FAILED; }
   key=StringFormat("AZR.%I64d.%s.%I64u.",AccountInfoInteger(ACCOUNT_LOGIN),_Symbol,InpMagic);
   if(StringLen(key)>54) { Print("State key too long: shorten symbol/magic."); return INIT_FAILED; }
   trade.SetExpertMagicNumber(InpMagic); trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetAsyncMode(false); trade.SetTypeFillingBySymbol(_Symbol);
   rng=InpRandomSeed==0 ? (uint)TimeLocal() : InpRandomSeed;
   if(rng==0) rng=1;
   // A magic/symbol pair must have one chart owner in this terminal.
   string lock=key+"owner";
   if(!GlobalVariableCheck(lock)) GlobalVariableTemp(lock);
   double owner=GlobalVariableGet(lock);
   if(owner!=0 && (long)owner!=ChartID())
   {
      for(long chart=ChartFirst();chart>=0;chart=ChartNext(chart))
         if(chart==(long)owner) { Print("Another chart owns this magic/symbol."); return INIT_FAILED; }
   }
   if(!GlobalVariableSetOnCondition(lock,(double)ChartID(),owner)) return INIT_FAILED;
   instance_chart=ChartID();
   Basket b=ReadBasket();
   if(b.count>0)
   {
      if(!LoadState() || (!closing && (opened!=b.count || MathAbs(gross_lots-b.volume)>1e-8))) { Print("Unrecoverable or changed basket state; inspect positions."); return INIT_FAILED; }
      Print("Restored existing basket.");
   }
   else
   {
      // Keep a manually triggered halt across chart restarts outside tester.
      if(!MQLInfoInteger(MQL_TESTER) && GlobalVariableCheck(key+"halted"))
         halted=GlobalVariableGet(key+"halted")>0;
      ResetBasket();
   }
   PrintFormat("Aziz recovery initialized: mode=%d multiplier=%.2f grid=%.0f points",InpTargetMode,InpMultiplier,InpGridPoints);
   return INIT_SUCCEEDED;
}
void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;
   Basket b=ReadBasket();
   // Keep terminal globals alive during recovery baskets lasting over four weeks.
   if(opened>0 && TimeCurrent()-last_state_flush>=60) SaveState();
   if(closing) { CloseBasket(); return; }
   if(b.count!=opened || MathAbs(b.volume-gross_lots)>1e-8)
   {
      Halt("external/manual change detected in own positions");
      if(b.count==0) { ResetBasket(); return; }
   }
   if(halted) return;
   if(b.count==0)
   {
      if(!CanEnter(tick)) return;
      double raw=InpAutoLot ? AccountInfoDouble(ACCOUNT_BALANCE)/InpCapitalPerLotUnit*InpLotUnit : InpStartingLot;
      double lots=RoundVolumeUp(raw,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP));
      if(!VolumeAllowed(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),InpMaxLot))
      { Halt("starting lot outside configured/broker bounds"); return; }
      rng^=rng<<13; rng^=rng>>17; rng^=rng<<5;
      int direction=(rng & 1)==0 ? 1 : -1;
      if(OpenLeg(direction,lots))
      {
         base_lot=last_lot;
         // Both reversal triggers use bid coordinates; spread cannot fake a zone crossing.
         upper=direction==1 ? tick.bid : tick.bid+InpGridPoints*_Point;
         lower=upper-InpGridPoints*_Point;
         SaveState();
      }
      return;
   }
   double value=PointValue();
   bool target=false;
   if(opened==1)
   {
      // No broker-side individual TP; after hedge entry only the basket exit applies.
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);
         if(!OwnPosition(ticket)) continue;
         double price=PositionGetDouble(POSITION_PRICE_OPEN);
         bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
         target=InitialReached(buy,price,tick.bid,tick.ask,_Point,InpInitialTPPoints,b.net);
      }
   }
   else target=BasketReached(InpTargetMode,b.net,value,InpBasketDollars,InpBasketPoints);
   if(target) { PrintFormat("TARGET net=%.2f positions=%d",b.net,b.count); CloseBasket(); return; }
   if(!CanEnter(tick) || blocked) return;
   if(opened>=InpMaxTrades) { Block("max trades reached"); return; }
   if(!RecoveryTriggered(last_direction,tick.bid,upper,lower)) return;
   double lots=RoundVolumeUp(last_lot*InpMultiplier,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP));
   if(!VolumeAllowed(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),InpMaxLot))
   { Block("next lot exceeds volume limit"); return; }
   if(OpenLeg(-last_direction,lots)) SaveState();
}
void OnDeinit(const int reason)
{
   if(instance_chart!=0 && GlobalVariableGet(key+"owner")==instance_chart)
      GlobalVariableSet(key+"owner",0);
}
