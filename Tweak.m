// WechatDuo — 微信全页面卡片化
// TrollFools 裸 dylib：纯 ObjC runtime，不链 Substrate。
//
// v1.0.3（对照用户日志）：
//   [ctor] → [boot main] → [hooks: ok=97] 之后闪退，无 SIGNAL。
//   栈已耗尽：97 个类共用同一个 WDLayoutIMP，WDOrig(self) 按实例 class 找 orig。
//   子类 [super layoutSubviews] → 父类已被换成同一 IMP → 再取子类 orig → 无限递归。
//   SIGKILL / 栈耗尽时 signal handler 写不出日志。这是 dingliu 同一错误。
//
// 禁止：
//   - 共享 IMP + 按实例 class 沿继承链找 orig
//   - class_addMethod 给没实现 layoutSubviews 的类补方法
//   - 热路径 NSStringFromClass / NSUserDefaults / layer.mask / 写宿主 frame
//   - 启动期装饰、reloadData、hook 系统类 / 表类 / 输入框
//
// 只做：
//   - 本类已有 layoutSubviews 才替换
//   - 每类独立 block IMP，orig 捕获在闭包里，super 不会撞回同一条
//   - 启动 2.5s 后才允许装饰

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

static char gLogHome[512];
static char gLogTmp[512];
static volatile int gLive = 0;
static volatile int gDepth = 0;
static int gInstalled = 0;
static int gSafe = 0;
static BOOL gMaster = YES;
static BOOL gContinuous = YES;

typedef struct { char on; float r; float i; } WDSnap;
static WDSnap gSnap[160];

#define WD_MAX_DEPTH 6

#pragma mark - C 日志

static void WDLogC(const char *msg) {
    char line[768];
    int n = snprintf(line, sizeof(line), "[WechatDuo v%s] %s\n", WD_VERSION_C, msg ? msg : "");
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
    char buf[80];
    snprintf(buf, sizeof(buf), "SIGNAL %d live=%d depth=%d", sig, gLive, gDepth);
    WDLogC(buf);
    signal(sig, SIG_DFL);
    raise(sig);
}

#pragma mark - 黑名单

static BOOL WDSkipName(const char *name) {
    if (!name || !name[0]) return YES;
    static const char *kSkip[] = {
        "UIView", "UIControl", "UIScrollView", "UIButton", "UILabel", "UIImageView",
        "UITableView", "UITableViewCell", "UITableViewHeaderFooterView",
        "UITableViewCellContentView", "UICollectionView", "UICollectionViewCell",
        "UISearchBar", "UISearchBarTextField", "UITextField", "UITextView",
        "UINavigationBar", "UITabBar", "UIToolbar", "UIWindow",
        "MMTableView", "WCTableView",
        "MMGrowTextView", "MMGrowTextViewWithExtras",
        NULL
    };
    for (int i = 0; kSkip[i]; i++) {
        if (strcmp(name, kSkip[i]) == 0) return YES;
    }
    if (strncmp(name, "UI", 2) == 0) return YES;
    if (strncmp(name, "_UI", 3) == 0) return YES;
    return NO;
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

#pragma mark - 快照（热路径不碰 NSUserDefaults / NSString）

static void WDSnapshot(void) {
    WDPrefs *p = [WDPrefs shared];
    gMaster = p.master;
    gContinuous = p.continuous;
    int n = WDCatalogCount();
    if (n > 160) n = 160;
    const WDItem *items = WDCatalogItems();
    for (int i = 0; i < n; i++) {
        NSString *name = @(items[i].cls);
        gSnap[i].on = [p enabledForClass:name def:items[i].defOn != 0] ? 1 : 0;
        gSnap[i].r = (float)[p radiusForClass:name def:items[i].defRadius];
        gSnap[i].i = (float)[p insetForClass:name def:items[i].defInset];
        if (items[i].kind == WDKindBubble) gSnap[i].i = 0;
    }
}

static void WDDecorate(id self, int idx, int kind) {
    if (idx < 0 || idx >= 160) return;
    if (!gSnap[idx].on) return;
    if (![self isKindOfClass:[UIView class]]) return;
    UIView *v = (UIView *)self;
    CGFloat r = gSnap[idx].r;
    if (kind == WDKindCell && [v isKindOfClass:[UITableViewCell class]]) {
        WDStyleCell((UITableViewCell *)v, gSnap[idx].i, r, gContinuous);
        return;
    }
    WDStyleRound(v, r, gContinuous);
}

#pragma mark - 每类独立 IMP（捕获该类 orig，super 不会撞回同一条）

static BOOL WDHookLayout(Class c, int idx, int kind) {
    if (!c) return NO;
    SEL s = @selector(layoutSubviews);
    if (!WDOwns(c, s)) return NO;
    Method m = class_getInstanceMethod(c, s);
    if (!m) return NO;
    IMP orig = method_getImplementation(m);
    if (!orig) return NO;

    IMP stub = imp_implementationWithBlock(^(id slf) {
        ((void(*)(id, SEL))orig)(slf, s);
        if (!gLive || !gMaster || gSafe) return;
        if (gDepth >= WD_MAX_DEPTH) return;
        gDepth++;
        @try { WDDecorate(slf, idx, kind); } @catch (NSException *e) {}
        gDepth--;
    });
    if (!stub) return NO;
    method_setImplementation(m, stub);
    return YES;
}

#pragma mark - getter（只改本类已有方法）

static const struct { const char *cls; const char *sel; } kGetters[] = {
    {"WCSearchViewController", "navBarContainerView"},
    {"MMNewMsgContentNavBar", "bgMaskView"},
};
static IMP gGetOrig[2];
static int gGetIdx[2] = { -1, -1 };

static id WDGetterIMP(id self, SEL _cmd) {
    IMP orig = NULL;
    int idx = -1;
    for (size_t i = 0; i < 2; i++) {
        if (!gGetOrig[i]) continue;
        if (sel_isEqual(_cmd, sel_registerName(kGetters[i].sel))) {
            orig = gGetOrig[i];
            idx = gGetIdx[i];
            break;
        }
    }
    id r = orig ? ((id(*)(id, SEL))orig)(self, _cmd) : nil;
    if (gLive && gMaster && !gSafe && idx >= 0 && [r isKindOfClass:[UIView class]]) {
        WDStyleRound((UIView *)r, gSnap[idx].r, gContinuous);
    }
    return r;
}

static int WDIndexOfClassName(const char *name) {
    int n = WDCatalogCount();
    const WDItem *items = WDCatalogItems();
    for (int i = 0; i < n; i++) {
        if (strcmp(items[i].cls, name) == 0) return i;
    }
    return -1;
}

static void WDInstallGetters(void) {
    for (size_t i = 0; i < sizeof(kGetters)/sizeof(kGetters[0]); i++) {
        Class c = objc_getClass(kGetters[i].cls);
        if (!c) continue;
        SEL s = sel_registerName(kGetters[i].sel);
        if (!WDOwns(c, s)) continue;
        Method m = class_getInstanceMethod(c, s);
        if (!m) continue;
        IMP cur = method_getImplementation(m);
        if (cur == (IMP)WDGetterIMP) continue;
        gGetOrig[i] = cur;
        gGetIdx[i] = WDIndexOfClassName(kGetters[i].cls);
        method_setImplementation(m, (IMP)WDGetterIMP);
    }
}

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

static void WDHookOwnedOrAdd(Class cls, SEL sel, IMP neu, IMP *slot) {
    if (!cls || *slot) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP cur = method_getImplementation(m);
    if (cur == neu) return;
    *slot = cur;
    if (WDOwns(cls, sel)) {
        method_setImplementation(m, neu);
        return;
    }
    class_addMethod(cls, sel, neu, method_getTypeEncoding(m));
}

static void WDHookEntry(const char *clsName) {
    Class cls = objc_getClass(clsName);
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
    Class min = objc_getClass("MinimizeViewController");
    if (!min) return;
    SEL s = @selector(viewDidLoad);
    Method m = class_getInstanceMethod(min, s);
    if (!m) return;
    gMinVDL = method_getImplementation(m);
    if (WDOwns(min, s)) method_setImplementation(m, (IMP)WDMinVDL);
    else class_addMethod(min, s, (IMP)WDMinVDL, method_getTypeEncoding(m));
}

#pragma mark - 安装

static void WDInstallHooks(void) {
    int n = WDCatalogCount();
    const WDItem *items = WDCatalogItems();
    int ok = 0, miss = 0, skip = 0, noown = 0;
    for (int i = 0; i < n; i++) {
        const char *name = items[i].cls;
        if (WDSkipName(name)) { skip++; continue; }
        Class c = objc_getClass(name);
        if (!c) { miss++; continue; }
        if (![c isSubclassOfClass:[UIView class]]) { skip++; continue; }
        if (WDHookLayout(c, i, items[i].kind)) ok++;
        else noown++;
    }
    WDInstallGetters();
    char buf[160];
    snprintf(buf, sizeof(buf), "hooks: ok=%d miss=%d skip=%d noown=%d", ok, miss, skip, noown);
    WDLogC(buf);
}

static void WDInstallOnce(void) {
    if (gInstalled) return;
    gInstalled = 1;
    @autoreleasepool {
        @try {
            [WDPrefs shared];
            WDSnapshot();
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"WDSafeMode"]) {
                gSafe = 1;
                WDLogC("SAFE MODE");
                WDHookEntry("MoreViewController");
                WDHookEntry("NewSettingViewController");
                WDHookPlugin();
                return;
            }
            WDInstallHooks();
            WDHookEntry("MoreViewController");
            WDHookEntry("NewSettingViewController");
            WDHookPlugin();
        } @catch (NSException *e) {
            WDLogC("install exception");
        }
    }
}

static void WDGoLive(void) {
    if (gLive) return;
    WDSnapshot();
    gLive = 1;
    WDLogC("live");
}

static void WDBoot(void) {
    WDLogC("boot main");
    WDInstallOnce();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2500 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{ WDGoLive(); });
    [[NSNotificationCenter defaultCenter] addObserverForName:WDPrefsDidChangeNotification
                                                      object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *n) {
        WDSnapshot();
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
