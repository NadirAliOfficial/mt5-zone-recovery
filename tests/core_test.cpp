#include <cmath>
#include <cassert>
#include <iostream>
#define MathCeil std::ceil
#include "../MQL5/Include/AzizZoneRecovery/Core.mqh"
int main() {
 int checks=0;
 auto check=[&](bool ok){assert(ok);++checks;};
 auto near=[](double a,double b){return std::abs(a-b)<1e-8;};
 check(near(RoundVolumeUp(.015,.01),.02));
 check(near(RoundVolumeUp(.03,.01),.03));
 check(near(RoundVolumeUp(.0015,.001),.002));
 check(near(RoundVolumeUp(.01*2,.01),.02));
 check(near(RoundVolumeUp(.02*2,.01),.04));
 check(near(RoundVolumeUp(.04*2,.01),.08));
 check(near(RoundVolumeUp(.01*3,.01),.03));
 check(!VolumeAllowed(.02,.01,100,.01));
 check(!VolumeAllowed(.001,.01,100,1));
 check(VolumeAllowed(.01,.01,100,1));
 check(!VolumeAllowed(101,.01,100,200));
 check(near(RoundVolumeUp(2000./1000*.01,.01),.02));
 check(near(RoundVolumeUp(10000./1000*.01,.01),.10));
 check(RecoveryTriggered(1,1.098,1.10,1.098));
 check(!RecoveryTriggered(1,1.099,1.10,1.098));
 check(RecoveryTriggered(-1,1.10,1.10,1.098));
 check(!RecoveryTriggered(-1,1.0999,1.10,1.098));
 check(BasketReached(TARGET_DOLLARS,2,.01,2,300));
 check(!BasketReached(TARGET_POINTS,2,.01,2,300));
 check(BasketReached(TARGET_EITHER,2,.01,2,300));
 check(!BasketReached(TARGET_BOTH,2,.01,2,300));
 check(BasketReached(TARGET_BOTH,3,.01,2,300));
 check(!BasketReached(TARGET_EITHER,-1,.01,2,200));
 check(!BasketReached(TARGET_DOLLARS,2,0,2,200));
 // Algebraic recovery P/L: BUY .01 at 1.1000, SELL .02 at 1.0980,
 // bid=ask=1.0960 => -4 + 4 = 0, not the +2 claimed in image.
 double net=(1.096-1.100)*100000*.01+(1.098-1.096)*100000*.02;
 check(near(net,0));
 check(!BasketReached(TARGET_DOLLARS,net,.01,2,200));
 check(BasketReached(TARGET_DOLLARS,2.01,.01,2,200));
 check(InitialReached(true,1.1001,1.1021,1.1022,.00001,200,2));
 check(!InitialReached(true,1.1001,1.1020,1.1021,.00001,200,2));
 check(InitialReached(false,1.1,1.0979,1.098,.00001,200,2));
 check(!InitialReached(false,1.1,1.098,1.0981,.00001,200,2));
 check(!InitialReached(true,1.1001,1.1021,1.1022,.00001,200,-1));
 std::cout << checks << " shared-core checks passed\n";
}
