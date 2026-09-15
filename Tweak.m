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
static float gHomeR = 16.f;
static float gHomeI = 12.f;

typedef struct { char on; float r; float i; int kind; } WDSnap;
static WDSnap gSnap[160];

static char gPageOn[8];
static char gPageHex[8][2][16];
static char gCardInOn = 0;
static char gCardInHex[2][16];

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

static Class WDOwnerClass(Class c, SEL s) {
    for (Class k = c; k; k = class_getSuperclass(k)) {
        const char *nm = class_getName(k);
        if (WDHardSkip(nm)) return Nil;
        if (k != c && WDSoftSkip(nm)) return Nil;
        if (WDOwns(k, s)) return k;
    }
    return Nil;
}

#pragma mark - 类下标

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
    for (Class k = c; k && found < 0; k = class_getSuperclass(k)) {
        const char *nm = class_getName(k);
        if (!nm) break;
        if (k != c && WDHardSkip(nm)) break;
        for (int i = 0; i < gClsN; i++) {
            if (gCls[i].cls == k) { found = gCls[i].idx; break; }
        }
        if (nm[0] == 'U' && nm[1] == 'I') break;
        if (strcmp(nm, "NSObject") == 0) break;
    }
    gCacheCls[h] = c;
    gCacheIdx[h] = found;
    return found;
}

#pragma mark - 快照

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
        if (strcmp(items[i].cls, "NewMainFrameCell") == 0) {
            gHomeR = gSnap[i].r;
            gHomeI = gSnap[i].i;
        }
    }
    char on = [p cardOutEnabled] ? 1 : 0;
    NSString *l = [p cardOutHexDark:NO];
    NSString *d = [p cardOutHexDark:YES];
    for (int pg = 0; pg < 8; pg++) {
        gPageOn[pg] = on;
        gPageHex[pg][0][0] = 0;
        gPageHex[pg][1][0] = 0;
        if (l.length) snprintf(gPageHex[pg][0], 16, "%s", l.UTF8String);
        if (d.length) snprintf(gPageHex[pg][1], 16, "%s", d.UTF8String);
    }
    gCardInOn = [p cardInEnabled] ? 1 : 0;
    gCardInHex[0][0] = 0;
    gCardInHex[1][0] = 0;
    NSString *inL = [p cardInHexDark:NO];
    NSString *inD = [p cardInHexDark:YES];
    if (inL.length) snprintf(gCardInHex[0], 16, "%s", inL.UTF8String);
    if (inD.length) snprintf(gCardInHex[1], 16, "%s", inD.UTF8String);
    WDStyleSyncColors(gMaster, gCardInOn != 0, gCardInHex[0], gCardInHex[1],
                      on != 0, gPageHex[0][0], gPageHex[0][1]);
}

static BOOL WDNameHas(const char *nm, const char *needle) {
    return nm && needle && strstr(nm, needle) != NULL;
}

static BOOL WDIsOurView(UIView *v) {
    if (!v) return YES;
    UIResponder *r = v;
    int d = 0;
    while (r && d < 10) {
        const char *n = class_getName(object_getClass(r));
        if (n && n[0] == 'W' && n[1] == 'D') return YES;
        r = r.nextResponder;
        d++;
    }
    return NO;
}

static BOOL WDIsChatView(UIView *v) {
    if (!v) return NO;
    const char *nm = class_getName(object_getClass(v));
    if (!nm) return NO;
    if (WDNameHas(nm, "ChatTableViewCell")) return YES;
    if (WDNameHas(nm, "BaseMsgContentViewController")) return YES;
    if (WDNameHas(nm, "MsgContentViewController")) return YES;
    if (WDNameHas(nm, "MessageCellView")) return YES;
    if (WDNameHas(nm, "ChatTimeCell")) return YES;
    if (WDNameHas(nm, "MMGrowTextView") || WDNameHas(nm, "GrowTextView")) return YES;
    if (WDNameHas(nm, "MMInputTool") || WDNameHas(nm, "InputToolContainer") ||
        WDNameHas(nm, "InputToolView")) return YES;
    UIView *p = v;
    int d = 0;
    while (p && d < 8) {
        const char *pn = class_getName(object_getClass(p));
        if (pn && (strstr(pn, "BaseMsgContent") || strstr(pn, "MsgContentView") ||
                   strstr(pn, "MMGrowTextView") || strstr(pn, "MMInputTool") ||
                   strstr(pn, "InputToolContainer"))) return YES;
        p = p.superview;
        d++;
    }
    return NO;
}

static BOOL WDNameIsPlugin(const char *n) {
    return n && strstr(n, "WCPlugins") != NULL;
}

static BOOL WDIsPluginStorage(UIViewController *vc) {
    if (!vc) return NO;
    for (UIViewController *c = vc; c; ) {
        if (WDNameIsPlugin(class_getName([c class]))) return YES;
        if (c.presentedViewController && WDNameIsPlugin(class_getName([c.presentedViewController class]))) return YES;
        if (c.parentViewController) { c = c.parentViewController; continue; }
        if (c.navigationController && c.navigationController != c) { c = c.navigationController; continue; }
        break;
    }
    return NO;
}

static void WDStyleSearchTree(UIView *v);
static BOOL WDHeaderOn(void);

static BOOL WDIsChatController(UIViewController *vc) {
    if (!vc) return NO;
    const char *n = class_getName([vc class]);
    if (!n) return NO;
    if (strstr(n, "BaseMsgContent") || strstr(n, "MsgContentViewController")) return YES;
    if (strstr(n, "BaseChatViewController")) return YES;
    return NO;
}

static void WDDecorate(id self, int idx) {
    if (idx < 0 || idx >= 160) return;
    if (!gSnap[idx].on) return;
    if (![self isKindOfClass:[UIView class]]) return;
    UIView *v = (UIView *)self;
    if (WDIsOurView(v)) return;
    if (WDStyleShouldSkip(v)) return;
    if (WDIsChatView(v)) return;
    const WDItem *it = &WDCatalogItems()[idx];
    if (it->kind == WDKindBubble || it->group == WDGroupBubble) return;
    if (it->page == WDPageChat && it->group == WDGroupInput) return;
    if (it->group == WDGroupSearch) {
        WDStyleSearchTree(v);
        return;
    }
    if (it->group == WDGroupHeader) {
        if (WDHeaderOn()) WDStyleClearHeader(v);
        return;
    }
    {
        const char *nm = class_getName(object_getClass(v));
        if (nm && strstr(nm, "FoldView")) {
            WDStyleFold(v, gSnap[idx].i, gSnap[idx].r, gContinuous, idx);
            return;
        }
        if (nm && strstr(nm, "TextStateProfileCard")) {
            WDStyleProfile(v, gSnap[idx].i, gSnap[idx].r, gContinuous, idx);
            return;
        }
    }
    if ([v isKindOfClass:[UITableViewCell class]]) {
        WDStyleCell((UITableViewCell *)v, gSnap[idx].i, gSnap[idx].r, gContinuous, idx);
        return;
    }
    if (gSnap[idx].kind == WDKindChrome) {
        const char *nm = class_getName(object_getClass(v));
        if (nm && (strstr(nm, "NavigationBar") || strstr(nm, "BarBackground") ||
                   strstr(nm, "BarContent") || strstr(nm, "CustomBar"))) return;
        WDStyleRound(v, gSnap[idx].r, gContinuous, idx);
        return;
    }
    if (gSnap[idx].i > 0.5f) {
        WDStyleView(v, gSnap[idx].i, gSnap[idx].r, gContinuous, idx);
        return;
    }
    WDStyleRound(v, gSnap[idx].r, gContinuous, idx);
}

#pragma mark - 每类独立 IMP

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
        if (!gMaster || !gSnap[idx].on) {
            if ([slf isKindOfClass:[UIView class]] && WDStyleTagOf((UIView *)slf) >= 0) {
                gDepth++;
                @try { WDStyleRevertView((UIView *)slf); } @catch (NSException *e) {}
                gDepth--;
            }
            return;
        }
        gDepth++;
        @try { WDDecorate(slf, idx); } @catch (NSException *e) {}
        gDepth--;
    });
    if (!stub) return NO;
    method_setImplementation(m, stub);
    if (gHookedN < 256) gHookedOwner[gHookedN++] = owner;
    return YES;
}

#pragma mark - getter

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

static int WDSearchIdxForView(UIView *v) {
    if (!v) return -1;
    int idx = WDIdxForClass(object_getClass(v));
    if (idx >= 0) return idx;
    const char *nm = class_getName(object_getClass(v));
    if (!nm) return WDIndexOfClassName("WCSearchBar");
    if (strstr(nm, "FavSearchBar")) return WDIndexOfClassName("FavSearchBar");
    if (strstr(nm, "WAMainFrameTaskBarSearchBar")) return WDIndexOfClassName("WAMainFrameTaskBarSearchBar");
    if (strstr(nm, "MMUISearchBar")) return WDIndexOfClassName("MMUISearchBar");
    if (strstr(nm, "NewContactsSearch") || strstr(nm, "ContactsSearch"))
        return WDIndexOfClassName("NewContactsSearchPanelView");
    if (strstr(nm, "WCSearchBar") || strstr(nm, "SearchBar"))
        return WDIndexOfClassName("WCSearchBar");
    return WDIndexOfClassName("WCSearchBar");
}

static void WDStyleSearchIfOn(UIView *v) {
    if (!v) return;
    int idx = WDSearchIdxForView(v);
    if (idx < 0 || idx >= 160) return;
    if (!gSnap[idx].on) {
        if (WDStyleTagOf(v) >= 0) WDStyleRevertView(v);
        return;
    }
    // 搜索栏默认跟随卡片的全局圆角 / 缩进，只有用户单独改过这个类才用类级数值
    WDPrefs *sp = [WDPrefs shared];
    NSString *sname = @(WDCatalogItems()[idx].cls);
    CGFloat r = [sp hasCustomRadius:sname] ? gSnap[idx].r : sp.globalRadius;
    CGFloat i = [sp hasCustomInset:sname] ? gSnap[idx].i : sp.globalInset;
    WDStyleSearch(v, i, r, gContinuous, idx);
}

static void WDStyleSearchTree(UIView *v) {
    if (!v) return;
    const char *nm = class_getName(object_getClass(v));
    BOOL wrap = nm && (strstr(nm, "SearchPanel") || strstr(nm, "ContactsSearch") ||
                       strstr(nm, "SearchBarContainer"));
    if (wrap || (v.bounds.size.height > 56 && nm && strstr(nm, "SearchBar"))) {
        NSMutableArray *q = [NSMutableArray arrayWithArray:v.subviews];
        int n = 0;
        BOOL hit = NO;
        while (q.count && n < 24) {
            UIView *sv = q.firstObject;
            [q removeObjectAtIndex:0];
            n++;
            const char *sn = class_getName(object_getClass(sv));
            if (sn && (strstr(sn, "WCSearchBar") || strstr(sn, "MMUISearchBar") ||
                       strstr(sn, "FavSearchBar") || strstr(sn, "WAMainFrameTaskBarSearchBar")) &&
                sv.bounds.size.height <= 56) {
                WDStyleSearchIfOn(sv);
                hit = YES;
                continue;
            }
            if (sv.subviews.count && n < 20) [q addObjectsFromArray:sv.subviews];
        }
        if (!hit && !wrap) WDStyleSearchIfOn(v);
        return;
    }
    WDStyleSearchIfOn(v);
}

static int gHeaderIdx = -2;
static BOOL WDHeaderOn(void) {
    if (gHeaderIdx == -2) gHeaderIdx = WDIndexOfClassName("MMTableSectionHeaderView");
    if (gHeaderIdx < 0 || gHeaderIdx >= 160) return YES;
    return gSnap[gHeaderIdx].on != 0;
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

#pragma mark - 页背景

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
    int slot = dark ? 1 : 0;
    if (gPageHex[page][slot][0]) {
        c = WDColorForHex([NSString stringWithUTF8String:gPageHex[page][slot]]);
    }
    // 深色没单独设时沿用浅色值
    if (!c && dark && gPageHex[page][0][0]) {
        c = WDColorForHex([NSString stringWithUTF8String:gPageHex[page][0]]);
    }
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

static BOOL WDIsHomeController(UIViewController *vc) {
    if (!vc) return NO;
    const char *n = class_getName([vc class]);
    return n && strstr(n, "NewMainFrame") != NULL;
}

static BOOL WDIsMeController(UIViewController *vc) {
    if (!vc) return NO;
    const char *n = class_getName([vc class]);
    return n && (strstr(n, "MoreViewController") || strstr(n, "NewSettingViewController"));
}

static void WDPaintNavChrome(UIViewController *vc, UIColor *want) {
    if (!vc) return;
    // 首页顶栏/搜索/+ 是一体：真假导航栏都不上色，上滑才不会多出一条。
    if (WDIsHomeController(vc)) return;
    // 「我」页不刷导航栏，避免顶部灰条。
    if (WDIsMeController(vc)) return;
    UINavigationController *nav = vc.navigationController;
    if (nav) {
        UINavigationBar *bar = nav.navigationBar;
        if (bar) WDPaintView(bar, want);
        if (nav.view) {
            for (UIView *s in nav.view.subviews) {
                const char *nm = class_getName(object_getClass(s));
                if (!nm) continue;
                if (strstr(nm, "NavigationBar") || strstr(nm, "BarBackground") || strstr(nm, "BarContent")) {
                    WDPaintView(s, want);
                }
            }
        }
    }
}

static void WDPaintTree(UIViewController *vc, UIColor *want) {
    if (!vc || !vc.isViewLoaded || !vc.view) return;
    if (WDIsPluginStorage(vc) || WDIsChatController(vc) || WDIsOurController(vc)) {
        WDPaintView(vc.view, nil);
        return;
    }
    if (WDIsMeController(vc)) {
        // 「我」页原生就是 InsetGrouped，刷 grouped 灰会在第一张卡上方多出一条。
        WDPaintNavChrome(vc, want);
        return;
    }
    if (WDIsHomeController(vc)) {
        // 只刷会话列表底。不刷 vc.view / 真导航栏 / fakeNav / + 号。
        for (UIView *s in vc.view.subviews) {
            if ([s isKindOfClass:[UITableView class]]) WDPaintView(s, want);
        }
        return;
    }
    WDPaintView(vc.view, want);
    WDPaintNavChrome(vc, want);
    for (UIView *s in vc.view.subviews) {
        const char *nm = class_getName(object_getClass(s));
        if (nm && (strstr(nm, "RightTopMenu") || strstr(nm, "BarItemCustom") ||
                   strstr(nm, "MMBarButton") || strstr(nm, "MFTitleView") ||
                   strstr(nm, "CustomBar") || strstr(nm, "TopHeader") ||
                   strstr(nm, "fakeNav") || strstr(nm, "NavigationBar"))) continue;
        if ([s isKindOfClass:[UIScrollView class]]) WDPaintView(s, want);
        if (nm && strstr(nm, "SearchBar")) {
            WDPaintView(s, want);
        }
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
    NSUInteger sel = tab.selectedIndex;
    if (sel > 3) sel = 0;
    for (int i = 0; i < 4; i++) {
        UIViewController *vc = vcs[(NSUInteger)i];
        if (![vc isKindOfClass:[UIViewController class]]) continue;
        UIViewController *root = vc;
        if ([vc isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nav = (UINavigationController *)vc;
            root = nav.viewControllers.firstObject;
            if ((NSUInteger)i != sel) continue;
            if (nav.topViewController != root) { WDPaintTree(root, nil); continue; }
        } else if ((NSUInteger)i != sel) {
            continue;
        }
        if (!root || WDIsOurController(root) || WDIsPluginStorage(root) || WDIsChatController(root)) {
            WDPaintTree(root, nil);
            continue;
        }
        WDPaintTree(root, WDWantColor(WDPageForTabIndex(i)));
    }
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return;
    for (UIWindow *w in app.windows) {
        UIViewController *r = w.rootViewController;
        NSMutableArray *q = [NSMutableArray array];
        if (r) [q addObject:r];
        int n = 0;
        while (q.count && n < 40) {
            UIViewController *c = q.firstObject;
            [q removeObjectAtIndex:0];
            n++;
            if (WDIsPluginStorage(c) || WDIsChatController(c)) WDPaintTree(c, nil);
            if (c.presentedViewController) [q addObject:c.presentedViewController];
            [q addObjectsFromArray:c.childViewControllers];
            if ([c isKindOfClass:[UINavigationController class]]) {
                UIViewController *top = ((UINavigationController *)c).topViewController;
                if (top) [q addObject:top];
            }
        }
    }
}

static void WDPageBgStart(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        WDPageBgApply();
        // 不再每 2 秒刷全部 4 个 Tab，切页闪烁就是这么来的。
    });
}

#pragma mark - 全量还原（关开关不留残留）

static int gRevertBudget = 0;

static void WDRevertRecur(UIView *v, int depth) {
    if (!v || depth > 20 || gRevertBudget <= 0) return;
    if (WDIsOurView(v)) return;
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

#pragma mark - willDisplay

static int gDefCellIdx = -2;

static void WDDecorateCellIfNeeded(UITableViewCell *cell) {
    if (!gLive || !gMaster || gSafe) return;
    if (![cell isKindOfClass:[UITableViewCell class]]) return;
    if (WDIsOurView(cell)) return;
    if (WDStyleShouldSkip(cell)) return;
    if (WDIsChatView(cell)) return;
    int idx = WDIdxForClass(object_getClass(cell));
    if (idx < 0) {
        if (gDefCellIdx == -2) gDefCellIdx = WDIndexOfClassName("MMTableViewCell");
        idx = gDefCellIdx;
    }
    if (idx < 0 || idx >= 160) return;
    if (!gSnap[idx].on) {
        if (WDStyleTagOf(cell) >= 0) WDStyleRevertView(cell);
        return;
    }
    WDDecorate(cell, idx);
}

static BOOL WDHookWillDisplay(const char *clsName) {
    Class cls = objc_getClass(clsName);
    if (!cls) return NO;
    SEL s = @selector(tableView:willDisplayCell:forRowAtIndexPath:);
    Method m = class_getInstanceMethod(cls, s);
    IMP orig = m ? method_getImplementation(m) : NULL;
    static Class hooked[32];
    static int hookedN = 0;
    for (int i = 0; i < hookedN; i++) if (hooked[i] == cls) return YES;
    IMP stub = imp_implementationWithBlock(^(id slf, UITableView *tv, UITableViewCell *cell, NSIndexPath *ip) {
        if (orig) ((void (*)(id, SEL, id, id, id))orig)(slf, s, tv, cell, ip);
        if (![NSThread isMainThread]) return;
        if (gLive && gMaster && !gSafe && [cell isKindOfClass:[UITableViewCell class]] && !WDIsOurView(cell) && !WDIsChatView(cell) && !WDStyleShouldSkip(cell)) {
            int idx = WDIdxForClass(object_getClass(cell));
            if (idx < 0) {
                if (gDefCellIdx == -2) gDefCellIdx = WDIndexOfClassName("MMTableViewCell");
                idx = gDefCellIdx;
            }
            if (idx >= 0 && idx < 160 && gSnap[idx].on) {
                @try { WDStyleCellAt(cell, tv, ip, gSnap[idx].i, gSnap[idx].r, gContinuous, idx); } @catch (NSException *e) {}
                return;
            }
        }
        @try { WDDecorateCellIfNeeded(cell); } @catch (NSException *e) {}
    });
    if (!stub) return NO;
    BOOL ok = NO;
    if (WDOwns(cls, s) && m) {
        method_setImplementation(m, stub);
        ok = YES;
    } else {
        const char *enc = m ? method_getTypeEncoding(m) : "v@:@@@";
        ok = class_addMethod(cls, s, stub, enc);
    }
    if (ok && hookedN < 32) hooked[hookedN++] = cls;
    return ok;
}

static int gDefBannerIdx = -2;

static void WDDecorateViewTree(UIView *v, int depth) {
    if (!v || depth > 4) return;
    if (![v isKindOfClass:[UIView class]]) return;
    if (WDIsOurView(v)) return;
    int idx = WDIdxForClass(object_getClass(v));
    if (idx < 0 && [v isKindOfClass:[UITableViewCell class]]) {
        WDDecorateCellIfNeeded((UITableViewCell *)v);
    } else if (idx >= 0 && idx < 160 && gSnap[idx].on) {
        WDDecorate(v, idx);
    } else {
        const char *nm = class_getName(object_getClass(v));
        if (nm && strstr(nm, "FoldView")) {
            if (gDefBannerIdx == -2) gDefBannerIdx = WDIndexOfClassName("MainFrameSectionFoldView");
            if (gDefBannerIdx >= 0 && gSnap[gDefBannerIdx].on) WDStyleFold(v, gSnap[gDefBannerIdx].i, gSnap[gDefBannerIdx].r, gContinuous, gDefBannerIdx);
        } else if (nm && strstr(nm, "TextStateProfileCard")) {
            int pidx = WDIndexOfClassName("TextStateProfileCardContentView");
            if (pidx >= 0 && gSnap[pidx].on) WDStyleProfile(v, gSnap[pidx].i, gSnap[pidx].r, gContinuous, pidx);
        } else if (nm && (strstr(nm, "SearchPanel") || strstr(nm, "SearchBar") ||
                          strstr(nm, "WCSearchBar") || strstr(nm, "MMUISearchBar") ||
                          strstr(nm, "FavSearchBar") || strstr(nm, "ContactsSearch"))) {
            WDStyleSearchTree(v);
        } else if (nm && (strstr(nm, "SectionHeader") || strstr(nm, "MMTableSection") ||
                          strstr(nm, "countLabel") || strstr(nm, "CountLabel"))) {
            if (WDHeaderOn()) WDStyleClearHeader(v);
        }
    }
    for (UIView *s in v.subviews) WDDecorateViewTree(s, depth + 1);
}

static BOOL WDHookWillDisplayHeader(const char *clsName) {
    Class cls = objc_getClass(clsName);
    if (!cls) return NO;
    SEL s = @selector(tableView:willDisplayHeaderView:forSection:);
    Method m = class_getInstanceMethod(cls, s);
    IMP orig = m ? method_getImplementation(m) : NULL;
    static Class hooked[32];
    static int hookedN = 0;
    for (int i = 0; i < hookedN; i++) if (hooked[i] == cls) return YES;
    IMP stub = imp_implementationWithBlock(^(id slf, UITableView *tv, UIView *header, NSInteger section) {
        if (orig) ((void (*)(id, SEL, id, id, NSInteger))orig)(slf, s, tv, header, section);
        if (!gLive || !gMaster || gSafe) return;
        if (![NSThread isMainThread]) return;
        @try {
            if ([header isKindOfClass:[UIView class]]) {
                const char *nm = class_getName(object_getClass(header));
                if (nm && (strstr(nm, "FoldView") || strstr(nm, "Banner"))) {
                    WDDecorateViewTree(header, 0);
                } else if (WDHeaderOn()) {
                    WDStyleClearHeader(header);
                }
            }
        } @catch (NSException *e) {}
    });
    if (!stub) return NO;
    BOOL ok = NO;
    if (WDOwns(cls, s) && m) {
        method_setImplementation(m, stub);
        ok = YES;
    } else {
        const char *enc = m ? method_getTypeEncoding(m) : "v@:@@q";
        ok = class_addMethod(cls, s, stub, enc);
    }
    if (ok && hookedN < 32) hooked[hookedN++] = cls;
    return ok;
}

static BOOL WDHookWillDisplayFooter(const char *clsName) {
    Class cls = objc_getClass(clsName);
    if (!cls) return NO;
    SEL s = @selector(tableView:willDisplayFooterView:forSection:);
    Method m = class_getInstanceMethod(cls, s);
    IMP orig = m ? method_getImplementation(m) : NULL;
    static Class hooked[32];
    static int hookedN = 0;
    for (int i = 0; i < hookedN; i++) if (hooked[i] == cls) return YES;
    IMP stub = imp_implementationWithBlock(^(id slf, UITableView *tv, UIView *footer, NSInteger section) {
        if (orig) ((void (*)(id, SEL, id, id, NSInteger))orig)(slf, s, tv, footer, section);
        if (!gLive || !gMaster || gSafe) return;
        if (![NSThread isMainThread]) return;
        @try { if (WDHeaderOn() && [footer isKindOfClass:[UIView class]]) WDStyleClearHeader(footer); } @catch (NSException *e) {}
    });
    if (!stub) return NO;
    BOOL ok = NO;
    if (WDOwns(cls, s) && m) {
        method_setImplementation(m, stub);
        ok = YES;
    } else {
        const char *enc = m ? method_getTypeEncoding(m) : "v@:@@q";
        ok = class_addMethod(cls, s, stub, enc);
    }
    if (ok && hookedN < 32) hooked[hookedN++] = cls;
    return ok;
}

static BOOL WDHookFoldUpdate(void);
static void WDClearCountOnOwner(UIViewController *own);
static BOOL WDHookFoldState(void);
static BOOL WDHookTabSelect(void);
static BOOL WDHookTabAppear(const char *clsName);
static BOOL WDHookProfileLayout(const char *clsName);
static BOOL WDHookMeLayout(const char *clsName);

static BOOL WDHookViewForHeader(const char *clsName) {
    Class cls = objc_getClass(clsName);
    if (!cls) return NO;
    SEL s = @selector(tableView:viewForHeaderInSection:);
    if (!WDOwns(cls, s)) return NO;
    Method m = class_getInstanceMethod(cls, s);
    if (!m) return NO;
    IMP orig = method_getImplementation(m);
    static Class hooked[32];
    static int hookedN = 0;
    for (int i = 0; i < hookedN; i++) if (hooked[i] == cls) return YES;
    IMP stub = imp_implementationWithBlock(^id(id slf, UITableView *tv, NSInteger section) {
        id r = orig ? ((id (*)(id, SEL, id, NSInteger))orig)(slf, s, tv, section) : nil;
        if (gLive && gMaster && !gSafe && [r isKindOfClass:[UIView class]]) {
            @try {
                const char *nm = class_getName(object_getClass(r));
                if (nm && (strstr(nm, "FoldView") || strstr(nm, "Banner"))) WDDecorateViewTree((UIView *)r, 0);
                else if (WDHeaderOn()) WDStyleClearHeader((UIView *)r);
            } @catch (NSException *e) {}
        }
        return r;
    });
    if (!stub) return NO;
    method_setImplementation(m, stub);
    if (hookedN < 32) hooked[hookedN++] = cls;
    return YES;
}

static BOOL WDHookHeaderHeight(const char *clsName) {
    Class cls = objc_getClass(clsName);
    if (!cls) return NO;
    SEL s = @selector(tableView:heightForHeaderInSection:);
    Method m = class_getInstanceMethod(cls, s);
    static Class hooked[32];
    static int hookedN = 0;
    for (int i = 0; i < hookedN; i++) if (hooked[i] == cls) return YES;
    IMP orig = (WDOwns(cls, s) && m) ? method_getImplementation(m) : NULL;
    IMP stub = imp_implementationWithBlock(^CGFloat(id slf, UITableView *tv, NSInteger section) {
        CGFloat h = orig ? ((CGFloat (*)(id, SEL, id, NSInteger))orig)(slf, s, tv, section) : 32.0;
        if (!gLive || !gMaster || gSafe) return h;
        const char *nm = class_getName(object_getClass(slf));
        if (nm && strstr(nm, "ContactsViewController") && !strstr(nm, "Brand") && !strstr(nm, "Tag")) {
            NSInteger letter = 0;
            @try {
                if ([slf respondsToSelector:@selector(ConvertToNormalContactSection:)]) {
                    letter = ((NSInteger (*)(id, SEL, NSInteger))objc_msgSend)(slf, @selector(ConvertToNormalContactSection:), 0);
                }
            } @catch (NSException *e) { letter = 0; }
            if (letter > 1 && section > 0 && section < letter) return CGFLOAT_MIN;
            if (!orig && letter > 1 && section < letter) return CGFLOAT_MIN;
        }
        return h;
    });
    if (!stub) return NO;
    BOOL ok = NO;
    if (WDOwns(cls, s) && m) { method_setImplementation(m, stub); ok = YES; }
    else {
        const char *enc = m ? method_getTypeEncoding(m) : "d@:@q";
        ok = class_addMethod(cls, s, stub, enc);
    }
    if (ok && hookedN < 32) hooked[hookedN++] = cls;
    return ok;
}

static BOOL WDHookFooterHeight(const char *clsName) {
    Class cls = objc_getClass(clsName);
    if (!cls) return NO;
    SEL s = @selector(tableView:heightForFooterInSection:);
    Method m = class_getInstanceMethod(cls, s);
    static Class hooked[32];
    static int hookedN = 0;
    for (int i = 0; i < hookedN; i++) if (hooked[i] == cls) return YES;
    IMP orig = (WDOwns(cls, s) && m) ? method_getImplementation(m) : NULL;
    IMP stub = imp_implementationWithBlock(^CGFloat(id slf, UITableView *tv, NSInteger section) {
        CGFloat h = orig ? ((CGFloat (*)(id, SEL, id, NSInteger))orig)(slf, s, tv, section) : CGFLOAT_MIN;
        if (!gLive || !gMaster || gSafe) return h;
        const char *nm = class_getName(object_getClass(slf));
        if (nm && strstr(nm, "ContactsViewController") && !strstr(nm, "Brand") && !strstr(nm, "Tag")) {
            NSInteger letter = 0;
            @try {
                if ([slf respondsToSelector:@selector(ConvertToNormalContactSection:)]) {
                    letter = ((NSInteger (*)(id, SEL, NSInteger))objc_msgSend)(slf, @selector(ConvertToNormalContactSection:), 0);
                }
            } @catch (NSException *e) { letter = 0; }
            if (letter > 1 && section >= 0 && section < letter) return CGFLOAT_MIN;
        }
        return h;
    });
    if (!stub) return NO;
    BOOL ok = NO;
    if (WDOwns(cls, s) && m) { method_setImplementation(m, stub); ok = YES; }
    else {
        const char *enc = m ? method_getTypeEncoding(m) : "d@:@q";
        ok = class_addMethod(cls, s, stub, enc);
    }
    if (ok && hookedN < 32) hooked[hookedN++] = cls;
    return ok;
}

static BOOL WDHookSearchSel(Class cls, SEL s) {
    if (!cls || !s || !WDOwns(cls, s)) return NO;
    Method m = class_getInstanceMethod(cls, s);
    if (!m) return NO;
    static SEL hookedSel[32];
    static Class hookedCls[32];
    static int hookedN = 0;
    for (int i = 0; i < hookedN; i++) if (hookedCls[i] == cls && hookedSel[i] == s) return YES;
    IMP orig = method_getImplementation(m);
    IMP stub = imp_implementationWithBlock(^(id slf) {
        if (orig) ((void (*)(id, SEL))orig)(slf, s);
        if (!gLive || !gMaster || gSafe) return;
        if (![NSThread isMainThread]) return;
        if (![slf isKindOfClass:[UIView class]]) return;
        if (WDIsOurView((UIView *)slf) || WDStyleShouldSkip((UIView *)slf) || WDIsChatView((UIView *)slf)) return;
        @try { WDStyleSearchTree((UIView *)slf); } @catch (NSException *e) {}
    });
    if (!stub) return NO;
    method_setImplementation(m, stub);
    if (hookedN < 32) { hookedCls[hookedN] = cls; hookedSel[hookedN] = s; hookedN++; }
    return YES;
}

static BOOL WDHookSearchBarClass(const char *clsName) {
    Class cls = objc_getClass(clsName);
    if (!cls) return NO;
    BOOL ok = NO;
    if (WDHookSearchSel(cls, @selector(layoutSubviews))) ok = YES;
    if (WDHookSearchSel(cls, @selector(arrangeBaseUIElements))) ok = YES;
    if (WDHookSearchSel(cls, @selector(setUnactiveStyle))) ok = YES;
    return ok;
}

static BOOL WDHookInitCountLabel(const char *clsName) {
    Class cls = objc_getClass(clsName);
    if (!cls) return NO;
    SEL s = @selector(initCountLabel:);
    if (!WDOwns(cls, s)) return NO;
    Method m = class_getInstanceMethod(cls, s);
    if (!m) return NO;
    static Class hooked[32];
    static int hookedN = 0;
    for (int i = 0; i < hookedN; i++) if (hooked[i] == cls) return YES;
    IMP orig = method_getImplementation(m);
    IMP stub = imp_implementationWithBlock(^(id slf, id arg) {
        if (orig) ((void (*)(id, SEL, id))orig)(slf, s, arg);
        if (!gLive || !gMaster || gSafe) return;
        if (![NSThread isMainThread]) return;
        @try {
            if (WDHeaderOn() && [arg isKindOfClass:[UIView class]]) WDStyleClearHeader((UIView *)arg);
            if (WDHeaderOn()) WDClearCountOnOwner([slf isKindOfClass:[UIViewController class]] ? (UIViewController *)slf : nil);
        } @catch (NSException *e) {}
    });
    if (!stub) return NO;
    method_setImplementation(m, stub);
    if (hookedN < 32) hooked[hookedN++] = cls;
    return YES;
}

static BOOL WDHookProfileLayout(const char *clsName) {
    Class cls = objc_getClass(clsName);
    if (!cls) return NO;
    SEL s = @selector(layoutSubviews);
    if (!WDOwns(cls, s)) return NO;
    Method m = class_getInstanceMethod(cls, s);
    if (!m) return NO;
    static Class hooked[4];
    static int hookedN = 0;
    for (int i = 0; i < hookedN; i++) if (hooked[i] == cls) return YES;
    IMP orig = method_getImplementation(m);
    IMP stub = imp_implementationWithBlock(^(id slf) {
        if (orig) ((void (*)(id, SEL))orig)(slf, s);
        if (!gLive || !gMaster || gSafe) return;
        if (![NSThread isMainThread]) return;
        if (![slf isKindOfClass:[UIView class]]) return;
        int pidx = WDIndexOfClassName("TextStateProfileCardContentView");
        if (pidx >= 0 && gSnap[pidx].on) {
            @try { WDStyleProfile((UIView *)slf, gSnap[pidx].i, gSnap[pidx].r, gContinuous, pidx); } @catch (NSException *e) {}
        }
    });
    if (!stub) return NO;
    method_setImplementation(m, stub);
    if (hookedN < 4) hooked[hookedN++] = cls;
    return YES;
}

static BOOL WDHookMeLayout(const char *clsName) {
    Class cls = objc_getClass(clsName);
    if (!cls) return NO;
    SEL s = @selector(viewDidLayoutSubviews);
    if (!WDOwns(cls, s)) return NO;
    Method m = class_getInstanceMethod(cls, s);
    if (!m) return NO;
    static Class hooked[4];
    static int hookedN = 0;
    for (int i = 0; i < hookedN; i++) if (hooked[i] == cls) return YES;
    IMP orig = method_getImplementation(m);
    IMP stub = imp_implementationWithBlock(^(id slf) {
        if (orig) ((void (*)(id, SEL))orig)(slf, s);
        if (!gLive || !gMaster || gSafe) return;
        if (![NSThread isMainThread]) return;
        if (![slf isKindOfClass:[UIViewController class]]) return;
        int pidx = WDIndexOfClassName("TextStateProfileCardContentView");
        if (pidx >= 0 && gSnap[pidx].on) {
            @try { WDStyleMePage((UIViewController *)slf, gSnap[pidx].i, gSnap[pidx].r, gContinuous, pidx); } @catch (NSException *e) {}
        }
    });
    if (!stub) return NO;
    method_setImplementation(m, stub);
    if (hookedN < 4) hooked[hookedN++] = cls;
    return YES;
}

// 新的朋友 / 好友申请这类页面：内容短，底部会露出一大片底色，整块透明掉
static BOOL WDHookTailClear(const char *clsName) {
    Class cls = objc_getClass(clsName);
    if (!cls) return NO;
    SEL s = @selector(viewDidAppear:);
    Method m = class_getInstanceMethod(cls, s);
    static Class hooked[16];
    static int hookedN = 0;
    for (int i = 0; i < hookedN; i++) if (hooked[i] == cls) return YES;
    IMP orig = (WDOwns(cls, s) && m) ? method_getImplementation(m) : NULL;
    IMP stub = imp_implementationWithBlock(^(id slf, BOOL animated) {
        if (orig) ((void (*)(id, SEL, BOOL))orig)(slf, s, animated);
        if (!gLive || !gMaster || gSafe) return;
        if (![NSThread isMainThread]) return;
        if (![slf isKindOfClass:[UIViewController class]]) return;
        UIViewController *vc = (UIViewController *)slf;
        if (!vc.isViewLoaded || !vc.view) return;
        @try { WDStyleClearTableTail(vc.view); } @catch (NSException *e) {}
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(350 * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            @try { WDStyleClearTableTail(vc.view); } @catch (NSException *e) {}
        });
    });
    if (!stub) return NO;
    BOOL ok = NO;
    if (WDOwns(cls, s) && m) {
        method_setImplementation(m, stub);
        ok = YES;
    } else {
        const char *enc = m ? method_getTypeEncoding(m) : "v@:B";
        ok = class_addMethod(cls, s, stub, enc);
    }
    if (ok && hookedN < 16) hooked[hookedN++] = cls;
    return ok;
}

static void WDInstallTableDisplay(void) {
    static const char *kTailVCs[] = {
        "SayHelloViewController", "HelloViewController", "NewFriendsViewController",
        "ApplyFriendListViewController", "FriendAsistSessionViewController",
        "AddFriendEntryViewController", NULL
    };
    for (int i = 0; kTailVCs[i]; i++) WDHookTailClear(kTailVCs[i]);
    static const char *kVCs[] = {
        "NewMainFrameViewController",
        "ContactsViewController",
        "NewContactsViewController",
        "FindFriendEntryViewController",
        "MoreViewController",
        "NewSettingViewController",
        "WCTableViewManager",
        "MMTableViewInfo",
        "BrandContactsViewController",
        "BrandServiceContactsViewController",
        "BrandAndServiceContactsViewController",
        "ChatRoomListViewController",
        "MemberListViewController",
        "ContactsGenericViewController",
        "WeixinOpenServiceViewController",
        "WCPayMainViewControllerV2",
        "SayHelloViewController",
        "HelloViewController",
        "ApplyFriendListViewController",
        "FriendAsistSessionViewController",
        "NewFriendsViewController",
        "AddFriendEntryViewController",
        "ContactInfoViewController",
        "WCPayMainViewController",
        "WCPayWalletViewController",
        NULL
    };
    for (int i = 0; kVCs[i]; i++) {
        WDHookWillDisplay(kVCs[i]);
        WDHookWillDisplayHeader(kVCs[i]);
        WDHookWillDisplayFooter(kVCs[i]);
        WDHookInitCountLabel(kVCs[i]);
    }
    WDHookViewForHeader("NewMainFrameViewController");
    WDHookViewForHeader("MGSessionBoxViewController");
    WDHookViewForHeader("WCTableViewManager");
    WDHookViewForHeader("MMTableViewInfo");
    WDHookViewForHeader("ContactsViewController");
    WDHookHeaderHeight("ContactsViewController");
    WDHookFooterHeight("ContactsViewController");
    WDHookFoldUpdate();
    WDHookFoldState();
    WDHookTabSelect();
    WDHookTabAppear("NewMainFrameViewController");
    WDHookTabAppear("ContactsViewController");
    WDHookTabAppear("FindFriendEntryViewController");
    WDHookTabAppear("MoreViewController");
    WDHookSearchBarClass("WCSearchBar");
    WDHookSearchBarClass("MMUISearchBar");
    WDHookSearchBarClass("FavSearchBar");
    WDHookSearchBarClass("WAMainFrameTaskBarSearchBar");
    WDHookSearchBarClass("NewContactsSearchPanelView");
    WDHookViewForHeader("SayHelloViewController");
    WDHookViewForHeader("HelloViewController");
    WDHookViewForHeader("ApplyFriendListViewController");
    WDHookViewForHeader("FriendAsistSessionViewController");
    WDHookViewForHeader("NewFriendsViewController");
    WDHookProfileLayout("TextStateProfileCardContentView");
    WDHookMeLayout("MoreViewController");
}

static BOOL WDHookFoldUpdate(void) {
    Class cls = objc_getClass("NewMainFrameViewController");
    if (!cls) return NO;
    SEL s = @selector(updateTopSessionFoldView);
    if (!WDOwns(cls, s)) return NO;
    Method m = class_getInstanceMethod(cls, s);
    if (!m) return NO;
    static IMP orig = NULL;
    if (orig) return YES;
    orig = method_getImplementation(m);
    IMP stub = imp_implementationWithBlock(^(id slf) {
        if (orig) ((void (*)(id, SEL))orig)(slf, s);
        if (!gLive || !gMaster || gSafe) return;
        if (![NSThread isMainThread]) return;
        @try {
            UIView *fold = nil;
            SEL g = @selector(topSessionFoldView);
            if ([slf respondsToSelector:g]) {
                fold = ((id (*)(id, SEL))objc_msgSend)(slf, g);
            }
            if ([fold isKindOfClass:[UIView class]]) WDDecorateViewTree(fold, 0);
        } @catch (NSException *e) {}
    });
    if (!stub) return NO;
    method_setImplementation(m, stub);
    return YES;
}

static BOOL WDHookFoldState(void) {
    Class cls = objc_getClass("MainFrameSectionFoldView");
    if (!cls) return NO;
    SEL s = @selector(setIsFolding:foldCount:);
    if (!WDOwns(cls, s)) return NO;
    Method m = class_getInstanceMethod(cls, s);
    if (!m) return NO;
    static IMP orig = NULL;
    if (orig) return YES;
    orig = method_getImplementation(m);
    IMP stub = imp_implementationWithBlock(^(id slf, BOOL folding, long long count) {
        if (orig) ((void (*)(id, SEL, BOOL, long long))orig)(slf, s, folding, count);
        if (!gLive || !gMaster || gSafe) return;
        if (![NSThread isMainThread]) return;
        if (![slf isKindOfClass:[UIView class]]) return;
        if (gDefBannerIdx == -2) gDefBannerIdx = WDIndexOfClassName("MainFrameSectionFoldView");
        if (gDefBannerIdx >= 0 && gSnap[gDefBannerIdx].on) {
            @try { WDStyleFold((UIView *)slf, gSnap[gDefBannerIdx].i, gSnap[gDefBannerIdx].r, gContinuous, gDefBannerIdx); } @catch (NSException *e) {}
        }
    });
    if (!stub) return NO;
    method_setImplementation(m, stub);
    return YES;
}

static BOOL WDHookTabSelect(void) {
    Class cls = objc_getClass("MMTabBarController");
    if (!cls) return NO;
    SEL s = @selector(setSelectedIndex:);
    Method m = class_getInstanceMethod(cls, s);
    static IMP orig = NULL;
    if (orig) return YES;
    orig = m ? method_getImplementation(m) : NULL;
    IMP stub = imp_implementationWithBlock(^(id slf, NSUInteger idx) {
        if (orig) ((void (*)(id, SEL, NSUInteger))orig)(slf, s, idx);
        if (!gLive || !gMaster || gSafe) return;
        if (![NSThread isMainThread]) return;
        @try { WDPageBgApply(); } @catch (NSException *e) {}
    });
    if (!stub) return NO;
    BOOL ok = NO;
    if (WDOwns(cls, s) && m) { method_setImplementation(m, stub); ok = YES; }
    else {
        const char *enc = m ? method_getTypeEncoding(m) : "v@:Q";
        ok = class_addMethod(cls, s, stub, enc);
    }
    return ok;
}

static BOOL WDHookTabAppear(const char *clsName) {
    Class cls = objc_getClass(clsName);
    if (!cls) return NO;
    SEL s = @selector(viewDidAppear:);
    Method m = class_getInstanceMethod(cls, s);
    static Class hooked[32];
    static int hookedN = 0;
    for (int i = 0; i < hookedN; i++) if (hooked[i] == cls) return YES;
    IMP orig = (WDOwns(cls, s) && m) ? method_getImplementation(m) : NULL;
    IMP stub = imp_implementationWithBlock(^(id slf, BOOL animated) {
        if (orig) ((void (*)(id, SEL, BOOL))orig)(slf, s, animated);
        if (!gLive || !gMaster || gSafe) return;
        if (![NSThread isMainThread]) return;
        @try { WDPageBgApply(); } @catch (NSException *e) {}
        if ([slf isKindOfClass:[UIViewController class]]) {
            const char *cn = class_getName([slf class]);
            if (cn && strstr(cn, "MoreViewController")) {
                int pidx = WDIndexOfClassName("TextStateProfileCardContentView");
                if (pidx >= 0 && gSnap[pidx].on) {
                    @try { WDStyleMePage((UIViewController *)slf, gSnap[pidx].i, gSnap[pidx].r, gContinuous, pidx); } @catch (NSException *e) {}
                }
            }
        }
    });
    if (!stub) return NO;
    BOOL ok = NO;
    if (WDOwns(cls, s) && m) { method_setImplementation(m, stub); ok = YES; }
    else {
        const char *enc = m ? method_getTypeEncoding(m) : "v@:B";
        ok = class_addMethod(cls, s, stub, enc);
    }
    if (ok && hookedN < 32) hooked[hookedN++] = cls;
    return ok;
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
            WDInstallTableDisplay();
            WDHookEntry("MoreViewController");
            WDHookEntry("NewSettingViewController");
            WDHookPlugin();
        } @catch (NSException *e) {
            WDLogC("install exception");
        }
    }
}

static UIViewController *WDOwnerVC(UIView *v) {
    UIResponder *rr = v;
    int d = 0;
    while (rr && d < 12) {
        if ([rr isKindOfClass:[UIViewController class]]) return (UIViewController *)rr;
        rr = rr.nextResponder;
        d++;
    }
    return nil;
}

static void WDClearCountOnOwner(UIViewController *own) {
    if (!own) return;
    @try {
        id lab = [own valueForKey:@"m_countLabel"];
        if ([lab isKindOfClass:[UIView class]]) WDStyleClearHeader((UIView *)lab);
    } @catch (NSException *e) {}
    @try {
        id lab = [own valueForKey:@"countLabel"];
        if ([lab isKindOfClass:[UIView class]]) WDStyleClearHeader((UIView *)lab);
    } @catch (NSException *e) {}
    if (!own.isViewLoaded || !own.view) return;
    NSMutableArray *tvs = [NSMutableArray array];
    NSMutableArray *q = [NSMutableArray arrayWithObject:own.view];
    int n = 0;
    while (q.count && n < 120) {
        UIView *sv = q.firstObject;
        [q removeObjectAtIndex:0];
        n++;
        if ([sv isKindOfClass:[UITableView class]]) [tvs addObject:sv];
        const char *sn = class_getName(object_getClass(sv));
        BOOL named = sn && (strstr(sn, "Count") || strstr(sn, "countLabel") ||
                            strstr(sn, "countLab") || strstr(sn, "BottomCount") ||
                            strstr(sn, "ContactCount"));
        if (named || [sv isKindOfClass:[UILabel class]]) {
            NSString *txt = nil;
            if ([sv isKindOfClass:[UILabel class]]) txt = ((UILabel *)sv).text;
            if (named || (txt && ([txt containsString:@"个服务号"] ||
                                  [txt containsString:@"个公众号"] ||
                                  [txt containsString:@"个朋友"] ||
                                  [txt containsString:@"个联系人"] ||
                                  [txt containsString:@"个群聊"] ||
                                  [txt containsString:@"位朋友"]))) {
                @try { WDStyleClearHeader(sv); } @catch (NSException *ex) {}
            }
        }
        if (sv.subviews.count && n < 90) [q addObjectsFromArray:sv.subviews];
    }
    for (UITableView *tv in tvs) {
        UIView *fv = tv.tableFooterView;
        if (!fv) continue;
        @try { WDStyleClearHeader(fv); } @catch (NSException *e) {}
        fv.backgroundColor = [UIColor clearColor];
        fv.opaque = NO;
    }
}

static void WDDecorateVisible(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return;
    for (UIWindow *w in app.windows) {
        if (!w) continue;
        NSMutableArray *q = [NSMutableArray arrayWithObject:w];
        int n = 0;
        while (q.count && n < 800) {
            UIView *v = q.firstObject;
            [q removeObjectAtIndex:0];
            n++;
            if (WDIsOurView(v)) continue;
            if ([v isKindOfClass:[UITableView class]]) {
                UITableView *tv = (UITableView *)v;
                tv.separatorColor = [UIColor clearColor];
                tv.separatorStyle = UITableViewCellSeparatorStyleNone;
                for (UITableViewCell *c in tv.visibleCells) {
                    @try { WDDecorateCellIfNeeded(c); } @catch (NSException *e) {}
                }
                NSInteger sn = tv.numberOfSections;
                for (NSInteger i = 0; i < sn && i < 32; i++) {
                    UIView *h = [tv headerViewForSection:i];
                    if (h) {
                        const char *hn = class_getName(object_getClass(h));
                        @try {
                            if (hn && strstr(hn, "FoldView")) WDDecorateViewTree(h, 0);
                            else if (WDHeaderOn()) WDStyleClearHeader(h);
                        } @catch (NSException *e) {}
                    }
                    UIView *f = [tv footerViewForSection:i];
                    if (f && WDHeaderOn()) @try { WDStyleClearHeader(f); } @catch (NSException *e) {}
                }
                if (tv.tableFooterView && WDHeaderOn()) @try { WDStyleClearHeader(tv.tableFooterView); } @catch (NSException *e) {}
                if (tv.tableHeaderView) {
                    const char *hn = class_getName(object_getClass(tv.tableHeaderView));
                    if (hn && strstr(hn, "SearchPanel")) {
                        for (UIView *sv in tv.tableHeaderView.subviews) {
                            const char *sn = class_getName(object_getClass(sv));
                            if (sn && (strstr(sn, "WCSearchBar") || strstr(sn, "MMUISearchBar"))) {
                                @try { WDStyleSearchTree(sv); } @catch (NSException *e) {}
                            }
                        }
                    } else if (hn && strstr(hn, "SearchBar")) {
                        @try { WDStyleSearchTree(tv.tableHeaderView); } @catch (NSException *e) {}
                    }
                }
                WDClearCountOnOwner(WDOwnerVC(tv));
            } else if ([v isKindOfClass:[UICollectionView class]]) {
                UIViewController *own = WDOwnerVC(v);
                const char *on = own ? class_getName([own class]) : NULL;
                if (on && strstr(on, "WCPayMainViewController")) {
                    int pay = WDIndexOfClassName("WCPayWalletEntryHeaderView");
                    if (pay < 0) pay = WDIndexOfClassName("NewMainFrameCell");
                    if (pay >= 0 && gSnap[pay].on) @try { WDStyleHostCard(v, gSnap[pay].i, gSnap[pay].r, gContinuous, pay); } @catch (NSException *e) {}
                }
            } else {
                const char *nm = class_getName(object_getClass(v));
                if (nm && strstr(nm, "FoldView")) {
                    @try { WDDecorateViewTree(v, 0); } @catch (NSException *e) {}
                } else if (nm && (strstr(nm, "TextStateProfileCard") || strstr(nm, "MoreViewController"))) {
                    int pidx = WDIndexOfClassName("TextStateProfileCardContentView");
                    if (pidx >= 0 && gSnap[pidx].on) {
                        UIViewController *own = WDOwnerVC(v);
                        if (own && WDIsMeController(own)) {
                            @try { WDStyleMePage(own, gSnap[pidx].i, gSnap[pidx].r, gContinuous, pidx); } @catch (NSException *e) {}
                        } else if (strstr(nm, "TextStateProfileCard")) {
                            @try { WDStyleProfile(v, gSnap[pidx].i, gSnap[pidx].r, gContinuous, pidx); } @catch (NSException *e) {}
                        }
                    }
                } else if (nm && strstr(nm, "SearchPanel")) {
                    for (UIView *sv in v.subviews) {
                        const char *sn = class_getName(object_getClass(sv));
                        if (sn && (strstr(sn, "WCSearchBar") || strstr(sn, "MMUISearchBar"))) {
                            @try { WDStyleSearchTree(sv); } @catch (NSException *e) {}
                        }
                    }
                } else if (nm && (strstr(nm, "SearchBar") || strstr(nm, "FavSearchBar"))) {
                    @try { WDStyleSearchTree(v); } @catch (NSException *e) {}
                }
            }
            if (v.subviews.count) [q addObjectsFromArray:v.subviews];
        }
    }
}

static void WDGoLive(void) {
    if (gLive) return;
    WDSnapshot();
    gLive = 1;
    WDLogC("live");
    WDPageBgStart();
    WDStyleInvalidate();
    @try { WDDecorateVisible(); } @catch (NSException *e) {}
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
        if (gLive && gMaster && !gSafe) {
            @try { WDDecorateVisible(); } @catch (NSException *e) {}
        }
        UIApplication *app = [UIApplication sharedApplication];
        if (app) {
            for (UIWindow *w in app.windows) {
                UIViewController *top = w.rootViewController;
                NSMutableArray *qq = [NSMutableArray array];
                if (top) [qq addObject:top];
                int k = 0;
                while (qq.count && k < 20) {
                    UIViewController *c = qq.firstObject;
                    [qq removeObjectAtIndex:0];
                    k++;
                    if (WDIsOurController(c) && c.isViewLoaded) {
                        if ([c isKindOfClass:[UITableViewController class]]) {
                            [((UITableViewController *)c).tableView setNeedsLayout];
                        }
                    }
                    if (c.presentedViewController) [qq addObject:c.presentedViewController];
                    [qq addObjectsFromArray:c.childViewControllers];
                    if ([c isKindOfClass:[UINavigationController class]]) {
                        UIViewController *t = ((UINavigationController *)c).topViewController;
                        if (t) [qq addObject:t];
                    }
                }
            }
        }
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
