#ifndef WDStyle_h
#define WDStyle_h

#import "WDCommon.h"

void WDStyleRound(UIView *view, CGFloat radius, BOOL continuous);
void WDStyleCell(UITableViewCell *cell, CGFloat inset, CGFloat radius, BOOL continuous);
void WDStyleInvalidate(void);

#endif
