#ifndef WDStyle_h
#define WDStyle_h

#import "WDCommon.h"

// tag = 目录下标，记录在视图上，供「关开关 → 精确还原」使用
void WDStyleRound(UIView *view, CGFloat radius, BOOL continuous, int tag);
void WDStyleRoundCorners(UIView *view, CGFloat radius, NSUInteger corners, BOOL continuous, int tag);
void WDStyleCell(UITableViewCell *cell, CGFloat inset, CGFloat radius, BOOL continuous, int tag);

// 设置页自身卡片化：圆角 + 双侧缩进 + 分区内首尾圆角
void WDStyleSettingsCell(UITableViewCell *cell, CGFloat inset, CGFloat radius, NSUInteger corners, BOOL continuous);

int  WDStyleTagOf(UIView *view);
void WDStyleRevertView(UIView *view);
void WDStyleInvalidate(void);

#endif
