#ifndef WDPrefs_h
#define WDPrefs_h

#import "WDCommon.h"

extern NSString *const WDPrefsDidChangeNotification;

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
- (CGFloat)insetForClass:(NSString *)name def:(CGFloat)def;
- (void)setInset:(CGFloat)v forClass:(NSString *)name;
- (BOOL)hasCustomRadius:(NSString *)name;
- (BOOL)hasCustomInset:(NSString *)name;
- (void)resetClass:(NSString *)name;
- (void)resetAll;
- (void)reload;
@end

#endif
