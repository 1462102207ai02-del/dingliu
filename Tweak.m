// WechatDuo — 微信全页面卡片化
// TrollFools 裸 dylib：纯 ObjC runtime，不链 Substrate。

#import "WDCommon.h"
#import "WDCatalog.h"
#import "WDPrefs.h"
#import "WDStyle.h"
#import "WDSettings.h"
#import <signal.h>
#import <fcntl.h>
#import <unistd.h>
#import <string.h>
#import <stdarg.h>

static NSMapTable *gOrig = nil;
static char gLogPath[512];

static NSString *WDKey(Class c, SEL s) {
    return [NSStringFromClass(c) stringByAppendingFormat:@"|%@", NSStringFromSelector(s)];
}
static IMP WDOrig(id self, SEL cmd) {
    if (!gOrig) return NULL;
    for (Class c = object_getClass(self); c; c = class_getSuperclass(c)) {
        NSValue *v = [gOrig objectForKey:WDKey(c, cmd)];
        if (v) return (IMP)[v pointerValue];
    }
    return NULL;
}

static void WDLayoutIMP(id self, SEL _cmd);
static void WDFrameIMP(id self, SEL _cmd, CGRect f);
static id WDGetterIMP(id self, SEL _cmd);
static BOOL WDIsOurs(IMP imp) {
    return imp == (IMP)WDLayoutIMP || imp == (IMP)WDFrameIMP || imp == (IMP)WDGetterIMP;
}
static BOOL WDSwizzle(Class c, SEL s, IMP neu) {
    if (!c) return NO;
    Method m = class_getInstanceMethod(c, s);
    if (!m) return NO;
    IMP cur = method_getImplementation(m);
    if (WDIsOurs(cur)) return NO;
    if (!gOrig) gOrig = [NSMapTable strongToStrongObjectsMapTable];
    [gOrig setObject:[NSValue valueWithPointer:cur] forKey:WDKey(c, s)];
    method_setImplementation(m, neu);
    return YES;
}

static const WDItem *WDItemForView(id self) {
    for (Class c = [self class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        const WDItem *it = WDCatalogFind(NSStringFromClass(c));
        if (it) return it;
    }
    return NULL;
}

static void WDDispatch(id self) {
    if (![self isKindOfClass:[UIView class]]) return;
    const WDItem *it = WDItemForView(self);
    if (!it) return;
    switch (it->kind) {
        case WDKindChrome: WDApplyChrome(self, it); break;
        case WDKindBanner: WDApplyBanner(self, it); break;
        case WDKindCell: {
            UITableViewCell *cell = (UITableViewCell *)self;
            if (![cell isKindOfClass:[UITableViewCell class]]) {
                WDApplyView(self, it); break;
            }
            UITableView *tv = nil;
            for (UIView *p = cell.superview; p; p = p.superview) {
                if ([p isKindOfClass:[UITableView class]]) { tv = (UITableView *)p; break; }
            }
            WDApplyCell(cell, tv, tv ? [tv indexPathForCell:cell] : nil, it);
            break;
        }
        case WDKindBubble: WDApplyBubble(self, it); break;
        default: WDApplyView(self, it); break;
    }
}

static void WDLayoutIMP(id self, SEL _cmd) {
    IMP orig = WDOrig(self, _cmd);
    if (orig) ((void(*)(id, SEL))orig)(self, _cmd);
    @try { WDDispatch(self); } @catch (NSException *e) {}
}

static void WDFrameIMP(id self, SEL _cmd, CGRect f) {
    IMP orig = WDOrig(self, _cmd);
    if (orig) ((void(*)(id, SEL, CGRect))orig)(self, _cmd, f);
    @try { WDDispatch(self); } @catch (NSException *e) {}
}

static id WDGetterIMP(id self, SEL _cmd) {
    IMP orig = WDOrig(self, _cmd);
    id r = orig ? ((id(*)(id, SEL))orig)(self, _cmd) : nil;
    @try {
        if ([r isKindOfClass:[UIView class]]) {
            const WDItem *it = WDCatalogFind(NSStringFromClass([self class]));
            if (it) WDApplyView(r, it);
        }
    } @catch (NSException *e) {}
    return r;
}

// WCSearchViewController.navBarContainerView / MMNewMsgContentNavBar.bgMaskView
static const struct { const char *cls; const char *sel; } kGetters[] = {
    {"WCSearchViewController", "navBarContainerView"},
    {"MMNewMsgContentNavBar", "bgMaskView"},
    {"MMInputMsgReferView", "thumbImageView"},
};

#pragma mark - 设置入口

static IMP gSec, gRows, gCell, gSel;
static NSInteger WDMoreSec(id self, SEL cmd, id tv) {
    NSInteger n = gSec ? ((NSInteger(*)(id, SEL, id))gSec)(self, cmd, tv) : 0;
    return n + 1;
}
static NSInteger WDMoreRows(id self, SEL cmd, id tv, NSInteger section) {
    NSInteger sections = gSec ? ((NSInteger(*)(id, SEL, id))gSec)(self, cmd, tv) : 0;
    if (section == sections) return 1;
    return gRows ? ((NSInteger(*)(id, SEL, id, NSInteger))gRows)(self, cmd, tv, section) : 0;
}
static UITableViewCell *WDMoreCell(id self, SEL cmd, id tv, NSIndexPath *ip) {
    NSInteger sections = gSec ? ((NSInteger(*)(id, SEL, id))gSec)(self, cmd, tv) : 0;
    if (ip.section == sections) {
        UITableViewCell *c = [(UITableView *)tv dequeueReusableCellWithIdentifier:@"WDEntry"];
        if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"WDEntry"];
        c.textLabel.text = WD_DISPLAY_NAME;
        c.detailTextLabel.text = @"卡片化 · 圆角 · 缩进";
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    return gCell ? ((UITableViewCell*(*)(id, SEL, id, NSIndexPath*))gCell)(self, cmd, tv, ip) : nil;
}
static void WDMoreSelect(id self, SEL cmd, id tv, NSIndexPath *ip) {
    NSInteger sections = gSec ? ((NSInteger(*)(id, SEL, id))gSec)(self, cmd, tv) : 0;
    if (ip.section == sections) {
        [(UITableView *)tv deselectRowAtIndexPath:ip animated:YES];
        WDPushSettings();
        return;
    }
    if (gSel) ((void(*)(id, SEL, id, NSIndexPath*))gSel)(self, cmd, tv, ip);
}
static void WDHookEntry(NSString *clsName) {
    Class cls = NSClassFromString(clsName);
    if (!cls) return;
    Method m;
    if (!gSec && (m = class_getInstanceMethod(cls, @selector(numberOfSectionsInTableView:)))) {
        gSec = method_getImplementation(m); method_setImplementation(m, (IMP)WDMoreSec);
    }
    if (!gRows && (m = class_getInstanceMethod(cls, @selector(tableView:numberOfRowsInSection:)))) {
        gRows = method_getImplementation(m); method_setImplementation(m, (IMP)WDMoreRows);
    }
    if (!gCell && (m = class_getInstanceMethod(cls, @selector(tableView:cellForRowAtIndexPath:)))) {
        gCell = method_getImplementation(m); method_setImplementation(m, (IMP)WDMoreCell);
    }
    if (!gSel && (m = class_getInstanceMethod(cls, @selector(tableView:didSelectRowAtIndexPath:)))) {
        gSel = method_getImplementation(m); method_setImplementation(m, (IMP)WDMoreSelect);
    }
}

#pragma mark - 插件收纳

static IMP gMinVDL = NULL;
static BOOL gReg = NO;
static void WDMinVDL(id self, SEL cmd) {
    if (gMinVDL) ((void(*)(id, SEL))gMinVDL)(self, cmd);
    if (gReg || !NSClassFromString(@"WCPluginsMgr")) return;
    gReg = YES;
    @try {
        Class mgr = objc_getClass("WCPluginsMgr");
        id inst = [mgr performSelector:@selector(sharedInstance)];
        SEL reg = @selector(registerControllerWithTitle:version:controller:);
        if (inst && [inst respondsToSelector:reg]) {
            ((void(*)(id, SEL, id, id, id))objc_msgSend)(inst, reg,
                WD_DISPLAY_NAME, WD_VERSION, WD_SETTINGS_CLS);
        }
    } @catch (NSException *e) {}
}

#pragma mark - 日志

static void WDLogRaw(const char *msg) {
    if (!gLogPath[0]) return;
    int fd = open(gLogPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    write(fd, msg, strlen(msg));
    close(fd);
}
static void WDLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"[WechatDuo v%@] %@\n", WD_VERSION, s];
    NSLog(@"%@", line);
    WDLogRaw(line.UTF8String);
}

#pragma mark - 安装

static void WDInstallHooks(void) {
    int n = WDCatalogCount();
    const WDItem *items = WDCatalogItems();
    int ok = 0;
    NSMutableSet *seen = [NSMutableSet set];
    for (int i = 0; i < n; i++) {
        NSString *name = @(items[i].cls);
        if ([seen containsObject:name]) continue;
        [seen addObject:name];
        Class c = NSClassFromString(name);
        if (!c) continue;
        SEL layout = @selector(layoutSubviews);
        SEL frame = @selector(setFrame:);
        if (class_getInstanceMethod(c, layout)) {
            if (WDSwizzle(c, layout, (IMP)WDLayoutIMP)) ok++;
        }
        if (items[i].kind == WDKindCell || items[i].kind == WDKindChrome || items[i].kind == WDKindBanner) {
            if (class_getInstanceMethod(c, frame)) WDSwizzle(c, frame, (IMP)WDFrameIMP);
        }
    }
    for (size_t i = 0; i < sizeof(kGetters)/sizeof(kGetters[0]); i++) {
        Class c = NSClassFromString(@(kGetters[i].cls));
        if (!c) continue;
        SEL s = sel_registerName(kGetters[i].sel);
        WDSwizzle(c, s, (IMP)WDGetterIMP);
    }
    WDLog(@"hooks installed: %d classes", ok);
}

__attribute__((constructor))
static void wechatduo_init(void) {
    @autoreleasepool {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        if (!docs) docs = NSHomeDirectory();
        NSString *p = [docs stringByAppendingPathComponent:WD_LOG_NAME];
        strncpy(gLogPath, p.fileSystemRepresentation, sizeof(gLogPath) - 1);
        WDLog(@"loaded");

        [WDPrefs shared];

        @try {
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"WDSafeMode"]) {
                WDLog(@"SAFE MODE");
            } else {
                WDInstallHooks();
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{ WDInstallHooks(); });
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{ WDInstallHooks(); });
            }
            WDHookEntry(@"MoreViewController");
            WDHookEntry(@"NewSettingViewController");
            Class min = NSClassFromString(@"MinimizeViewController");
            if (min) {
                Method m = class_getInstanceMethod(min, @selector(viewDidLoad));
                if (m) {
                    gMinVDL = method_getImplementation(m);
                    method_setImplementation(m, (IMP)WDMinVDL);
                }
            }
            [[NSNotificationCenter defaultCenter] addObserverForName:WDPrefsDidChangeNotification
                                                              object:nil queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(__unused NSNotification *n) {
                WDStyleVisibleTables();
            }];
        } @catch (NSException *e) {
            WDLog(@"init exception: %@ — %@", e.name, e.reason);
        }
    }
}
