// ============================================================
// dingliu —— 你啊爸支鼎溜
// 微信 8.0.70+ 全局圆角美化 (iOS, rootless / TrollFools 双环境)
//
// 逆向来源：
//   微信首页圆角_patched.dylib (31 hooks) + 微信圆角_patched.dylib (217 hooks)
//   两包整合重写：不依赖 CydiaSubstrate，纯 ObjC runtime swizzle，
//   数据驱动 hook 表 + 手工特判，类名全部存在性守卫，向前兼容 8.0.70+。
// ============================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ------------------------------------------------------------
// MARK: - 常量 / 偏好键
// ------------------------------------------------------------

#define DL_PREF_DOMAIN @"com.dingliu.wechat"

static NSString * const kMaster          = @"DLMasterSwitch";        // 总开关
static NSString * const kHomeEnable      = @"DLEnableHomeRound";     // 首页(聊天列表)圆角
static NSString * const kHomeRadius      = @"DLHomeRadius";          // 首页圆角半径
static NSString * const kHomeColors      = @"DLHomeCellColors";      // 首页单元格背景色 light:#...;dark:#...
static NSString * const kSearchRound     = @"DLEnableSearchBarRound";// 搜索框圆角
static NSString * const kGlobalEnable    = @"DLEnableGlobalRound";   // 全局圆角
static NSString * const kGlobalRadius    = @"DLGlobalRadius";        // 全局圆角半径
static NSString * const kBubbleEnable    = @"DLEnableBubbleRound";   // 聊天气泡圆角
static NSString * const kBubbleRadius    = @"DLBubbleRadius";        // 气泡圆角半径
static NSString * const kBorderOn        = @"DLEnableBorder";        // 描边开关
static NSString * const kBorderWidth     = @"DLBorderWidth";         // 描边宽度
static NSString * const kBorderColor     = @"DLBorderColor";         // 描边颜色 light:#...;dark:#...
static NSString * const kContinuous      = @"DLContinuousCorner";    // 连续曲率
static NSString * const kSystemRound     = @"DLSystemRound";         // 系统类(UISearchBar/UITableViewCell/UIButton...)圆角
static NSString * const kFullWidth       = @"DLFullWidthCells";      // 单元格铺满屏幕宽
static NSString * const kCleanBorders    = @"DLCleanSystemBorders";  // 清除系统自带描边

static NSString * const kDisplayName     = @"你啊爸支鼎溜";
static NSString * const kVersionString    = @"1.0.2";

// hook kind
enum {
    DL_KIND_LAYOUT = 0,   // void(id, SEL)                    layoutSubviews / didMoveToWindow
    DL_KIND_FRAME  = 1,   // void(id, SEL, CGRect)            setFrame:
    DL_KIND_GETTER = 2,   // id(id, SEL)                      返回 view 的 getter
    DL_KIND_SETCOL = 3,   // void(id, SEL, UIColor*)          setBackgroundColor:
    DL_KIND_SETVW  = 4,   // void(id, SEL, UIView*)           setXxxBackgroundView:
    DL_KIND_TABLE  = 5,   // void(id, SEL)                    UITableView/容器，仅首页上下文生效
};

// group
enum {
    DL_GROUP_HOME   = 0,
    DL_GROUP_GLOBAL = 1,
    DL_GROUP_BUBBLE = 2,
    DL_GROUP_SYSTEM = 3,
};

// ------------------------------------------------------------
// MARK: - 偏好读取
// ------------------------------------------------------------

static inline id DLGet(NSString *k) { return [[NSUserDefaults standardUserDefaults] objectForKey:k]; }
static inline BOOL DLOn(NSString *k, BOOL def) {
    id v = DLGet(k);
    return v == nil ? def : [v boolValue];
}
static inline CGFloat DLNum(NSString *k, CGFloat def) {
    id v = DLGet(k);
    return (v == nil || ![v respondsToSelector:@selector(doubleValue)]) ? def : [v doubleValue];
}
static inline NSString *DLStr(NSString *k) {
    id v = DLGet(k);
    return [v isKindOfClass:[NSString class]] ? v : @"";
}

static BOOL DLMaster(void)   { return DLOn(kMaster, YES); }
static BOOL DLEnableHome(void)   { return DLOn(kHomeEnable, YES); }
static BOOL DLEnableGlobal(void) { return DLOn(kGlobalEnable, YES); }
static BOOL DLEnableBubble(void) { return DLOn(kBubbleEnable, YES); }
static BOOL DLEnableSystem(void) { return DLOn(kSystemRound, YES); }

static CGFloat DLRadiusForGroupNSInteger(NSInteger group) {
    switch (group) {
        case DL_GROUP_HOME:   return DLNum(kHomeRadius, 18.0);
        case DL_GROUP_BUBBLE: return DLNum(kBubbleRadius, 16.0);
        default:              return DLNum(kGlobalRadius, 14.0);
    }
}

// ------------------------------------------------------------
// MARK: - 颜色解析  "light:#RRGGBB(AA);dark:#RRGGBB(AA)"
// ------------------------------------------------------------

static UIColor *DLColorFromHex(NSString *hex) {
    if (!hex || !hex.length) return nil;
    NSMutableString *s = [hex mutableCopy];
    [s replaceOccurrencesOfString:@"#" withString:@"" options:0 range:NSMakeRange(0, s.length)];
    // 支持命名色
    static NSDictionary *named = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        named = @{@"white": @"FFFFFF", @"black": @"000000", @"clear": @"00000000",
                  @"red": @"FF3B30", @"blue": @"007AFF", @"green": @"34C759",
                  @"gray": @"8E8E93", @"orange": @"FF9500", @"yellow": @"FFCC00"};
        NSString *l = [[s lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *m = named[l];
        if (m) [s setString:m];
    });
    if (s.length != 6 && s.length != 8) return nil;
    unsigned int v = 0;
    NSScanner *sc = [NSScanner scannerWithString:s];
    if (![sc scanHexInt:&v]) return nil;
    CGFloat r, g, b, a = 1.0;
    if (s.length == 8) {
        r = ((v >> 24) & 0xFF) / 255.0; g = ((v >> 16) & 0xFF) / 255.0;
        b = ((v >>  8) & 0xFF) / 255.0; a = ( v        & 0xFF) / 255.0;
    } else {
        r = ((v >> 16) & 0xFF) / 255.0; g = ((v >>  8) & 0xFF) / 255.0;
        b = ( v        & 0xFF) / 255.0;
    }
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static UIColor *DLDynamicColor(NSString *pair) {
    if (!pair.length) return nil;
    UIColor *light = nil, *dark = nil;
    for (NSString *part in [pair componentsSeparatedByString:@";"]) {
        NSString *p = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (p.length < 6) continue;
        NSRange colon = [p rangeOfString:@":"];
        NSString *key = colon.location == NSNotFound ? @"light" : [p substringToIndex:colon.location];
        NSString *val = colon.location == NSNotFound ? p : [p substringFromIndex:colon.location + 1];
        UIColor *c = DLColorFromHex(val);
        if (!c) continue;
        if ([key.lowercaseString isEqualToString:@"dark"]) dark = c; else light = c;
    }
    if (!light && !dark) return nil;
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
            if (tc.userInterfaceStyle == UIUserInterfaceStyleDark) return dark ?: light;
            return light ?: dark;
        }];
    }
    return light ?: dark;
}

// ------------------------------------------------------------
// MARK: - swizzle 基础设施
// ------------------------------------------------------------

static NSMapTable *gOrigMap = nil;   // "Class|SEL" -> NSValue(IMP)

static NSString *DLKeyFor(Class c, SEL s) {
    return [NSStringFromClass(c) stringByAppendingFormat:@"|%@", NSStringFromSelector(s)];
}

static IMP DLOrigIMP(id self, SEL _cmd) {
    if (!gOrigMap) return NULL;
    // 沿继承链回溯：子类实例调用父类挂的 hook 时，也要能找到 orig
    for (Class c = object_getClass(self); c; c = class_getSuperclass(c)) {
        NSValue *v = [gOrigMap objectForKey:DLKeyFor(c, _cmd)];
        if (v) return (IMP)[v pointerValue];
    }
    return NULL;
}

static void DLStoreOrig(Class c, SEL s, IMP orig) {
    if (!gOrigMap) {
        gOrigMap = [NSMapTable mapTableWithKeyOptions:NSMapTableStrongMemory
                                         valueOptions:NSMapTableStrongMemory];
    }
    [gOrigMap setObject:[NSValue valueWithPointer:orig] forKey:DLKeyFor(c, s)];
}

// 前置声明：DLIsOurImp 需要引用后面定义的各 hook IMP
static void DLLayoutIMP(id self, SEL _cmd);
static void DLFrameIMP(id self, SEL _cmd, CGRect f);
static id DLGetterIMP(id self, SEL _cmd);
static void DLSetColorIMP(id self, SEL _cmd, UIColor *c);
static void DLSetViewIMP(id self, SEL _cmd, UIView *arg);
static void DLHomeTableIMP(id self, SEL _cmd);
static void DLSearchBarLayoutIMP(id self, SEL _cmd);
static void DLLayerBorderIMP(id self, SEL _cmd, CGFloat w);

/// 判断某个 IMP 是否是我们自己的 hook 实现。
/// 关键防崩溃逻辑：hook 表里有父子类对（UITableView/MMTableView、UIButton/FixTitleColorButton 等）。
/// 父类挂完后，class_getInstanceMethod(子类, sel) 返回的是继承来的「已替换」实现；
/// 若不检测直接再挂，orig 会存成我们自己的 hook → 调自己 → 无限递归栈溢出 → 启动即闪退。
static BOOL DLIsOurImp(IMP imp) {
    if (!imp) return NO;
    return imp == (IMP)DLLayoutIMP || imp == (IMP)DLFrameIMP || imp == (IMP)DLGetterIMP
        || imp == (IMP)DLSetColorIMP || imp == (IMP)DLSetViewIMP || imp == (IMP)DLHomeTableIMP
        || imp == (IMP)DLSearchBarLayoutIMP || imp == (IMP)DLLayerBorderIMP;
}

/// 替换实例方法实现；方法不存在或已被本插件挂过（含继承自父类）时返回 NO
static BOOL DLSwizzle(Class c, SEL s, IMP newImp) {
    if (!c) return NO;
    Method m = class_getInstanceMethod(c, s);
    if (!m) return NO;
    IMP cur = method_getImplementation(m);
    if (DLIsOurImp(cur)) return NO;   // 父类已挂：跳过子类条目，避免自我递归
    DLStoreOrig(c, s, cur);
    method_setImplementation(m, newImp);
    return YES;
}

// ------------------------------------------------------------
// MARK: - 圆角应用
// ------------------------------------------------------------

static void DLApplyRound(UIView *v, CGFloat r) {
    if (!v || r <= 0) return;
    CALayer *l = v.layer;
    l.cornerRadius = r;
    l.masksToBounds = YES;
    if (DLOn(kContinuous, YES)) {
        if (@available(iOS 13.0, *)) {
            if ([l respondsToSelector:@selector(cornerCurve)]) l.cornerCurve = kCACornerCurveContinuous;
        }
    }
    if (DLOn(kBorderOn, NO)) {
        l.borderWidth = DLNum(kBorderWidth, 1.0);
        UIColor *bc = DLDynamicColor(DLStr(kBorderColor));
        if (bc) l.borderColor = bc.CGColor;
    }
}

static void DLClearColorIfSystemBackground(UIView *v) {
    // 首页原思路：清除 _UISystemBackgroundView 的底色，避免圆角外露白
    NSString *cls = NSStringFromClass([v class]);
    if ([cls hasPrefix:@"_UISystemBackground"]) {
        v.backgroundColor = [UIColor clearColor];
        for (UIView *sub in v.subviews) {
            if ([NSStringFromClass([sub class]) hasPrefix:@"_UISystemBackground"]) sub.backgroundColor = [UIColor clearColor];
        }
    }
}

static BOOL gInBgOverride = NO;

// ------------------------------------------------------------
// MARK: - 通用 hook 实现
// ------------------------------------------------------------

static void DLLayoutIMP(id self, SEL _cmd) {
    IMP orig = DLOrigIMP(self, _cmd);
    if (orig) ((void(*)(id, SEL))orig)(self, _cmd);
    if (!DLMaster()) return;
    UIView *v = self;
    if (![v isKindOfClass:[UIView class]]) return;
    DLClearColorIfSystemBackground(v);
    DLApplyRound(v, DLRadiusForGroupNSInteger(DL_GROUP_GLOBAL));
}

static void DLFrameIMP(id self, SEL _cmd, CGRect f) {
    IMP orig = DLOrigIMP(self, _cmd);
    if (DLMaster() && DLOn(kFullWidth, NO)) {
        CGFloat sw = [UIScreen mainScreen].bounds.size.width;
        if (f.size.width < sw - 1.0 && f.size.width > 1.0) {
            f.origin.x = 0;
            f.size.width = sw;
        }
    }
    if (orig) ((void(*)(id, SEL, CGRect))orig)(self, _cmd, f);
    if (DLMaster() && [self isKindOfClass:[UIView class]]) {
        DLApplyRound((UIView *)self, DLRadiusForGroupNSInteger(DL_GROUP_GLOBAL));
    }
}

static id DLGetterIMP(id self, SEL _cmd) {
    IMP orig = DLOrigIMP(self, _cmd);
    id r = orig ? ((id(*)(id, SEL))orig)(self, _cmd) : nil;
    if (DLMaster() && [r isKindOfClass:[UIView class]]) {
        DLApplyRound((UIView *)r, DLRadiusForGroupNSInteger(DL_GROUP_GLOBAL));
    }
    return r;
}

static void DLSetColorIMP(id self, SEL _cmd, UIColor *c) {
    IMP orig = DLOrigIMP(self, _cmd);
    if (orig) ((void(*)(id, SEL, id))orig)(self, _cmd, c);
    if (!DLMaster() || gInBgOverride) return;
    NSString *pair = DLStr(kHomeColors);
    if (pair.length) {
        UIColor *dyn = DLDynamicColor(pair);
        if (dyn) {
            gInBgOverride = YES;
            ((void(*)(id, SEL, id))objc_msgSend)(self, _cmd, dyn);
            gInBgOverride = NO;
        }
    }
}

static void DLSetViewIMP(id self, SEL _cmd, UIView *arg) {
    IMP orig = DLOrigIMP(self, _cmd);
    if (orig) ((void(*)(id, SEL, id))orig)(self, _cmd, arg);
    if (DLMaster() && [arg isKindOfClass:[UIView class]]) {
        DLApplyRound(arg, DLRadiusForGroupNSInteger(DL_GROUP_BUBBLE));
    }
}

/// UITableView 等容器：仅当所属页面是聊天列表/会话盒子时应用圆角
static BOOL DLInHomeContext(UIView *v) {
    for (UIView *p = v; p; p = p.superview) {
        UIResponder *r = p;
        while (r && ![r isKindOfClass:[UIViewController class]]) r = [r nextResponder];
        if ([r isKindOfClass:[UIViewController class]]) {
            NSString *vc = NSStringFromClass([r class]);
            return ([vc isEqualToString:@"NewMainFrameViewController"] ||
                    [vc isEqualToString:@"MGSessionBoxViewController"] ||
                    [vc isEqualToString:@"MainTabBarViewController"]);
        }
    }
    return NO;
}

static void DLHomeTableIMP(id self, SEL _cmd) {
    IMP orig = DLOrigIMP(self, _cmd);
    if (orig) ((void(*)(id, SEL))orig)(self, _cmd);
    if (!DLMaster() || !DLEnableHome()) return;
    UIView *v = self;
    if (![v isKindOfClass:[UIView class]]) return;
    if (DLInHomeContext(v)) {
        DLClearColorIfSystemBackground(v);
        DLApplyRound(v, DLRadiusForGroupNSInteger(DL_GROUP_HOME));
    }
}

// ------------------------------------------------------------
// MARK: - 手工特判 hook
// ------------------------------------------------------------

// ---- 搜索框 (来自 首页圆角: WCSearchBar / UISearchBar / _searchBarTextField) ----
static void DLSearchBarLayoutIMP(id self, SEL _cmd) {
    IMP orig = DLOrigIMP(self, _cmd);
    if (orig) ((void(*)(id, SEL))orig)(self, _cmd);
    if (!DLMaster() || !DLOn(kSearchRound, YES)) return;
    if (![self isKindOfClass:[UISearchBar class]]) return;
    UISearchBar *sb = (UISearchBar *)self;
    CGFloat r = DLRadiusForGroupNSInteger(DL_GROUP_HOME) + 2.0;
    sb.layer.cornerRadius = r;
    sb.layer.masksToBounds = YES;
    UITextField *tf = nil;
    if ([sb respondsToSelector:@selector(searchTextField)]) {
        tf = [sb performSelector:@selector(searchTextField)];
    } else {
        for (UIView *sub in sb.subviews) {
            if ([sub isKindOfClass:[UITextField class]]) { tf = (UITextField *)sub; break; }
        }
    }
    if (tf) {
        tf.layer.cornerRadius = MAX(r - 5.0, 6.0);
        tf.clipsToBounds = YES;
        if ([NSStringFromClass([tf class]) isEqualToString:@"_UISearchBarSearchFieldBackgroundView"]) {
            tf.backgroundColor = [UIColor clearColor];
        }
    }
}

// ---- UITableViewCell 分组圆角 (来自 首页圆角: class_addMethod "_roundedGroupCornerRadius") ----
static CGFloat DLRoundedGroupCornerRadiusIMP(id self, SEL _cmd) {
    return DLMaster() ? DLRadiusForGroupNSInteger(DL_GROUP_HOME) : 0.0;
}

// ---- CALayer setBorderWidth: (来自 微信圆角: 清理系统自带描边) ----
static void DLLayerBorderIMP(id self, SEL _cmd, CGFloat w) {
    IMP orig = DLOrigIMP(self, _cmd);
    if (DLMaster() && DLOn(kCleanBorders, NO) && w > 0 && w <= 1.5) {
        w = 0; // 按需抹掉 WeChat 给卡片画的 1px 描边，交给自己的描边开关
    }
    if (orig) ((void(*)(id, SEL, CGFloat))orig)(self, _cmd, w);
}

// ------------------------------------------------------------
// MARK: - hook 表 (逆向整合自两个原始 dylib)
//   kind: 0 layout / 1 frame / 2 getter / 3 setColor / 4 setView / 5 homeTable
//   group: 0 home / 1 global / 2 bubble / 3 system
// ------------------------------------------------------------

typedef struct { const char *cls; const char *sel; int kind; int group; } DLEntry;

static const DLEntry gTable[] = {
    // ===== 首页 / 聊天列表 (源自 微信首页圆角) =====
    {"MMTableViewCell",                     "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_HOME},
    {"MMMultiMenuTableViewCell",            "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_HOME},
    {"MMMultiMenuTableViewCell",            "setBackgroundColor:",          DL_KIND_SETCOL, DL_GROUP_HOME},
    {"MainFrameSectionFoldView",            "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_HOME},
    {"MMTableSectionHeaderView",            "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_HOME},
    {"ChatTableViewCell",                   "setFrame:",                    DL_KIND_FRAME,  DL_GROUP_HOME},
    {"UITableViewCell",                     "setFrame:",                    DL_KIND_FRAME,  DL_GROUP_HOME},
    {"UITableViewHeaderFooterView",         "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_HOME},
    {"UITableViewCellContentView",          "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_SYSTEM},
    {"UITableViewCell",                     "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_SYSTEM},
    {"UITableView",                         "layoutSubviews",               DL_KIND_TABLE,  DL_GROUP_HOME},
    {"MMTableView",                         "layoutSubviews",               DL_KIND_TABLE,  DL_GROUP_HOME},

    // ===== 全局控件 (源自 微信圆角) =====
    {"MMMenuContentView",                   "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MMToastView",                         "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MMInputMsgReferView",                 "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MMInputMsgReferView",                 "thumbImageView",               DL_KIND_GETTER, DL_GROUP_GLOBAL},
    {"WCDragCollectionView",                "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCImageFullScreenViewContainer",      "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCFinderFullMultiMediaCollectionView","layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCPlayerView",                        "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCPlayableImageView",                 "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MultiColumnReaderMessageCellView",    "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"WCPayRecepictReaderMessageCellView",  "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"AppHardWareRankMessageCellView",      "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"EmoticonBoardCrossCollectionQQEmojiPageCell", "layoutSubviews",       DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MMFinderLiveProductButton",           "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MMLiveIconButton",                    "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCFinderMaskButton",                  "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MMBorderView",                        "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"FixTitleColorButton",                 "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCFinderBothSideIconButton",          "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCPayDecimalKeyboardView",            "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCPayDecimalKeyboardView",            "floatConfirmBtn",              DL_KIND_GETTER, DL_GROUP_GLOBAL},
    {"VoiceMessageCellView",                "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"FavSearchBar",                        "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MMFavCellComponent",                  "didMoveToWindow",              DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"BizAppBaseMessageCellView",           "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"VoIPInvitationBreadthQuickReplyView", "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"VoIPInvitationBreadthInviteView",     "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCFinderCommentInputBackView",        "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCFinderTemplateVideoCommentView",    "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCFinderTemplateCommentArrowButton",  "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCFinderCommentAdTableViewCell",      "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCFinderCommentHeatUpTipsView",       "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCCommentInputView",                  "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"TextStatePublishCustomIconView",      "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"TextStatePublishOfficialIconSectionBackgroundView", "layoutSubviews", DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCPayWalletEntryHeaderView",          "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCPayWalletDecorationView",           "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCPayWalletBusinessSectionHeader",    "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCTableView",                         "layoutSubviews",               DL_KIND_TABLE,  DL_GROUP_GLOBAL},
    {"WCRedEnvelopesReceiveHomeView",       "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MsgFileBrowseItemView",               "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"UISearchBarTextField",                "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_SYSTEM},
    {"WAMainFrameTaskBarSearchBar",         "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"NewContactsSearchPanelView",          "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"StorageUsageDetailView",              "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MultiDeviceCardView",                 "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MMGrowTextView",                      "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MMGrowTextView",                      "didMoveToWindow",              DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCBaseTimelineViewController",        "setGrowTextViewBackGroundView:", DL_KIND_SETVW, DL_GROUP_BUBBLE},
    {"WCCommentDetailViewControllerFB",     "setGrowTextViewBackGroundView:", DL_KIND_SETVW, DL_GROUP_BUBBLE},
    {"MMTransparentButton",                 "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MultiReaderMessageCellView",          "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"ReaderMessageCellView",               "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"AppWxGameCardMessageCellView",        "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"TextReaderMessageCellView",           "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"ReaderItemView",                      "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"MMSnackBarView",                      "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"AppFileMessageCellView",              "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"AppRecordMessageCellView",            "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"EditVideoInitialView",                "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"TipsView",                            "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MMNewMsgContentNavBar",               "bgMaskView",                   DL_KIND_GETTER, DL_GROUP_GLOBAL},
    {"MMNewMsgContentNavBar",               "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MMMsgContentNavBar",                  "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCPayFaceHBPayView",                  "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MMFinderLiveAudienceGoodsCell",       "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MMFinderLiveGoodsSKUCell",            "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCFinderHeadInfoEasyView",            "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCListTextCellView",                  "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"WCTextThumbView",                     "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"TextStateHistoryCalendarSectionBackgroundView", "layoutSubviews",     DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MMCellLikeCollectionViewCell",        "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"TextMessageCellView",                 "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"CommonMessageCellView",               "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"WCFinderMusicEventHeaderView",        "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCContentItemViewTemplateNote",       "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"WNAttachmentBaseView",                "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"BrandProfileItemBaseCell",            "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCFinderShareLiveCellView",           "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCMediaImageScrollView",              "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCListMusicCellViewNew",              "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"AppPatMessageCellView",               "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"ChatTimeCellView",                    "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MailMessageCellView",                 "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"KindaUIView",                         "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"KindaUIButton",                       "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"QuickReplyMsgNotifyView",             "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"TextStateProfileTableView",           "layoutSubviews",               DL_KIND_TABLE,  DL_GROUP_GLOBAL},
    {"WCPayWalletBusinessCell",             "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"EmotionCollectionViewCell",           "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"BTReaderItemCellView",                "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"ChatRoomInvitationMultiMenuTableViewCell", "layoutSubviews",          DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MMActionSheetQRCodeRowView",          "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"ThemeBoxThemeView",                   "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"ThemeBoxTagView",                     "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"ThemeBoxActionView",                  "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"SharePreConfirmSuccessView",          "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"SharePreConfirmSheetView",            "sendButton",                   DL_KIND_GETTER, DL_GROUP_GLOBAL},
    {"NotifyLiveImageMessageCellView",      "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"MMUINavigationBar",                   "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MMTabBar",                            "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"AppMMScheduleMessageCellView",        "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"StrongNotificationContentView",       "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"SelectAttachmentView",                "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"MultiTalkMemberCell",                 "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WeappToolItemView",                   "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"ThirdPartyServiceListCell",           "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"FavRecordReferView",                  "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCFinderShareLiveView",               "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCListFeedCellView",                  "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"WCSearchViewController",              "navBarContainerView",          DL_KIND_GETTER, DL_GROUP_GLOBAL},
    {"MMUISearchBar",                       "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_SYSTEM},
    {"SessionSelectView",                   "recentChatHeaderView",         DL_KIND_GETTER, DL_GROUP_GLOBAL},
    {"MMUIView",                            "setBackgroundColor:",          DL_KIND_SETCOL, DL_GROUP_GLOBAL},
    {"WCPayBizF2FTransferMoneyViewController", "m_imageView",               DL_KIND_GETTER, DL_GROUP_GLOBAL},
    {"UIButton",                            "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_SYSTEM},
    {"AppFileMessageCellViewV2",            "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"AppNoteMessageCellViewClassic",       "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"AppRecordMessageCellViewClassic",     "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"BrandMyTabEntranceCardView",          "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCFinderMyTabFinderCardView",         "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"WCFinderQRCodeViewController",        "cardView",                     DL_KIND_GETTER, DL_GROUP_GLOBAL},
    {"MMImagePreviewActionSheet_ImageView", "imageView",                    DL_KIND_GETTER, DL_GROUP_GLOBAL},
    {"MMGrowTextViewWithExtras",            "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"CardImageView",                       "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_GLOBAL},
    {"AppUrlMessageCellViewClassic",        "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"AppUrlMessageImageView",              "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"MsgMediaGroupCard",                   "layoutSubviews",               DL_KIND_LAYOUT, DL_GROUP_BUBBLE},
    {"UISearchBar",                         "didMoveToWindow",              DL_KIND_LAYOUT, DL_GROUP_SYSTEM},
};

static const int gTableCount = (int)(sizeof(gTable) / sizeof(gTable[0]));

// ------------------------------------------------------------
// MARK: - 设置页
// ------------------------------------------------------------

@class DLSettingsController;

static void DLPushSettings(void) {
    // 找最顶层 VC，push 我们的设置页
    UIViewController *top = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (!w.keyWindow) continue;
        UIViewController *find = w.rootViewController;
        while (find.presentedViewController) find = find.presentedViewController;
        if ([find isKindOfClass:[UINavigationController class]]) {
            find = [(UINavigationController *)find topViewController];
        }
        top = find;
        break;
    }
    if (!top) return;
    UIViewController *s = [[NSClassFromString(@"DLSettingsController") alloc] init];
    UINavigationController *nav = nil;
    if ([top.navigationController isKindOfClass:[UINavigationController class]]) {
        nav = top.navigationController;
        [nav pushViewController:s animated:YES];
    } else {
        UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:s];
        nc.modalPresentationStyle = UIModalPresentationFullScreen;
        [top presentViewController:nc animated:YES completion:nil];
    }
}

@interface DLSettingsController : UITableViewController <UITextFieldDelegate>
@end

@implementation DLSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kDisplayName;
    self.tableView.rowHeight = 48.0;
    if (@available(iOS 13.0, *)) {
        self.tableView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    }
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone
                                                            target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = done;
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 5; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 1;           // 总开关
        case 1: return 3;           // 首页
        case 2: return 4;           // 全局
        case 3: return 3;           // 描边
        case 4: return 4;           // 其他
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    switch (s) {
        case 0: return @"总开关";
        case 1: return @"首页 / 聊天列表";
        case 2: return @"全局圆角";
        case 3: return @"描边";
        case 4: return @"其他";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 4) return [NSString stringWithFormat:@"%@ v1.0.2 — 适配微信 8.0.70+，rootless / TrollFools 通用。改动保存后回到页面自动生效。", kDisplayName];
    return nil;
}

- (UITableViewCell *)cell:(UITableView *)tv {
    static NSString *idc = @"DLCell";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:idc];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:idc];
    return c;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [self cell:tv];
    c.accessoryView = nil;
    c.accessoryType = UITableViewCellAccessoryNone;
    c.detailTextLabel.text = nil;

    UISwitch *sw = [[UISwitch alloc] init];
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    c.textLabel.text = nil;

    switch (ip.section) {
        case 0:
            c.textLabel.text = @"启用圆角美化";
            sw.on = DLMaster(); sw.tag = 100;
            c.accessoryView = sw;
            break;
        case 1:
            if (ip.row == 0) { c.textLabel.text = @"首页圆角半径"; c.detailTextLabel.text = [self numText:kHomeRadius def:@18]; }
            else if (ip.row == 1) {
                c.textLabel.text = @"单元格背景色";
                UITextField *tf = [self fieldWithKey:kHomeColors placeholder:@"light:#FFF;dark:#1C1C1E"];
                c.accessoryView = tf;
            }
            else { c.textLabel.text = @"搜索框圆角"; sw.on = DLOn(kSearchRound, YES); sw.tag = 101; c.accessoryView = sw; }
            break;
        case 2:
            if (ip.row == 0) { c.textLabel.text = @"启用全局圆角"; sw.on = DLEnableGlobal(); sw.tag = 102; c.accessoryView = sw; }
            else if (ip.row == 1) { c.textLabel.text = @"全局半径"; c.detailTextLabel.text = [self numText:kGlobalRadius def:@14]; }
            else if (ip.row == 2) { c.textLabel.text = @"气泡圆角"; sw.on = DLEnableBubble(); sw.tag = 103; c.accessoryView = sw; }
            else { c.textLabel.text = @"气泡半径"; c.detailTextLabel.text = [self numText:kBubbleRadius def:@16]; }
            break;
        case 3:
            if (ip.row == 0) { c.textLabel.text = @"启用描边"; sw.on = DLOn(kBorderOn, NO); sw.tag = 104; c.accessoryView = sw; }
            else if (ip.row == 1) {
                c.textLabel.text = @"描边颜色";
                c.accessoryView = [self fieldWithKey:kBorderColor placeholder:@"light:#22000000;dark:#22FFFFFF"];
            }
            else { c.textLabel.text = @"描边粗细"; c.detailTextLabel.text = [self numText:kBorderWidth def:@1]; }
            break;
        case 4:
            if (ip.row == 0) { c.textLabel.text = @"连续曲率(更圆滑)"; sw.on = DLOn(kContinuous, YES); sw.tag = 105; c.accessoryView = sw; }
            else if (ip.row == 1) { c.textLabel.text = @"系统控件也圆角"; sw.on = DLEnableSystem(); sw.tag = 106; c.accessoryView = sw; }
            else if (ip.row == 2) { c.textLabel.text = @"单元格铺满屏幕宽"; sw.on = DLOn(kFullWidth, NO); sw.tag = 107; c.accessoryView = sw; }
            else { c.textLabel.text = @"恢复默认设置"; c.textLabel.textColor = [UIColor systemRedColor]; c.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
            break;
    }
    return c;
}

- (NSString *)numText:(NSString *)key def:(NSNumber *)d {
    id v = DLGet(key);
    return [v respondsToSelector:@selector(stringValue)] ? [v stringValue] : [d stringValue];
}

- (UITextField *)fieldWithKey:(NSString *)key placeholder:(NSString *)ph {
    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 170, 34)];
    tf.borderStyle = UITextBorderStyleRoundedRect;
    tf.font = [UIFont systemFontOfSize:12];
    tf.placeholder = ph;
    tf.textAlignment = NSTextAlignmentRight;
    tf.delegate = self;
    tf.tag = [key hash] & 0xFFFF;
    objc_setAssociatedObject(tf, @selector(tag), key, OBJC_ASSOCIATION_RETAIN);
    [tf addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventEditingChanged];
    id v = DLGet(key);
    if ([v isKindOfClass:[NSString class]]) tf.text = v;
    return tf;
}

- (void)switchChanged:(UISwitch *)s {
    NSString *key = nil;
    switch (s.tag) {
        case 100: key = kMaster; break;
        case 101: key = kSearchRound; break;
        case 102: key = kGlobalEnable; break;
        case 103: key = kBubbleEnable; break;
        case 104: key = kBorderOn; break;
        case 105: key = kContinuous; break;
        case 106: key = kSystemRound; break;
        case 107: key = kFullWidth; break;
    }
    if (key) [[NSUserDefaults standardUserDefaults] setBool:s.on forKey:key];
}

- (void)fieldChanged:(UITextField *)tf {
    NSString *key = objc_getAssociatedObject(tf, @selector(tag));
    if (!key) return;
    // 数字键
    if ([key isEqualToString:kHomeRadius] || [key isEqualToString:kGlobalRadius] ||
        [key isEqualToString:kBubbleRadius] || [key isEqualToString:kBorderWidth]) {
        CGFloat d = tf.text.doubleValue;
        [[NSUserDefaults standardUserDefaults] setDouble:d forKey:key];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:tf.text ?: @"" forKey:key];
    }
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 4 && ip.row == 3) {
        NSArray *keys = @[kMaster, kHomeEnable, kHomeRadius, kHomeColors, kSearchRound,
                          kGlobalEnable, kGlobalRadius, kBubbleEnable, kBubbleRadius,
                          kBorderOn, kBorderWidth, kBorderColor, kContinuous,
                          kSystemRound, kFullWidth, kCleanBorders];
        for (NSString *k in keys) [[NSUserDefaults standardUserDefaults] removeObjectForKey:k];
        [self.tableView reloadData];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }

@end

// ------------------------------------------------------------
// MARK: - 设置入口注入 ("我" 页 / 设置页)
//   思路来自 首页圆角 的 MoreViewController hooks：
//   numberOfSectionsInTableView:+1，末区追加一行 "你啊爸支鼎溜"
// ------------------------------------------------------------

static IMP gOrigMoreSections = NULL;
static IMP gOrigMoreRows     = NULL;
static IMP gOrigMoreCell     = NULL;
static IMP gOrigMoreSelect   = NULL;

static NSInteger DLMoreSectionsIMP(id self, SEL _cmd, id tv) {
    NSInteger n = gOrigMoreSections ? ((NSInteger(*)(id, SEL, id))gOrigMoreSections)(self, _cmd, tv) : 0;
    return n + 1;
}

static NSInteger DLMoreRowsIMP(id self, SEL _cmd, id tv, NSInteger section) {
    NSInteger n = gOrigMoreRows ? ((NSInteger(*)(id, SEL, id, NSInteger))gOrigMoreRows)(self, _cmd, tv, section) : 0;
    // 仅最后一个区（我们追加的区）给 1 行
    NSInteger sections = gOrigMoreSections ? ((NSInteger(*)(id, SEL, id))gOrigMoreSections)(self, _cmd, tv) : 0;
    if (section == sections) return 1;
    return n;
}

static UITableViewCell *DLMoreCellIMP(id self, SEL _cmd, id tv, NSIndexPath *ip) {
    NSInteger sections = gOrigMoreSections ? ((NSInteger(*)(id, SEL, id))gOrigMoreSections)(self, _cmd, tv) : 0;
    if (ip.section == sections) {
        static NSString *idk = @"DLEntryCell";
        UITableViewCell *c = [(UITableView *)tv dequeueReusableCellWithIdentifier:idk];
        if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:idk];
        c.textLabel.text = kDisplayName;
        c.detailTextLabel.text = @"微信圆角美化";
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    return gOrigMoreCell ? ((UITableViewCell*(*)(id, SEL, id, NSIndexPath*))gOrigMoreCell)(self, _cmd, tv, ip) : nil;
}

static void DLMoreSelectIMP(id self, SEL _cmd, id tv, NSIndexPath *ip) {
    NSInteger sections = gOrigMoreSections ? ((NSInteger(*)(id, SEL, id))gOrigMoreSections)(self, _cmd, tv) : 0;
    if (ip.section == sections) {
        [(UITableView *)tv deselectRowAtIndexPath:ip animated:YES];
        DLPushSettings();
        return;
    }
    if (gOrigMoreSelect) ((void(*)(id, SEL, id, NSIndexPath*))gOrigMoreSelect)(self, _cmd, tv, ip);
}

static void DLHookEntryPage(NSString *clsName) {
    Class cls = NSClassFromString(clsName);
    if (!cls) return;
    SEL s1 = @selector(numberOfSectionsInTableView:);
    SEL s2 = @selector(tableView:numberOfRowsInSection:);
    SEL s3 = @selector(tableView:cellForRowAtIndexPath:);
    SEL s4 = @selector(tableView:didSelectRowAtIndexPath:);
    // 只 hook 一次；MoreViewController 优先，NewSettingViewController 兜底
    if (!gOrigMoreSections) {
        Method m = class_getInstanceMethod(cls, s1);
        if (m) { gOrigMoreSections = method_getImplementation(m); method_setImplementation(m, (IMP)DLMoreSectionsIMP); }
    }
    if (!gOrigMoreRows) {
        Method m = class_getInstanceMethod(cls, s2);
        if (m) { gOrigMoreRows = method_getImplementation(m); method_setImplementation(m, (IMP)DLMoreRowsIMP); }
    }
    if (!gOrigMoreCell) {
        Method m = class_getInstanceMethod(cls, s3);
        if (m) { gOrigMoreCell = method_getImplementation(m); method_setImplementation(m, (IMP)DLMoreCellIMP); }
    }
    if (!gOrigMoreSelect) {
        Method m = class_getInstanceMethod(cls, s4);
        if (m) { gOrigMoreSelect = method_getImplementation(m); method_setImplementation(m, (IMP)DLMoreSelectIMP); }
    }
}

// ------------------------------------------------------------
// MARK: - 插件收纳接入 (WCPluginsMgr)
//   按《插件收纳接入声明》：hook MinimizeViewController 的 viewDidLoad，
//   调用 WCPluginsMgr.sharedInstance registerControllerWithTitle:version:controller:
//   把 dingliu 的设置页收纳进插件归类列表。
// ------------------------------------------------------------

static IMP  gOrigMinimizeViewDidLoad = NULL;
static BOOL gDLPluginsEntryRegistered = NO;

static void DLMinimizeViewDidLoadIMP(id self, SEL _cmd) {
    if (gOrigMinimizeViewDidLoad) ((void(*)(id, SEL))gOrigMinimizeViewDidLoad)(self, _cmd);

    if (!gDLPluginsEntryRegistered && NSClassFromString(@"WCPluginsMgr")) {
        gDLPluginsEntryRegistered = YES;
        @try {
            Class mgr = objc_getClass("WCPluginsMgr");
            id inst = [mgr performSelector:@selector(sharedInstance)];
            SEL reg = @selector(registerControllerWithTitle:version:controller:);
            if (inst && [inst respondsToSelector:reg]) {
                ((void(*)(id, SEL, id, id, id))objc_msgSend)(inst, reg,
                    kDisplayName,                  // 外显名：你啊爸支鼎溜
                    kVersionString,                // 版本号
                    @"DLSettingsController");      // 设置页 Controller 类名
            }
        } @catch (NSException *exception) {
            // 防止因微信版本变动导致闪退
        }
    }
}

// ------------------------------------------------------------
// MARK: - 安装
// ------------------------------------------------------------

static void DLRegisterDefaults(void) {
    NSDictionary *d = @{
        kMaster:       @YES,
        kHomeEnable:   @YES,
        kHomeRadius:   @18.0,
        kHomeColors:   @"",
        kSearchRound:  @YES,
        kGlobalEnable: @YES,
        kGlobalRadius: @14.0,
        kBubbleEnable: @YES,
        kBubbleRadius: @16.0,
        kBorderOn:     @NO,
        kBorderWidth:  @1.0,
        kBorderColor:  @"light:#22000000;dark:#22FFFFFF",
        kContinuous:   @YES,
        kSystemRound:  @YES,
        kFullWidth:    @NO,
        kCleanBorders: @NO,
    };
    [[NSUserDefaults standardUserDefaults] registerDefaults:d];
}

__attribute__((constructor))
static void dingliu_init(void) {
    @autoreleasepool {
        DLRegisterDefaults();

        @try {
            if (DLOn(@"DLSafeMode", NO)) {
                // 安全模式：跳过所有外观 hook，只装设置入口，便于救砖
                NSLog(@"[dingliu] SAFE MODE: cosmetic hooks skipped");
            } else {
                // 数据驱动 hook 表
                IMP impTable[6] = {
                    (IMP)DLLayoutIMP, (IMP)DLFrameIMP, (IMP)DLGetterIMP,
                    (IMP)DLSetColorIMP, (IMP)DLSetViewIMP, (IMP)DLHomeTableIMP
                };
                int installed = 0;
                for (int i = 0; i < gTableCount; i++) {
                    const DLEntry *e = &gTable[i];
                    Class c = NSClassFromString(@(e->cls));
                    if (!c) continue;                                  // 类名守卫：新版微信改名/删除则跳过
                    if (e->group == DL_GROUP_SYSTEM && !DLEnableSystem()) continue;
                    SEL s = sel_registerName(e->sel);
                    if (DLSwizzle(c, s, impTable[e->kind])) installed++;
                }

                // 搜索框特判（UISearchBar 本体不进数据表，由这里统一处理，避免双重 hook）
                for (NSString *n in @[@"WCSearchBar", @"UISearchBar", @"MMUISearchBar"]) {
                    Class c = NSClassFromString(n);
                    if (c) DLSwizzle(c, @selector(layoutSubviews), (IMP)DLSearchBarLayoutIMP);
                }

                // UITableViewCell 分组圆角 API（原首页包用 class_addMethod 添加）
                Class cellCls = NSClassFromString(@"UITableViewCell");
                SEL selRGC = sel_registerName("_roundedGroupCornerRadius");
                if (cellCls && !class_getInstanceMethod(cellCls, selRGC)) {
                    class_addMethod(cellCls, selRGC, (IMP)DLRoundedGroupCornerRadiusIMP, "d@:");
                }

                // CALayer 描边清理（可选）
                Class layerCls = NSClassFromString(@"CALayer");
                if (layerCls) DLSwizzle(layerCls, @selector(setBorderWidth:), (IMP)DLLayerBorderIMP);

                NSLog(@"[dingliu] 你啊爸支鼎溜 loaded");
            }

            // 设置入口（安全模式下也保留，方便关闭插件）
            DLHookEntryPage(@"MoreViewController");
            DLHookEntryPage(@"NewSettingViewController");

            // 插件收纳接入：MinimizeViewController viewDidLoad 时注册入口
            Class minCls = NSClassFromString(@"MinimizeViewController");
            if (minCls) {
                Method m = class_getInstanceMethod(minCls, @selector(viewDidLoad));
                if (m) {
                    gOrigMinimizeViewDidLoad = method_getImplementation(m);
                    method_setImplementation(m, (IMP)DLMinimizeViewDidLoadIMP);
                }
            }
        } @catch (NSException *e) {
            // 构造阶段任何异常都不允许带崩微信
            NSLog(@"[dingliu] init exception: %@ — %@", e.name, e.reason);
        }
    }
}
