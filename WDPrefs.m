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
- (void)setMaster:(BOOL)v {
    BOOL was = self.master;
    if (was == v) {
        [_ud setBool:v forKey:@"WD.master"];
        [self ping];
        return;
    }
    if (!v && was) {
        // 关掉：记下当前子开关，界面显示全关，数值保留。再开时按这份恢复。
        NSMutableDictionary *snap = [NSMutableDictionary dictionary];
        int n = WDCatalogCount();
        const WDItem *items = WDCatalogItems();
        for (int i = 0; i < n; i++) {
            NSString *name = @(items[i].cls);
            snap[name] = @([self enabledForClass:name def:items[i].defOn != 0]);
        }
        [_ud setObject:snap forKey:@"WD.master.savedOn"];
        [_ud setBool:[self cardOutEnabled] forKey:@"WD.master.savedBg"];
        [_ud setBool:[self cardInEnabled] forKey:@"WD.master.savedCardIn"];
        [_ud setBool:self.continuous forKey:@"WD.master.savedCont"];
    } else if (v && !was) {
        NSDictionary *snap = [_ud dictionaryForKey:@"WD.master.savedOn"];
        if ([snap isKindOfClass:[NSDictionary class]]) {
            for (NSString *name in snap) {
                id on = snap[name];
                if ([on respondsToSelector:@selector(boolValue)]) {
                    [_ud setBool:[on boolValue] forKey:WDOnKey(name)];
                }
            }
        }
        if ([_ud objectForKey:@"WD.master.savedBg"]) {
            [_ud setBool:[_ud boolForKey:@"WD.master.savedBg"] forKey:@"WD.bg.on"];
        }
        if ([_ud objectForKey:@"WD.master.savedCardIn"]) {
            [_ud setBool:[_ud boolForKey:@"WD.master.savedCardIn"] forKey:@"WD.card.in.on"];
        }
        if ([_ud objectForKey:@"WD.master.savedCont"]) {
            [_ud setBool:[_ud boolForKey:@"WD.master.savedCont"] forKey:@"WD.continuous"];
        }
        [_ud removeObjectForKey:@"WD.master.savedOn"];
        [_ud removeObjectForKey:@"WD.master.savedBg"];
        [_ud removeObjectForKey:@"WD.master.savedCardIn"];
        [_ud removeObjectForKey:@"WD.master.savedCont"];
    }
    [_ud setBool:v forKey:@"WD.master"];
    [self ping];
}

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

#pragma mark - 页面背景色（四页共用）

- (void)migratePageBgIfNeeded {
    if ([_ud objectForKey:@"WD.bg.migrated"]) return;
    if ([_ud objectForKey:@"WD.bg.on"] || [_ud objectForKey:@"WD.bg.l"] || [_ud objectForKey:@"WD.bg.d"]) {
        [_ud setBool:YES forKey:@"WD.bg.migrated"];
        return;
    }
    BOOL on = NO;
    NSString *lit = nil, *dark = nil;
    for (int page = 0; page < 4; page++) {
        if ([_ud boolForKey:WDBgOnKey(page)]) on = YES;
        if (!lit) lit = [_ud stringForKey:WDBgLitKey(page)];
        if (!dark) dark = [_ud stringForKey:WDBgDarkKey(page)];
    }
    if (on) [_ud setBool:YES forKey:@"WD.bg.on"];
    if (lit.length) [_ud setObject:lit forKey:@"WD.bg.l"];
    if (dark.length) [_ud setObject:dark forKey:@"WD.bg.d"];
    [_ud setBool:YES forKey:@"WD.bg.migrated"];
}

- (BOOL)bgEnabled {
    [self migratePageBgIfNeeded];
    id v = [_ud objectForKey:@"WD.bg.on"];
    return v ? [v boolValue] : NO;
}
- (void)setBgEnabled:(BOOL)on {
    [self migratePageBgIfNeeded];
    [_ud setBool:on forKey:@"WD.bg.on"];
    [self ping];
}
- (NSString *)bgHexDark:(BOOL)dark {
    [self migratePageBgIfNeeded];
    return dark ? [_ud stringForKey:@"WD.bg.d"] : [_ud stringForKey:@"WD.bg.l"];
}
- (void)setBgHex:(NSString *)hex dark:(BOOL)dark {
    [self migratePageBgIfNeeded];
    NSString *key = dark ? @"WD.bg.d" : @"WD.bg.l";
    if (hex.length) [_ud setObject:hex forKey:key];
    else [_ud removeObjectForKey:key];
    [self ping];
}
- (UIColor *)bgColorDark:(BOOL)dark {
    UIColor *c = WDColorForHex([self bgHexDark:dark]);
    if (!c && dark) c = WDColorForHex([self bgHexDark:NO]);
    return c;
}
- (void)resetBg {
    [_ud removeObjectForKey:@"WD.bg.on"];
    [_ud removeObjectForKey:@"WD.bg.l"];
    [_ud removeObjectForKey:@"WD.bg.d"];
    [_ud removeObjectForKey:@"WD.card.in.on"];
    [_ud removeObjectForKey:@"WD.card.in.l"];
    [_ud removeObjectForKey:@"WD.card.in.d"];
    [self ping];
}

- (BOOL)cardOutEnabled { return [self bgEnabled]; }
- (void)setCardOutEnabled:(BOOL)on { [self setBgEnabled:on]; }
- (NSString *)cardOutHexDark:(BOOL)dark { return [self bgHexDark:dark]; }
- (void)setCardOutHex:(NSString *)hex dark:(BOOL)dark { [self setBgHex:hex dark:dark]; }
- (UIColor *)cardOutColorDark:(BOOL)dark { return [self bgColorDark:dark]; }

- (BOOL)cardInEnabled {
    id v = [_ud objectForKey:@"WD.card.in.on"];
    return v ? [v boolValue] : NO;
}
- (void)setCardInEnabled:(BOOL)on {
    [_ud setBool:on forKey:@"WD.card.in.on"];
    [self ping];
}
- (NSString *)cardInHexDark:(BOOL)dark {
    return dark ? [_ud stringForKey:@"WD.card.in.d"] : [_ud stringForKey:@"WD.card.in.l"];
}
- (void)setCardInHex:(NSString *)hex dark:(BOOL)dark {
    NSString *key = dark ? @"WD.card.in.d" : @"WD.card.in.l";
    if (hex.length) [_ud setObject:hex forKey:key];
    else [_ud removeObjectForKey:key];
    [self ping];
}
- (UIColor *)cardInColorDark:(BOOL)dark {
    UIColor *c = WDColorForHex([self cardInHexDark:dark]);
    if (!c && dark) c = WDColorForHex([self cardInHexDark:NO]);
    return c;
}

- (void)ping {
    [_ud synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:WDPrefsDidChangeNotification object:nil];
}

@end
