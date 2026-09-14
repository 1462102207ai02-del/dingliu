#ifndef WDStyle_h
#define WDStyle_h

#import "WDCommon.h"

// tag = 目录下标，记录在视图上，供「关开关 → 精确还原」使用
void WDStyleRound(UIView *view, CGFloat radius, BOOL continuous, int tag);
void WDStyleRoundCorners(UIView *view, CGFloat radius, NSUInteger corners, BOOL continuous, int tag);
void WDStyleView(UIView *view, CGFloat inset, CGFloat radius, BOOL continuous, int tag);
void WDStyleCell(UITableViewCell *cell, CGFloat inset, CGFloat radius, BOOL continuous, int tag);
void WDStyleCellAt(UITableViewCell *cell, UITableView *tv, NSIndexPath *ip, CGFloat inset, CGFloat radius, BOOL continuous, int tag);
void WDStyleSearch(UIView *view, CGFloat inset, CGFloat radius, BOOL continuous, int tag);
void WDStyleFold(UIView *view, CGFloat inset, CGFloat radius, BOOL continuous, int tag);
void WDStyleProfile(UIView *view, CGFloat inset, CGFloat radius, BOOL continuous, int tag);
void WDStyleClearHeader(UIView *view);
void WDStyleHostCard(UIView *host, CGFloat inset, CGFloat radius, BOOL continuous, int tag);

// 设置页自身卡片化：圆角 + 双侧缩进 + 分区内首尾圆角
void WDStyleSettingsCell(UITableViewCell *cell, CGFloat inset, CGFloat radius, NSUInteger corners, BOOL continuous);

int  WDStyleTagOf(UIView *view);
void WDStyleRevertView(UIView *view);
void WDStyleInvalidate(void);
BOOL WDStyleShouldSkip(UIView *view);
void WDStyleSyncColors(BOOL master, BOOL inOn, const char *inL, const char *inD,
                       BOOL outOn, const char *outL, const char *outD);

#endif
