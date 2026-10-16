#property strict
#property description "Read-only historical tick export for offline regression/replay. No trading calls."
void OnStart()
{
   string symbol="EURUSD";
   if(!SymbolSelect(symbol,true)) { Print("EXPORT_FAIL symbol"); return; }
   int file=FileOpen("aziz-eurusd-ticks.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(file==INVALID_HANDLE) { Print("EXPORT_FAIL file"); return; }
   FileWrite(file,"time_msc","bid","ask");
   long total=0;
   for(datetime day=D'2025.01.02';day<D'2025.04.01';day+=86400)
   {
      MqlTick ticks[];
      int n=CopyTicksRange(symbol,ticks,COPY_TICKS_ALL,(ulong)day*1000,(ulong)(day+86400)*1000-1);
      if(n<0) { PrintFormat("EXPORT_FAIL date=%s error=%d",TimeToString(day),GetLastError()); FileClose(file); return; }
      for(int i=0;i<n;i++)
         if(ticks[i].bid>0 && ticks[i].ask>=ticks[i].bid)
         { FileWrite(file,ticks[i].time_msc,DoubleToString(ticks[i].bid,5),DoubleToString(ticks[i].ask,5)); total++; }
      PrintFormat("EXPORT_DAY %s ticks=%d",TimeToString(day,TIME_DATE),n);
   }
   FileClose(file);
   PrintFormat("EXPORT_OK total=%I64d point=%.8f contract=%.0f volume_step=%.4f",total,
               SymbolInfoDouble(symbol,SYMBOL_POINT),SymbolInfoDouble(symbol,SYMBOL_TRADE_CONTRACT_SIZE),SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP));
}
