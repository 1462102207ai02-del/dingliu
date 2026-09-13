#ifndef WDStyle_h
#define WDStyle_h

#import "WDCommon.h"

void WDApplyChrome(UIView *view, const WDItem *item);
void WDApplyBanner(UIView *view, const WDItem *item);
void WDApplyCell(UITableViewCell *cell, UITableView *tv, NSIndexPath *ip, const WDItem *item);
void WDApplyView(UIView *view, const WDItem *item);
void WDApplyBubble(UIView *view, const WDItem *item);
void WDStyleVisibleTables(void);

#endif
