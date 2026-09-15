#ifndef WDPrefs_h
#define WDPrefs_h

#import "WDCommon.h"

extern NSString *const WDPrefsDidChangeNotification;

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
- (NSDictionary *)exportDictionary;
- (BOOL)importDictionary:(NSDictionary *)dict;
- (void)ping;

- (BOOL)bgEnabled;
- (void)setBgEnabled:(BOOL)on;
- (NSString *)bgHexDark:(BOOL)dark;
- (void)setBgHex:(NSString *)hex dark:(BOOL)dark;
- (UIColor *)bgColorDark:(BOOL)dark;
- (void)resetBg;

- (BOOL)cardOutEnabled;
- (void)setCardOutEnabled:(BOOL)on;
- (NSString *)cardOutHexDark:(BOOL)dark;
- (void)setCardOutHex:(NSString *)hex dark:(BOOL)dark;
- (UIColor *)cardOutColorDark:(BOOL)dark;

- (BOOL)cardInEnabled;
- (void)setCardInEnabled:(BOOL)on;
- (NSString *)cardInHexDark:(BOOL)dark;
- (void)setCardInHex:(NSString *)hex dark:(BOOL)dark;
- (UIColor *)cardInColorDark:(BOOL)dark;
@end

#endif
