#ifndef WDStyle_h
#define WDStyle_h

#import "WDCommon.h"

void WDStyleRound(UIView *view, CGFloat radius, BOOL continuous, int tag);
void WDStyleRoundCorners(UIView *view, CGFloat radius, NSUInteger corners, BOOL continuous, int tag);
void WDStyleView(UIView *view, CGFloat inset, CGFloat radius, BOOL continuous, int tag);
void WDStyleCell(UITableViewCell *cell, CGFloat inset, CGFloat radius, BOOL continuous, int tag);
void WDStyleCellAt(UITableViewCell *cell, UITableView *tv, NSIndexPath *ip, CGFloat inset, CGFloat radius, BOOL continuous, int tag);
void WDStyleSearch(UIView *view, CGFloat inset, CGFloat radius, BOOL continuous, int tag);
void WDStyleFold(UIView *view, CGFloat inset, CGFloat radius, BOOL continuous, int tag);
void WDStyleProfile(UIView *view, CGFloat inset, CGFloat radius, BOOL continuous, int tag);
void WDStyleMePage(UIViewController *vc, CGFloat inset, CGFloat radius, BOOL continuous, int tag);
void WDStyleClearHeader(UIView *view);
void WDStyleClearTableTail(UIView *root);
BOOL WDStyleIsSearchBarLike(UIView *view);
void WDStyleHostCard(UIView *host, CGFloat inset, CGFloat radius, BOOL continuous, int tag);

void WDStyleSettingsCell(UITableViewCell *cell, CGFloat inset, CGFloat radius, NSUInteger corners, BOOL continuous);

int  WDStyleTagOf(UIView *view);
void WDStyleRevertView(UIView *view);
void WDStyleInvalidate(void);
BOOL WDStyleShouldSkip(UIView *view);
void WDStyleSyncColors(BOOL master, BOOL inOn, const char *inL, const char *inD,
                       BOOL outOn, const char *outL, const char *outD);

#endif
