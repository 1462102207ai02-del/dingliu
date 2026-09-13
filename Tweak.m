// WechatDuo — 微信全页面卡片化
// TrollFools 裸 dylib：纯 ObjC runtime，不链 Substrate。
//
// v1.1.0
//   1) 挂载策略：沿父类链找到「真正实现 layoutSubviews」的那个类再替换 IMP。
//      旧版只在本类实现了才挂，导致首页会话列表（NewMainFrameCell 自己没有
//      layoutSubviews，实现在 MMTableViewCell）完全没被装饰 —— 看不到缩进。
//   2) 每类独立 block IMP，orig 捕获在闭包里，super 不会撞回同一条（v1.0.3 修复保留）。
//   3) 运行期按实例真实类解析配置下标（8 槽直址缓存，热路径无字符串）。
//   4) 开关真实可逆：所有装饰都记录原值；总开关或单类开关一关，
//      立刻遍历窗口把已装饰的视图还原，杜绝残留。
//   5) 四个 Tab 页（微信/通讯录/发现/我）背景色支持浅色/深色分别自定义。
//
// 禁止：
//   - 共享 IMP + 按实例 class 沿继承链找 orig
//   - 给没实现 layoutSubviews 的类补方法（class_addMethod）
//   - 热路径 NSStringFromClass / NSUserDefaults / layer.mask
//   - 启动期装饰、reloadData、hook 硬黑名单里的基类

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

typedef struct { char on; float r; float i; int kind; } WDSnap;
static WDSnap gSnap[160];

// 四个 Tab 之外的页面也预留，方便以后扩展
static char gPageOn[8];
static char gPageHex[8][2][16];

#define WD_MAX_DEPTH 6
#define WD_ASSOC OBJC_ASSOCIATION_RETAIN_NONATOMIC

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

// 硬黑名单：这些基类一旦替换 IMP 会影响整个 App，坚决不碰
static BOOL WDHardSkip(const char *name) {
    if (!name || !name[0]) return YES;
    static const char *k[] = {
        "UIView", "UIControl", "UIScrollView", "UIButton", "UILabel", "UIImageView",
        "UITableView", "UITableViewCell", "UICollectionView", "UICollectionViewCell",
        "UITableViewCellContentView", "UITableViewHeaderFooterView",
        "UINavigationBar", "UITabBar", "UIToolbar", "UIWindow",
        "MMTableView", "WCTableView",
        NULL
    };
    for (int i = 0; k[i]; i++) {
        if (strcmp(name, k[i]) == 0) return YES;
    }
    return NO;
}

// 软黑名单：系统类只在「它自己就是目录项」时才允许挂载（例如 UISearchBar）
static BOOL WDSoftSkip(const char *name) {
    if (!name || !name[0]) return YES;
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

// 沿父类链找到真正实现 layoutSubviews 的类；撞到黑名单就放弃
static Class WDOwnerClass(Class c, SEL s) {
    for (Class k = c; k; k = class_getSuperclass(k)) {
        const char *nm = class_getName(k);
        if (WDHardSkip(nm)) return Nil;
        if (k != c && WDSoftSkip(nm)) return Nil;
        if (WDOwns(k, s)) return k;
    }
    return Nil;
}

#pragma mark - 类 → 配置下标（热路径：指针比较 + 8 槽直址缓存）

typedef struct { Class cls; int idx; } WDClsEnt;
static WDClsEnt gCls[256];
static int gClsN = 0;
static Class gCacheCls[8];
static int  gCacheIdx[8];

static void WDIdxCacheReset(void) {
    for (int i = 0; i < 8; i++) { gCacheCls[i] = Nil; gCacheIdx[i] = -1; }
}

static void WDClsAdd(Class c, int idx) {
    if (!c || gClsN >= 256) return;
    for (int i = 0; i < gClsN; i++) if (gCls[i].cls == c) return;
    gCls[gClsN].cls = c;
    gCls[gClsN].idx = idx;
    gClsN++;
}

static int WDIdxForClass(Class c) {
    if (!c) return -1;
    NSUInteger h = ((NSUInteger)c >> 4) & 7u;
    if (gCacheCls[h] == c) return gCacheIdx[h];
    int found = -1;
    for (int i = 0; i < gClsN; i++) {
        if (gCls[i].cls == c) { found = gCls[i].idx; break; }
    }
    gCacheCls[h] = c;
    gCacheIdx[h] = found;
    return found;
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
        gSnap[i].kind = items[i].kind;
        if (items[i].kind == WDKindBubble) gSnap[i].i = 0;
    }
    for (int pg = 0; pg < (int)WDPageCount && pg < 8; pg++) {
        gPageOn[pg] = [p bgEnabledForPage:pg] ? 1 : 0;
        NSString *l = [p bgHexForPage:pg dark:NO];
        NSString *d = [p bgHexForPage:pg dark:YES];
        gPageHex[pg][0][0] = 0;
        gPageHex[pg][1][0] = 0;
        if (l.length) snprintf(gPageHex[pg][0], 16, "%s", l.UTF8String);
        if (d.length) snprintf(gPageHex[pg][1], 16, "%s", d.UTF8String);
    }
}

static void WDDecorate(id self, int idx) {
    if (idx < 0 || idx >= 160) return;
    if (!gSnap[idx].on) return;
    if (![self isKindOfClass:[UIView class]]) return;
    UIView *v = (UIView *)self;
    if (gSnap[idx].kind == WDKindCell && [v isKindOfClass:[UITableViewCell class]]) {
        WDStyleCell((UITableViewCell *)v, gSnap[idx].i, gSnap[idx].r, gContinuous, idx);
        return;
    }
    WDStyleRound(v, gSnap[idx].r, gContinuous, idx);
}

#pragma mark - 每类独立 IMP（捕获该类 orig，super 不会撞回同一条）

static Class gHookedOwner[256];
static int gHookedN = 0;

static BOOL WDHookOwner(Class owner, int fallbackIdx) {
    if (!owner) return NO;
    for (int i = 0; i < gHookedN; i++) if (gHookedOwner[i] == owner) return YES;
    SEL s = @selector(layoutSubviews);
    Method m = class_getInstanceMethod(owner, s);
    if (!m) return NO;
    IMP orig = method_getImplementation(m);
    if (!orig) return NO;

    IMP stub = imp_implementationWithBlock(^(id slf) {
        ((void (*)(id, SEL))orig)(slf, s);
        if (!gLive || !gMaster || gSafe) return;
        if (![NSThread isMainThread]) return;
        if (gDepth >= WD_MAX_DEPTH) return;
        int idx = WDIdxForClass(object_getClass(slf));
        if (idx < 0) idx = fallbackIdx;
        if (idx < 0) return;
        gDepth++;
        @try { WDDecorate(slf, idx); } @catch (NSException *e) {}
        gDepth--;
    });
    if (!stub) return NO;
    method_setImplementation(m, stub);
    if (gHookedN < 256) gHookedOwner[gHookedN++] = owner;
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
    id r = orig ? ((id (*)(id, SEL))orig)(self, _cmd) : nil;
    if (gLive && gMaster && !gSafe && idx >= 0 && gSnap[idx].on && [r isKindOfClass:[UIView class]]) {
        WDStyleRound((UIView *)r, gSnap[idx].r, gContinuous, idx);
    }
    return r;
}

static int WDIndexOfClassName(const char *name) {
    return WDCatalogIndexOf([NSString stringWithUTF8String:name]);
}

static void WDInstallGetters(void) {
    for (size_t i = 0; i < sizeof(kGetters) / sizeof(kGetters[0]); i++) {
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

#pragma mark - 四个 Tab 页背景色

static const void *kWDPageOrigKey = &kWDPageOrigKey;

static BOOL WDIsDarkMode(void) {
    if (@available(iOS 13.0, *)) {
        return [UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return NO;
}

static UIColor *WDWantColor(int page) {
    if (page < 0 || page >= 8) return nil;
    if (!gMaster || !gPageOn[page]) return nil;
    BOOL dark = WDIsDarkMode();
    UIColor *c = nil;
    if (gPageHex[page][dark ? 1][0]) c = WDColorForHex([NSString stringWithUTF8String:gPageHex[page][dark ? 1][0]]);
    if (!c && dark && gPageHex[page][0][0]) c = WDColorForHex([NSString stringWithUTF8String:gPageHex[page][0][0]]);
    if (!c && !dark && gPageHex[page][0][0]) c = WDColorForHex([NSString stringWithUTF8String:gPageHex[page][0][0]]);
    return c;
}

static void WDPaintView(UIView *v, UIColor *want) {
    if (!v) return;
    id orig = objc_getAssociatedObject(v, kWDPageOrigKey);
    if (!want) {
        if (orig) {
            v.backgroundColor = [orig isKindOfClass:[UIColor class]] ? (UIColor *)orig : nil;
            objc_setAssociatedObject(v, kWDPageOrigKey, nil, WD_ASSOC);
        }
        return;
    }
    if (!orig) {
        UIColor *cur = v.backgroundColor;
        objc_setAssociatedObject(v, kWDPageOrigKey, cur ? (id)cur : (id)[NSNull null], WD_ASSOC);
    }
    UIColor *now = v.backgroundColor;
    if (!now || ![now isEqual:want]) v.backgroundColor = want;
}

static BOOL WDIsOurController(UIViewController *vc) {
    if (!vc) return NO;
    const char *n = class_getName([vc class]);
    return n && strncmp(n, "WD", 2) == 0;
}

static void WDPaintTree(UIViewController *vc, UIColor *want) {
    if (!vc || !vc.isViewLoaded || !vc.view) return;
    WDPaintView(vc.view, want);
    for (UIView *s in vc.view.subviews) {
        if ([s isKindOfClass:[UIScrollView class]]) WDPaintView(s, want);
    }
}

static UITabBarController *WDFindTabIn(UIViewController *vc, int depth) {
    if (!vc || depth > 3) return nil;
    if ([vc isKindOfClass:[UITabBarController class]]) return (UITabBarController *)vc;
    for (UIViewController *c in vc.childViewControllers) {
        UITabBarController *t = WDFindTabIn(c, depth + 1);
        if (t) return t;
    }
    return WDFindTabIn(vc.presentedViewController, depth + 1);
}

static UITabBarController *WDFindTabBarController(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return nil;
    for (UIWindow *w in app.windows) {
        UITabBarController *t = WDFindTabIn(w.rootViewController, 0);
        if (t) return t;
    }
    return nil;
}

static void WDPageBgApply(void) {
    UITabBarController *tab = WDFindTabBarController();
    if (!tab) return;
    NSArray *vcs = tab.viewControllers;
    if (vcs.count < 4) return;
    for (int i = 0; i < 4; i++) {
        UIViewController *vc = vcs[(NSUInteger)i];
        if (![vc isKindOfClass:[UIViewController class]]) continue;
        UIViewController *root = vc;
        if ([vc isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nav = (UINavigationController *)vc;
            root = nav.viewControllers.firstObject;
            // 只染该 Tab 的根页面，push 进去的子页面保持原样
            if (nav.topViewController != root) { WDPaintTree(root, nil); continue; }
        }
        if (!root || WDIsOurController(root)) { continue; }
        WDPaintTree(root, WDWantColor(WDPageForTabIndex(i)));
    }
}

static void WDPageBgStart(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        WDPageBgApply();
        NSTimer *t = [NSTimer timerWithTimeInterval:2.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
            @try { WDPageBgApply(); } @catch (NSException *e) {}
        }];
        [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
    });
}

#pragma mark - 全量还原（关开关不留残留）

static int gRevertBudget = 0;

static void WDRevertRecur(UIView *v, int depth) {
    if (!v || depth > 20 || gRevertBudget <= 0) return;
    gRevertBudget--;
    int tag = WDStyleTagOf(v);
    if (tag >= 0 && tag < 160) {
        if (!gMaster || !gSnap[tag].on) WDStyleRevertView(v);
    }
    for (UIView *s in v.subviews) WDRevertRecur(s, depth + 1);
}

static void WDRevertPass(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return;
    gRevertBudget = 40000;
    for (UIWindow *w in app.windows) WDRevertRecur(w, 0);
    WDPageBgApply();
}

#pragma mark - 设置入口

static IMP gSec, gRows, gCell, gSel;

static NSInteger WDMoreSec(id self, SEL cmd, id tv) {
    NSInteger n = gSec ? ((NSInteger (*)(id, SEL, id))gSec)(self, cmd, tv) : 0;
    return n + 1;
}
static NSInteger WDMoreRows(id self, SEL cmd, id tv, NSInteger section) {
    NSInteger sections = gSec ? ((NSInteger (*)(id, SEL, id))gSec)(self, cmd, tv) : 0;
    if (section == sections) return 1;
    return gRows ? ((NSInteger (*)(id, SEL, id, NSInteger))gRows)(self, cmd, tv, section) : 0;
}
static UITableViewCell *WDMoreCell(id self, SEL cmd, id tv, NSIndexPath *ip) {
    NSInteger sections = gSec ? ((NSInteger (*)(id, SEL, id))gSec)(self, cmd, tv) : 0;
    if (ip.section == sections) {
        UITableViewCell *c = [(UITableView *)tv dequeueReusableCellWithIdentifier:@"WDEntry"];
        if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"WDEntry"];
        c.textLabel.text = WD_DISPLAY_NAME;
        c.detailTextLabel.text = @"卡片化 · 圆角 · 缩进";
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    return gCell ? ((UITableViewCell *(*)(id, SEL, id, NSIndexPath *))gCell)(self, cmd, tv, ip) : nil;
}
static void WDMoreSelect(id self, SEL cmd, id tv, NSIndexPath *ip) {
    NSInteger sections = gSec ? ((NSInteger (*)(id, SEL, id))gSec)(self, cmd, tv) : 0;
    if (ip.section == sections) {
        [(UITableView *)tv deselectRowAtIndexPath:ip animated:YES];
        WDPushSettings();
        return;
    }
    if (gSel) ((void (*)(id, SEL, id, NSIndexPath *))gSel)(self, cmd, tv, ip);
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
        ((void (*)(id, SEL))gMinVDL)(self, cmd);
    if (gReg || !objc_getClass("WCPluginsMgr")) return;
    gReg = YES;
    @try {
        Class mgr = objc_getClass("WCPluginsMgr");
        id inst = ((id (*)(id, SEL))objc_msgSend)(mgr, @selector(sharedInstance));
        SEL reg = @selector(registerControllerWithTitle:version:controller:);
        if (inst && [inst respondsToSelector:reg]) {
            ((void (*)(id, SEL, id, id, id))objc_msgSend)(inst, reg,
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
    SEL s = @selector(layoutSubviews);
    for (int i = 0; i < n; i++) {
        Class cands[2] = { Nil, Nil };
        cands[0] = objc_getClass(items[i].cls);
        if (items[i].alias) cands[1] = objc_getClass(items[i].alias);
        if (!cands[0] && !cands[1]) { miss++; continue; }
        BOOL touched = NO;
        for (int k = 0; k < 2; k++) {
            Class c = cands[k];
            if (!c) continue;
            if (![c isSubclassOfClass:[UIView class]]) { continue; }
            if (WDHardSkip(class_getName(c))) { continue; }
            WDClsAdd(c, i);
            Class owner = WDOwnerClass(c, s);
            if (!owner) { continue; }
            int fb = WDIdxForClass(owner); // owner 自己也在目录里时，未列出的子类用它的配置
            if (WDHookOwner(owner, fb)) { ok++; touched = YES; }
            else noown++;
        }
        if (!touched) skip++;
    }
    WDInstallGetters();
    char buf[200];
    snprintf(buf, sizeof(buf), "hooks: owners=%d cls=%d miss=%d noown=%d skip=%d",
             gHookedN, gClsN, miss, noown, skip);
    WDLogC(buf);
}

static void WDInstallOnce(void) {
    if (gInstalled) return;
    gInstalled = 1;
    @autoreleasepool {
        @try {
            [WDPrefs shared];
            WDIdxCacheReset();
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
    WDPageBgStart();
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
        @try { WDRevertPass(); } @catch (NSException *e) {}
        WDStyleInvalidate();
        WDPageBgApply();
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *n) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(400 * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            @try { WDPageBgApply(); } @catch (NSException *e) {}
        });
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
