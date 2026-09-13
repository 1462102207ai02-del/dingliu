// WechatDuo — 微信全页面卡片化
// TrollFools 裸 dylib：纯 ObjC runtime，不链 Substrate。
//
// v1.0.2 闪退修复：
// 1. constructor 里禁止 ObjC / NSUserDefaults / 同步 swizzle
// 2. 只 hook 本类方法；没有则 class_addMethod，绝不 method_setImplementation 改父类
// 3. 不 hook 系统类（UITableViewCell / UITableView / UISearchBar …）
// 4. 不再 hook setFrame:；layout 路径不写 frame
// 5. orig IMP 跳过我们自己的 IMP，避免父子互相递归

#import "WDCommon.h"
#import "WDCatalog.h"
#import "WDPrefs.h"
#import "WDStyle.h"
#import "WDSettings.h"
#import <signal.h>
#import <fcntl.h>
#import <unistd.h>
#import <string.h>
#import <stdio.h>
#import <stdlib.h>
#import <stdarg.h>

static NSMapTable *gOrig = nil;      // "ClassName|sel" -> NSValue(IMP)
static NSMapTable *gClassItem = nil; // Class -> NSValue(WDItem*)
static char gLogHome[512];
static char gLogTmp[512];
static int gSafe = 0;

#pragma mark - 纯 C 日志（constructor 可用）

static void WDLogC(const char *msg) {
    char line[768];
    int n = snprintf(line, sizeof(line), "[WechatDuo v%s] %s\n", "1.0.2", msg ? msg : "");
    if (n <= 0) return;
    const char *paths[2] = { gLogTmp[0] ? gLogTmp : NULL,
                             gLogHome[0] ? gLogHome : NULL };
    for (int i = 0; i < 2; i++) {
        if (!paths[i]) continue;
        int fd = open(paths[i], O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd < 0) continue;
        write(fd, line, (size_t)n);
        close(fd);
    }
}

static void WDInitLogPaths(void) {
    const char *tmp = getenv("TMPDIR");
    if (!tmp || !tmp[0]) tmp = "/tmp";
    snprintf(gLogTmp, sizeof(gLogTmp), "%s/WechatDuo.log", tmp);
    const char *home = getenv("HOME");
    if (home && home[0]) {
        snprintf(gLogHome, sizeof(gLogHome), "%s/Documents/WechatDuo.log", home);
    }
}

static void WDSignal(int sig) {
    char buf[64];
    snprintf(buf, sizeof(buf), "SIGNAL %d", sig);
    WDLogC(buf);
    signal(sig, SIG_DFL);
    raise(sig);
}

static void WDLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    WDLogC(s.UTF8String ?: "");
}

#pragma mark - swizzle

static NSString *WDKey(Class c, SEL s) {
    return [NSStringFromClass(c) stringByAppendingFormat:@"|%@", NSStringFromSelector(s)];
}

static void WDLayoutIMP(id self, SEL _cmd);
static id WDGetterIMP(id self, SEL _cmd);

static BOOL WDIsOurs(IMP imp) {
    return imp == (IMP)WDLayoutIMP || imp == (IMP)WDGetterIMP;
}

static BOOL WDOwns(Class c, SEL s) {
    if (!c || !s) return NO;
    unsigned n = 0;
    Method *list = class_copyMethodList(c, &n);
    if (!list) return NO;
    BOOL yes = NO;
    for (unsigned i = 0; i < n; i++) {
        if (method_getName(list[i]) == s) { yes = YES; break; }
    }
    free(list);
    return yes;
}

static BOOL WDSkipName(const char *name) {
    if (!name) return YES;
    static const char *kSkip[] = {
        "UIView", "UITableViewCell", "UITableView", "UICollectionViewCell",
        "UISearchBar", "UISearchBarTextField", "UITableViewHeaderFooterView",
        "UINavigationBar", "UITabBar", "UIScrollView", "UIControl",
        "MMTableView", "WCTableView",
        NULL
    };
    for (int i = 0; kSkip[i]; i++) {
        if (strcmp(name, kSkip[i]) == 0) return YES;
    }
    return NO;
}

static IMP WDOrig(id self, SEL cmd) {
    if (!gOrig || !self) return NULL;
    for (Class c = object_getClass(self); c; c = class_getSuperclass(c)) {
        NSValue *v = [gOrig objectForKey:WDKey(c, cmd)];
        if (!v) continue;
        IMP p = (IMP)[v pointerValue];
        if (p && !WDIsOurs(p)) return p;
    }
    return NULL;
}

static IMP WDResolveOrig(Class c, SEL s, IMP cur) {
    if (cur && !WDIsOurs(cur)) return cur;
    for (Class p = class_getSuperclass(c); p; p = class_getSuperclass(p)) {
        NSValue *v = gOrig ? [gOrig objectForKey:WDKey(p, s)] : nil;
        if (v) {
            IMP o = (IMP)[v pointerValue];
            if (o && !WDIsOurs(o)) return o;
        }
        Method m = class_getInstanceMethod(p, s);
        if (!m) continue;
        IMP o = method_getImplementation(m);
        if (o && !WDIsOurs(o)) return o;
    }
    return NULL;
}

static BOOL WDHookLayout(Class c) {
    if (!c) return NO;
    SEL s = @selector(layoutSubviews);
    Method m = class_getInstanceMethod(c, s);
    if (!m) return NO;
    IMP cur = method_getImplementation(m);
    if (WDIsOurs(cur) && WDOwns(c, s)) return NO;

    if (!gOrig) gOrig = [NSMapTable strongToStrongObjectsMapTable];
    IMP orig = WDResolveOrig(c, s, cur);
    if (!orig) return NO;

    [gOrig setObject:[NSValue valueWithPointer:orig] forKey:WDKey(c, s)];

    if (WDOwns(c, s)) {
        method_setImplementation(m, (IMP)WDLayoutIMP);
        return YES;
    }
    return class_addMethod(c, s, (IMP)WDLayoutIMP, method_getTypeEncoding(m));
}

static BOOL WDHookSel(Class c, SEL s, IMP neu) {
    if (!c || !s || !WDOwns(c, s)) return NO;
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
    if (!self || !gClassItem) return NULL;
    Class isa = object_getClass(self);
    NSValue *cached = [gClassItem objectForKey:(id)isa];
    if (cached) return (const WDItem *)[cached pointerValue];
    const WDItem *found = NULL;
    for (Class c = isa; c; c = class_getSuperclass(c)) {
        NSValue *v = [gClassItem objectForKey:(id)c];
        if (v) { found = (const WDItem *)[v pointerValue]; break; }
        if (c == [UIView class] || c == [NSObject class]) break;
    }
    [gClassItem setObject:[NSValue valueWithPointer:(void *)found] forKey:(id)isa];
    return found;
}

static void WDDispatch(id self) {
    if (!self) return;
    const WDItem *it = WDItemForView(self);
    if (!it) return;
    if (![self isKindOfClass:[UIView class]]) return;
    switch (it->kind) {
        case WDKindChrome: WDApplyChrome(self, it); break;
        case WDKindBanner: WDApplyBanner(self, it); break;
        case WDKindCell: {
            if (![self isKindOfClass:[UITableViewCell class]]) {
                WDApplyView(self, it);
                break;
            }
            WDApplyCell((UITableViewCell *)self, nil, nil, it);
            break;
        }
        case WDKindBubble: WDApplyBubble(self, it); break;
        default: WDApplyView(self, it); break;
    }
}

static void WDLayoutIMP(id self, SEL _cmd) {
    IMP orig = WDOrig(self, _cmd);
    if (orig && orig != (IMP)WDLayoutIMP) {
        ((void(*)(id, SEL))orig)(self, _cmd);
    }
    @try { WDDispatch(self); } @catch (NSException *e) {}
}

static id WDGetterIMP(id self, SEL _cmd) {
    IMP orig = WDOrig(self, _cmd);
    id r = orig ? ((id(*)(id, SEL))orig)(self, _cmd) : nil;
    @try {
        if ([r isKindOfClass:[UIView class]]) {
            const WDItem *it = NULL;
            if (gClassItem) {
                NSValue *v = [gClassItem objectForKey:(id)[self class]];
                if (v) it = (const WDItem *)[v pointerValue];
            }
            if (it) WDApplyView(r, it);
        }
    } @catch (NSException *e) {}
    return r;
}

static const struct { const char *cls; const char *sel; } kGetters[] = {
    {"WCSearchViewController", "navBarContainerView"},
    {"MMNewMsgContentNavBar", "bgMaskView"},
    {"MMInputMsgReferView", "thumbImageView"},
};

#pragma mark - 设置入口（只改本类方法）

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

static void WDHookOwnedOrAdd(Class cls, SEL sel, IMP neu, IMP *slot) {
    if (!cls || *slot) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP cur = method_getImplementation(m);
    if (cur == neu) return;
    IMP orig = WDResolveOrig(cls, sel, cur);
    if (!orig) orig = cur;
    *slot = orig;
    if (WDOwns(cls, sel)) {
        method_setImplementation(m, neu);
        return;
    }
    class_addMethod(cls, sel, neu, method_getTypeEncoding(m));
}

static void WDHookEntry(NSString *clsName) {
    Class cls = NSClassFromString(clsName);
    if (!cls) return;
    WDHookOwnedOrAdd(cls, @selector(numberOfSectionsInTableView:), (IMP)WDMoreSec, &gSec);
    WDHookOwnedOrAdd(cls, @selector(tableView:numberOfRowsInSection:), (IMP)WDMoreRows, &gRows);
    WDHookOwnedOrAdd(cls, @selector(tableView:cellForRowAtIndexPath:), (IMP)WDMoreCell, &gCell);
    WDHookOwnedOrAdd(cls, @selector(tableView:didSelectRowAtIndexPath:), (IMP)WDMoreSelect, &gSel);
}

#pragma mark - 插件收纳

static IMP gMinVDL = NULL;
static BOOL gReg = NO;
static void WDMinVDL(id self, SEL cmd) {
    if (gMinVDL && gMinVDL != (IMP)WDMinVDL)
        ((void(*)(id, SEL))gMinVDL)(self, cmd);
    if (gReg || !objc_getClass("WCPluginsMgr")) return;
    gReg = YES;
    @try {
        Class mgr = objc_getClass("WCPluginsMgr");
        id inst = ((id(*)(id, SEL))objc_msgSend)(mgr, @selector(sharedInstance));
        SEL reg = @selector(registerControllerWithTitle:version:controller:);
        if (inst && [inst respondsToSelector:reg]) {
            ((void(*)(id, SEL, id, id, id))objc_msgSend)(inst, reg,
                WD_DISPLAY_NAME, WD_VERSION, WD_SETTINGS_CLS);
        }
    } @catch (NSException *e) {}
}

static void WDHookPlugin(void) {
    if (gMinVDL) return;
    Class min = NSClassFromString(@"MinimizeViewController");
    if (!min) return;
    SEL s = @selector(viewDidLoad);
    Method m = class_getInstanceMethod(min, s);
    if (!m) return;
    IMP cur = method_getImplementation(m);
    gMinVDL = WDResolveOrig(min, s, cur) ?: cur;
    if (WDOwns(min, s)) {
        method_setImplementation(m, (IMP)WDMinVDL);
    } else {
        class_addMethod(min, s, (IMP)WDMinVDL, method_getTypeEncoding(m));
    }
}

#pragma mark - 安装

static void WDRememberClass(Class c, const WDItem *it) {
    if (!c || !it) return;
    if (!gClassItem) gClassItem = [NSMapTable strongToStrongObjectsMapTable];
    [gClassItem setObject:[NSValue valueWithPointer:(void *)it] forKey:(id)c];
}

static void WDInstallHooks(void) {
    int n = WDCatalogCount();
    const WDItem *items = WDCatalogItems();
    int ok = 0, miss = 0, skip = 0;
    for (int i = 0; i < n; i++) {
        const char *name = items[i].cls;
        if (WDSkipName(name)) { skip++; continue; }
        Class c = objc_getClass(name);
        if (!c) { miss++; continue; }
        WDRememberClass(c, &items[i]);
        if (![c isSubclassOfClass:[UIView class]]) continue;
        if (WDHookLayout(c)) ok++;
    }
    for (size_t i = 0; i < sizeof(kGetters)/sizeof(kGetters[0]); i++) {
        Class c = objc_getClass(kGetters[i].cls);
        if (!c) continue;
        SEL s = sel_registerName(kGetters[i].sel);
        WDHookSel(c, s, (IMP)WDGetterIMP);
    }
    char buf[128];
    snprintf(buf, sizeof(buf), "hooks: ok=%d miss=%d skip=%d", ok, miss, skip);
    WDLogC(buf);
}

static void WDInstallOnce(void) {
    @autoreleasepool {
        @try {
            [WDPrefs shared];
            NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
            if ([ud boolForKey:@"WDSafeMode"]) {
                gSafe = 1;
                WDLogC("SAFE MODE — no visual hooks");
                WDHookEntry(@"MoreViewController");
                WDHookEntry(@"NewSettingViewController");
                WDHookPlugin();
                return;
            }
            WDInstallHooks();
            WDHookEntry(@"MoreViewController");
            WDHookEntry(@"NewSettingViewController");
            WDHookPlugin();
        } @catch (NSException *e) {
            WDLog([NSString stringWithFormat:@"install exception: %@ %@", e.name, e.reason]);
        }
    }
}

static void WDBoot(void) {
    WDLogC("boot main");
    WDInstallOnce();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ WDInstallOnce(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ WDInstallOnce(); });
    [[NSNotificationCenter defaultCenter] addObserverForName:WDPrefsDidChangeNotification
                                                      object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *n) {
        WDStyleVisibleTables();
    }];
}

__attribute__((constructor))
static void wechatduo_init(void) {
    WDInitLogPaths();
    WDLogC("ctor");
    signal(SIGSEGV, WDSignal);
    signal(SIGBUS, WDSignal);
    signal(SIGABRT, WDSignal);
    signal(SIGTRAP, WDSignal);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(800 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{ WDBoot(); });
}
