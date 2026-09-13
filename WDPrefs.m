#import "WDPrefs.h"
#import "WDCatalog.h"

NSString *const WDPrefsDidChangeNotification = @"WDPrefsDidChangeNotification";

static NSString *WDOnKey(NSString *n) { return [@"WD.on." stringByAppendingString:n]; }
static NSString *WDRadKey(NSString *n) { return [@"WD.r." stringByAppendingString:n]; }
static NSString *WDInsKey(NSString *n) { return [@"WD.i." stringByAppendingString:n]; }

@implementation WDPrefs {
    NSUserDefaults *_ud;
}

+ (instancetype)shared {
    static WDPrefs *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[WDPrefs alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _ud = [NSUserDefaults standardUserDefaults];
        [_ud registerDefaults:@{
            @"WD.master": @YES,
            @"WD.continuous": @YES,
            @"WD.globalRadius": @14.0,
            @"WD.globalInset": @12.0,
        }];
        int n = WDCatalogCount();
        const WDItem *items = WDCatalogItems();
        for (int i = 0; i < n; i++) {
            NSString *name = @(items[i].cls);
            if ([_ud objectForKey:WDOnKey(name)] == nil) {
                [_ud setBool:items[i].defOn != 0 forKey:WDOnKey(name)];
            }
        }
    }
    return self;
}

- (BOOL)master { return [_ud objectForKey:@"WD.master"] ? [_ud boolForKey:@"WD.master"] : YES; }
- (void)setMaster:(BOOL)v { [_ud setBool:v forKey:@"WD.master"]; [self ping]; }

- (BOOL)continuous { return [_ud objectForKey:@"WD.continuous"] ? [_ud boolForKey:@"WD.continuous"] : YES; }
- (void)setContinuous:(BOOL)v { [_ud setBool:v forKey:@"WD.continuous"]; [self ping]; }

- (CGFloat)globalRadius {
    id v = [_ud objectForKey:@"WD.globalRadius"];
    return v ? [v doubleValue] : 14.0;
}
- (void)setGlobalRadius:(CGFloat)v { [_ud setDouble:v forKey:@"WD.globalRadius"]; [self ping]; }

- (CGFloat)globalInset {
    id v = [_ud objectForKey:@"WD.globalInset"];
    return v ? [v doubleValue] : 12.0;
}
- (void)setGlobalInset:(CGFloat)v { [_ud setDouble:v forKey:@"WD.globalInset"]; [self ping]; }

- (BOOL)enabledForClass:(NSString *)name def:(BOOL)def {
    id v = [_ud objectForKey:WDOnKey(name)];
    return v ? [v boolValue] : def;
}
- (void)setEnabled:(BOOL)on forClass:(NSString *)name {
    [_ud setBool:on forKey:WDOnKey(name)];
    [self ping];
}

- (BOOL)hasCustomRadius:(NSString *)name {
    return [_ud objectForKey:WDRadKey(name)] != nil;
}
- (CGFloat)radiusForClass:(NSString *)name def:(CGFloat)def {
    id v = [_ud objectForKey:WDRadKey(name)];
    if (v) return [v doubleValue];
    if (def > 0) return def;
    return self.globalRadius;
}
- (void)setRadius:(CGFloat)r forClass:(NSString *)name {
    [_ud setDouble:r forKey:WDRadKey(name)];
    [self ping];
}

- (BOOL)hasCustomInset:(NSString *)name {
    return [_ud objectForKey:WDInsKey(name)] != nil;
}
- (CGFloat)insetForClass:(NSString *)name def:(CGFloat)def {
    id v = [_ud objectForKey:WDInsKey(name)];
    if (v) return [v doubleValue];
    // 气泡默认不缩进：defInset=0 且未自定义时保持 0
    if (def == 0 && ![self hasCustomInset:name]) {
        const WDItem *it = WDCatalogFind(name);
        if (it && it->kind == WDKindBubble) return 0;
        if (it && it->defInset == 0) return 0;
    }
    if (def > 0) return def;
    return self.globalInset;
}
- (void)setInset:(CGFloat)v forClass:(NSString *)name {
    [_ud setDouble:v forKey:WDInsKey(name)];
    [self ping];
}

- (void)resetClass:(NSString *)name {
    [_ud removeObjectForKey:WDOnKey(name)];
    [_ud removeObjectForKey:WDRadKey(name)];
    [_ud removeObjectForKey:WDInsKey(name)];
    const WDItem *it = WDCatalogFind(name);
    if (it) [_ud setBool:it->defOn != 0 forKey:WDOnKey(name)];
    [self ping];
}

- (void)resetAll {
    NSDictionary *d = [_ud dictionaryRepresentation];
    for (NSString *k in d) {
        if ([k hasPrefix:@"WD."]) [_ud removeObjectForKey:k];
    }
    [_ud setBool:YES forKey:@"WD.master"];
    [_ud setBool:YES forKey:@"WD.continuous"];
    [_ud setDouble:14.0 forKey:@"WD.globalRadius"];
    [_ud setDouble:12.0 forKey:@"WD.globalInset"];
    int n = WDCatalogCount();
    const WDItem *items = WDCatalogItems();
    for (int i = 0; i < n; i++) {
        [_ud setBool:items[i].defOn != 0 forKey:WDOnKey(@(items[i].cls))];
    }
    [self ping];
}

- (void)reload { /* NSUserDefaults 同进程即时可读 */ }

- (void)ping {
    [_ud synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:WDPrefsDidChangeNotification object:nil];
}

@end
