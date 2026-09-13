#import "WDPrefs.h"
#import "WDCatalog.h"

NSString *const WDPrefsDidChangeNotification = @"WDPrefsDidChangeNotification";

static NSString *WDOnKey(NSString *n) { return [@"WD.on." stringByAppendingString:n]; }
static NSString *WDRadKey(NSString *n) { return [@"WD.r." stringByAppendingString:n]; }
static NSString *WDInsKey(NSString *n) { return [@"WD.i." stringByAppendingString:n]; }

static NSString *WDBgOnKey(int page)  { return [NSString stringWithFormat:@"WD.bg.on.%d", page]; }
static NSString *WDBgLitKey(int page) { return [NSString stringWithFormat:@"WD.bg.l.%d", page]; }
static NSString *WDBgDarkKey(int page){ return [NSString stringWithFormat:@"WD.bg.d.%d", page]; }

UIColor *WDColorForHex(NSString *hex) {
    if (hex.length == 0) return nil;
    NSString *h = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (h.length != 6 && h.length != 8) return nil;
    unsigned v = 0;
    NSScanner *s = [NSScanner scannerWithString:h];
    if (!s || ![s scanHexInt:&v]) return nil;
    if (h.length == 8)
        return [UIColor colorWithRed:((v >> 16) & 0xff) / 255.0
                               green:((v >> 8) & 0xff) / 255.0
                                blue:(v & 0xff) / 255.0
                               alpha:((v >> 24) & 0xff) / 255.0];
    return [UIColor colorWithRed:((v >> 16) & 0xff) / 255.0
                           green:((v >> 8) & 0xff) / 255.0
                            blue:(v & 0xff) / 255.0
                           alpha:1.0];
}

NSString *WDHexForColor(UIColor *c) {
    if (!c) return nil;
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![c getRed:&r green:&g blue:&b alpha:&a]) return nil;
    r = MAX(0.0, MIN(1.0, r)); g = MAX(0.0, MIN(1.0, g));
    b = MAX(0.0, MIN(1.0, b)); a = MAX(0.0, MIN(1.0, a));
    if (a < 0.999)
        return [NSString stringWithFormat:@"#%02X%02X%02X%02X",
                (int)roundf(a * 255), (int)roundf(r * 255), (int)roundf(g * 255), (int)roundf(b * 255)];
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (int)roundf(r * 255), (int)roundf(g * 255), (int)roundf(b * 255)];
}

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
- (void)clearRadiusForClass:(NSString *)name {
    [_ud removeObjectForKey:WDRadKey(name)];
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
        if (it && (it->kind == WDKindBubble || it->defInset == 0)) return 0;
    }
    if (def > 0) return def;
    return self.globalInset;
}
- (void)setInset:(CGFloat)v forClass:(NSString *)name {
    [_ud setDouble:v forKey:WDInsKey(name)];
    [self ping];
}
- (void)clearInsetForClass:(NSString *)name {
    [_ud removeObjectForKey:WDInsKey(name)];
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

- (void)disableAllEnabled {
    int n = WDCatalogCount();
    const WDItem *items = WDCatalogItems();
    for (int i = 0; i < n; i++) {
        [_ud setBool:NO forKey:WDOnKey(@(items[i].cls))];
    }
    [self ping];
}

- (void)restoreCustomValues {
    NSDictionary *d = [_ud dictionaryRepresentation];
    for (NSString *k in d) {
        if ([k hasPrefix:@"WD.r."] || [k hasPrefix:@"WD.i."]) {
            [_ud removeObjectForKey:k];
        }
    }
    [_ud removeObjectForKey:@"WD.globalRadius"];
    [_ud removeObjectForKey:@"WD.globalInset"];
    [_ud setDouble:14.0 forKey:@"WD.globalRadius"];
    [_ud setDouble:12.0 forKey:@"WD.globalInset"];
    [self ping];
}

- (NSDictionary *)exportDictionary {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSDictionary *d = [_ud dictionaryRepresentation];
    for (NSString *k in d) {
        if ([k hasPrefix:@"WD."]) out[k] = d[k];
    }
    out[@"WD.exportVersion"] = WD_VERSION;
    out[@"WD.exportName"] = WD_DISPLAY_NAME;
    return out;
}

- (BOOL)importDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]] || dict.count == 0) return NO;
    NSInteger n = 0;
    for (NSString *k in dict) {
        if (![k isKindOfClass:[NSString class]]) continue;
        if (![k hasPrefix:@"WD."]) continue;
        if ([k isEqualToString:@"WD.exportVersion"] || [k isEqualToString:@"WD.exportName"]) continue;
        id v = dict[k];
        if (v) {
            [_ud setObject:v forKey:k];
            n++;
        }
    }
    if (n == 0) return NO;
    [self ping];
    return YES;
}

#pragma mark - 页面背景色

- (BOOL)bgEnabledForPage:(int)page {
    id v = [_ud objectForKey:WDBgOnKey(page)];
    return v ? [v boolValue] : NO;
}
- (void)setBgEnabled:(BOOL)on forPage:(int)page {
    [_ud setBool:on forKey:WDBgOnKey(page)];
    [self ping];
}
- (NSString *)bgHexForPage:(int)page dark:(BOOL)dark {
    return dark ? [_ud stringForKey:WDBgDarkKey(page)] : [_ud stringForKey:WDBgLitKey(page)];
}
- (void)setBgHex:(NSString *)hex forPage:(int)page dark:(BOOL)dark {
    if (hex.length) [_ud setObject:hex forKey:(dark ? WDBgDarkKey(page) : WDBgLitKey(page))];
    else [_ud removeObjectForKey:(dark ? WDBgDarkKey(page) : WDBgLitKey(page))];
    [self ping];
}
- (UIColor *)bgColorForPage:(int)page dark:(BOOL)dark {
    UIColor *c = WDColorForHex([self bgHexForPage:page dark:dark]);
    // 深色模式下若没单独设深色，回退到浅色值，避免"设了没反应"
    if (!c && dark) c = WDColorForHex([self bgHexForPage:page dark:NO]);
    return c;
}
- (void)resetPage:(int)page {
    [_ud removeObjectForKey:WDBgOnKey(page)];
    [_ud removeObjectForKey:WDBgLitKey(page)];
    [_ud removeObjectForKey:WDBgDarkKey(page)];
    [self ping];
}

- (void)reload { /* NSUserDefaults 同进程即时可读 */ }

- (void)ping {
    [_ud synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:WDPrefsDidChangeNotification object:nil];
}

@end
