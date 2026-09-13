#ifndef WDPrefs_h
#define WDPrefs_h

#import "WDCommon.h"

extern NSString *const WDPrefsDidChangeNotification;

// #RRGGBB / #AARRGGBB
UIColor *WDColorForHex(NSString *hex);
NSString *WDHexForColor(UIColor *c);

@interface WDPrefs : NSObject
+ (instancetype)shared;
@property (nonatomic, assign) BOOL master;
@property (nonatomic, assign) BOOL continuous;
@property (nonatomic, assign) CGFloat globalRadius;
@property (nonatomic, assign) CGFloat globalInset;

- (BOOL)enabledForClass:(NSString *)name def:(BOOL)def;
- (void)setEnabled:(BOOL)on forClass:(NSString *)name;
- (CGFloat)radiusForClass:(NSString *)name def:(CGFloat)def;
- (void)setRadius:(CGFloat)r forClass:(NSString *)name;
- (void)clearRadiusForClass:(NSString *)name;
- (CGFloat)insetForClass:(NSString *)name def:(CGFloat)def;
- (void)setInset:(CGFloat)v forClass:(NSString *)name;
- (void)clearInsetForClass:(NSString *)name;
- (BOOL)hasCustomRadius:(NSString *)name;
- (BOOL)hasCustomInset:(NSString *)name;
- (void)resetClass:(NSString *)name;
- (void)resetAll;
- (void)reload;
- (void)ping;

// 四个 Tab 页背景色：浅色 / 深色可分别设定
- (BOOL)bgEnabledForPage:(int)page;
- (void)setBgEnabled:(BOOL)on forPage:(int)page;
- (NSString *)bgHexForPage:(int)page dark:(BOOL)dark;
- (void)setBgHex:(NSString *)hex forPage:(int)page dark:(BOOL)dark;
- (UIColor *)bgColorForPage:(int)page dark:(BOOL)dark;
- (void)resetPage:(int)page;
@end

#endif
