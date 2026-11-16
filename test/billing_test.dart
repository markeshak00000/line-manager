import 'package:flutter_test/flutter_test.dart';
import 'package:line_manager/domain/billing_engine.dart';
import 'package:line_manager/core/year_month.dart';
void main(){
  test('Case1 full payment', (){ final c=BillingCycleData(ym: YearMonth(2026,1), pricePiasters: 20000, packageName: 'X', paidPiasters: 20000); expect(c.status,'paid'); expect(c.remaining,0); });
  test('Case2 partial', (){ final c=BillingCycleData(ym: YearMonth(2026,1), pricePiasters: 30000, packageName: 'X', paidPiasters: 20000); expect(c.remaining,10000); expect(c.status,'partial'); expect(BillingEngine.remainingAfterPartial(price:30000, oldPaid:20000, newPayment:10000),0); });
  test('Case3 3 months arrears 600', (){ final list=[for(var i=1;i<=3;i++) BillingCycleData(ym: YearMonth(2026,i), pricePiasters: 20000, packageName: 'X')]; expect(BillingEngine.totalArrears(list),60000); });
  test('Case4 prepaid future not arrears', (){ final now=YearMonth.nowCairo(); final future=BillingCycleData(ym: now.addMonths(2), pricePiasters: 20000, packageName: 'X', paidPiasters: 20000); expect(future.isPrepaid,true); expect(BillingEngine.totalArrears([future]),0); });
  test('Case5 partial then complete does not affect others', (){ final a=BillingCycleData(ym: YearMonth(2026,1), pricePiasters: 30000, packageName: 'X', paidPiasters: 20000); final b=BillingCycleData(ym: YearMonth(2026,2), pricePiasters: 30000, packageName: 'X'); final alloc=BillingEngine.allocate([a,b],10000); expect(alloc.allocations['2026-01'],10000); expect(alloc.overpaymentPiasters,0); expect(b.paidPiasters,0); });
  test('Case6 two lines isolated', (){ final l1=[BillingCycleData(ym: YearMonth(2026,1), pricePiasters: 20000, packageName: 'X')]; final l2=[BillingCycleData(ym: YearMonth(2026,1), pricePiasters: 20000, packageName: 'X')]; BillingEngine.allocate(l1,20000); expect(BillingEngine.totalArrears(l2),20000); });
  test('Leap year Feb', (){ expect(YearMonth(2024,2).lastDay.day,29); expect(YearMonth(2025,2).lastDay.day,28); expect(YearMonth(2026,1).lastDay.day,31); });
  test('Allocation oldest first', (){ final cycles=[BillingCycleData(ym: YearMonth(2026,2), pricePiasters: 20000, packageName: 'X'), BillingCycleData(ym: YearMonth(2026,1), pricePiasters: 20000, packageName: 'X')]; final a=BillingEngine.allocate(cycles,30000); expect(a.allocations['2026-01'],20000); expect(a.allocations['2026-02'],10000); });
  test('FIXED overpayment is credit not folded', (){ final cycles=[BillingCycleData(ym: YearMonth(2026,1), pricePiasters: 20000, packageName: 'X')]; final a=BillingEngine.allocate(cycles,25000); expect(a.allocations['2026-01'],20000); expect(a.overpaymentPiasters,5000); expect(a.totalAllocated,20000); });
  test('FIXED manual allocation cannot exceed remaining', (){ final cycles=[BillingCycleData(ym: YearMonth(2026,1), pricePiasters: 20000, packageName: 'X', paidPiasters: 5000)]; expect(()=>BillingEngine.allocate(cycles, 20000, manual: {'2026-01': 20000}), throwsArgumentError); });
  test('Next due is first of next month', (){ final now=YearMonth(2026,1); final next=now.next(); expect(DateTime(next.year,next.month,1), DateTime(2026,2,1)); });
}
