#ifndef AZIZ_CORE_MQH
#define AZIZ_CORE_MQH
// Pure functions shared by the EA and portable C++ regression tests.
enum BasketTargetMode { TARGET_DOLLARS=0, TARGET_POINTS=1, TARGET_EITHER=2, TARGET_BOTH=3 };
double RoundVolumeUp(double requested,double step)
{
   if(step<=0 || requested<=0) return 0;
   return MathCeil(requested/step-1e-9)*step;
}
bool VolumeAllowed(double lots,double minimum,double maximum,double user_max)
{
   return lots>=minimum-1e-9 && lots<=maximum+1e-9 && lots<=user_max+1e-9;
}
bool BasketReached(BasketTargetMode mode,double net,double point_value,double dollars,double points)
{
   if(net<=0 || point_value<=0) return false;
   bool money_ok=net+1e-8>=dollars;
   bool points_ok=net+1e-8>=points*point_value;
   if(mode==TARGET_DOLLARS) return money_ok;
   if(mode==TARGET_POINTS) return points_ok;
   if(mode==TARGET_EITHER) return money_ok || points_ok;
   return money_ok && points_ok;
}
bool InitialReached(bool buy,double fill,double bid,double ask,double point_size,double target_points,double net)
{
   if(point_size<=0 || net<=0) return false;
   double distance=buy ? bid-fill : fill-ask;
   return distance/point_size+1e-7>=target_points;
}
bool RecoveryTriggered(int prior_direction,double bid,double upper_level,double lower_level)
{
   return prior_direction==1 ? bid<=lower_level : bid>=upper_level;
}
#endif
