#import "WDStyle.h"
#import "WDDiag.h"
#import "WDPrefs.h"
#import <string.h>
#import <stdio.h>

#define WD_ASSOC OBJC_ASSOCIATION_RETAIN_NONATOMIC

static const void *kWDPlateKey       = &kWDPlateKey;
static const void *kWDTagKey         = &kWDTagKey;
static const void *kWDOrigRadiusKey  = &kWDOrigRadiusKey;
static const void *kWDOrigMaskKey    = &kWDOrigMaskKey;
static const void *kWDOrigCurveKey   = &kWDOrigCurveKey;
static const void *kWDOrigCornersKey = &kWDOrigCornersKey;
static const void *kWDOrigBgKey      = &kWDOrigBgKey;
static const void *kWDOrigBgColorKey = &kWDOrigBgColorKey;
static const void *kWDTableBgKey     = &kWDTableBgKey;
static const void *kWDOrigTFKey      = &kWDOrigTFKey;
static const void *kWDRowsCacheKey   = &kWDRowsCacheKey;
static const void *kWDCatCacheKey    = &kWDCatCacheKey;
static const void *kWDSelKey         = &kWDSelKey;
static const void *kWDProfileFillKey = &kWDProfileFillKey;
static const void *kWDOrigFrameKey    = &kWDOrigFrameKey;
static const void *kWDArrowHiddenKey  = &kWDArrowHiddenKey;
static const void *kWDTailClearKey    = &kWDTailClearKey;
// 搜索栏：为露出胶囊清掉沿途白底容器，记录下来以便还原
static const void *kWDClearedViewsKey = &kWDClearedViewsKey;
// 记录"这次刷上去的参数"，系统重新布局后可以原样重贴（防回弹 / 防错位）
static const void *kWDStyleKindKey    = &kWDStyleKindKey;
static const void *kWDStyleInsetKey   = &kWDStyleInsetKey;
static const void *kWDStyleRadiusKey  = &kWDStyleRadiusKey;
static const void *kWDStyleBusyKey    = &kWDStyleBusyKey;
static const void *kWDMomentsKey      = &kWDMomentsKey;

// 朋友圈每条动态是一张独立卡：四角全圆 + 上下留缝 + 不要分隔线
#define WD_MOMENTS_VGAP 6.0

enum { WDKindStyleView = 0, WDKindStyleCell = 1, WDKindStyleSearch = 2, WDKindStyleProfile = 3 };

static void WDRecordStyle(UIView *v, int kind, CGFloat inset, CGFloat radius) {
    if (!v) return;
    objc_setAssociatedObject(v, kWDStyleKindKey, @(kind), WD_ASSOC);
    objc_setAssociatedObject(v, kWDStyleInsetKey, @(inset), WD_ASSOC);
    objc_setAssociatedObject(v, kWDStyleRadiusKey, @(radius), WD_ASSOC);
}

static BOOL gColMaster = YES;
static BOOL gInOn = NO;
static BOOL gOutOn = NO;
static char gInL[16];
static char gInD[16];
static char gOutL[16];
static char gOutD[16];

// "布局后重贴"的钩子安装器由 Tweak.m 提供（那里才有 gLive/gMaster 开关），
// 样式层只负责"这个类也需要重贴"的请求
static void (*gRelayoutHookFn)(Class cls) = NULL;
void WDStyleSetRelayoutHook(void (*fn)(Class cls)) { gRelayoutHookFn = fn; }
static void WDRequestRelayoutHook(Class cls) { if (cls && gRelayoutHookFn) gRelayoutHookFn(cls); }

void WDStyleSyncColors(BOOL master, BOOL inOn, const char *inL, const char *inD,
                       BOOL outOn, const char *outL, const char *outD) {
    gColMaster = master;
    gInOn = inOn;
    gOutOn = outOn;
    gInL[0] = gInD[0] = gOutL[0] = gOutD[0] = 0;
    if (inL && inL[0]) snprintf(gInL, 16, "%s", inL);
    if (inD && inD[0]) snprintf(gInD, 16, "%s", inD);
    if (outL && outL[0]) snprintf(gOutL, 16, "%s", outL);
    if (outD && outD[0]) snprintf(gOutD, 16, "%s", outD);
}

static BOOL gStyleCont = YES;
void WDStyleSetContinuous(BOOL on) { gStyleCont = on; }

static BOOL WDStyleDark(void) {
    if (@available(iOS 13.0, *)) {
        return [UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return NO;
}

static UIColor *WDHexC(const char *s) {
    if (!s || !s[0]) return nil;
    return WDColorForHex([NSString stringWithUTF8String:s]);
}

@interface WDCardPlate : UIView
@property (nonatomic, strong) CAShapeLayer *fill;
@property (nonatomic, strong) CAShapeLayer *sep;
@property (nonatomic, assign) CGFloat radius;
@property (nonatomic, assign) NSUInteger corners;
@property (nonatomic, assign) CGFloat inset;
@property (nonatomic, assign) CGFloat vInset; // 上下也留缝（朋友圈每条动态一张独立卡）
@property (nonatomic, assign) BOOL showSep;
@property (nonatomic, assign) BOOL punch; // YES=打洞遮罩（不改内容坐标）
@end

@implementation WDCardPlate
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingNone;
        _corners = 15;
        _punch = YES;
        _fill = [CAShapeLayer layer];
        _fill.fillRule = kCAFillRuleEvenOdd;
        _fill.fillColor = [UIColor groupTableViewBackgroundColor].CGColor;
        if (@available(iOS 13.0, *)) {
            _fill.fillColor = [UIColor systemGroupedBackgroundColor].CGColor;
        }
        [self.layer addSublayer:_fill];
        _sep = [CAShapeLayer layer];
        _sep.fillColor = [UIColor colorWithWhite:0.75 alpha:0.45].CGColor;
        [self.layer addSublayer:_sep];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [self redraw];
}
- (void)traitCollectionDidChange:(UITraitCollection *)prev {
    [super traitCollectionDidChange:prev];
    [self redraw];
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    (void)point; (void)event;
    return nil;
}
- (void)redraw {
    CGRect r = self.bounds;
    if (r.size.width < 1 || r.size.height < 1) {
        _fill.path = NULL;
        _sep.path = NULL;
        return;
    }
    CGFloat inx = MAX(0, _inset);
    CGFloat vix = MAX(0, _vInset);
    CGRect hole = UIEdgeInsetsInsetRect(r, UIEdgeInsetsMake(vix, inx, vix, inx));
    if (hole.size.width < 8 || hole.size.height < 8) hole = UIEdgeInsetsInsetRect(r, UIEdgeInsetsMake(0, inx, 0, inx));
    if (hole.size.width < 8) hole = r;
    CGFloat rad = MIN(_radius, MIN(hole.size.width, hole.size.height) / 2.0);
    UIRectCorner uc = 0;
    NSUInteger c = _corners;
    if (c & kCALayerMinXMinYCorner) uc |= UIRectCornerTopLeft;
    if (c & kCALayerMaxXMinYCorner) uc |= UIRectCornerTopRight;
    if (c & kCALayerMinXMaxYCorner) uc |= UIRectCornerBottomLeft;
    if (c & kCALayerMaxXMaxYCorner) uc |= UIRectCornerBottomRight;
    UIBezierPath *holeP = nil;
    if (uc == 0 || rad <= 0.2) holeP = [UIBezierPath bezierPathWithRect:hole];
    else holeP = [UIBezierPath bezierPathWithRoundedRect:hole byRoundingCorners:uc cornerRadii:CGSizeMake(rad, rad)];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fill.frame = r;
    if (_punch) {
        UIBezierPath *p = [UIBezierPath bezierPathWithRect:r];
        [p appendPath:holeP];
        _fill.fillRule = kCAFillRuleEvenOdd;
        _fill.path = p.CGPath;
    } else {
        _fill.fillRule = kCAFillRuleNonZero;
        _fill.path = holeP.CGPath;
    }
    if (_showSep && hole.size.width > 8) {
        CGFloat spad = MIN(16.0, hole.size.width * 0.08);
        if (spad < 12.0) spad = MIN(12.0, hole.size.width / 6.0);
        CGRect sr = CGRectMake(hole.origin.x + spad, r.size.height - 1.0 / [UIScreen mainScreen].scale,
                               hole.size.width - spad * 2.0, 1.0 / [UIScreen mainScreen].scale);
        _sep.frame = r;
        _sep.path = [UIBezierPath bezierPathWithRect:sr].CGPath;
        _sep.hidden = NO;
    } else {
        _sep.path = NULL;
        _sep.hidden = YES;
    }
    [CATransaction commit];
}
@end

#pragma mark - 圆角

static void WDStoreOrig(UIView *v) {
    if (objc_getAssociatedObject(v, kWDOrigRadiusKey)) return;
    objc_setAssociatedObject(v, kWDOrigRadiusKey, @(v.layer.cornerRadius), WD_ASSOC);
    objc_setAssociatedObject(v, kWDOrigMaskKey, @(v.layer.masksToBounds ? 1 : 0), WD_ASSOC);
    objc_setAssociatedObject(v, kWDOrigCornersKey, @(v.layer.maskedCorners), WD_ASSOC);
    if (@available(iOS 13.0, *)) {
        if ([v.layer respondsToSelector:@selector(cornerCurve)]) {
            NSString *cv = v.layer.cornerCurve;
            if (cv) objc_setAssociatedObject(v, kWDOrigCurveKey, cv, WD_ASSOC);
        }
    }
}

static void WDRevertRound(UIView *v) {
    id orv = objc_getAssociatedObject(v, kWDOrigRadiusKey);
    if (!orv) return;
    id omv = objc_getAssociatedObject(v, kWDOrigMaskKey);
    id ocv = objc_getAssociatedObject(v, kWDOrigCurveKey);
    id ocn = objc_getAssociatedObject(v, kWDOrigCornersKey);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    v.layer.cornerRadius = [orv doubleValue];
    v.layer.masksToBounds = omv ? [omv boolValue] : NO;
    if (ocn) v.layer.maskedCorners = (CACornerMask)[ocn unsignedIntegerValue];
    if ([ocv isKindOfClass:[NSString class]]) {
        if (@available(iOS 13.0, *)) {
            if ([v.layer respondsToSelector:@selector(setCornerCurve:)]) v.layer.cornerCurve = (NSString *)ocv;
        }
    }
    [CATransaction commit];
    objc_setAssociatedObject(v, kWDOrigRadiusKey, nil, WD_ASSOC);
    objc_setAssociatedObject(v, kWDOrigMaskKey, nil, WD_ASSOC);
    objc_setAssociatedObject(v, kWDOrigCurveKey, nil, WD_ASSOC);
    objc_setAssociatedObject(v, kWDOrigCornersKey, nil, WD_ASSOC);
}

void WDStyleRound(UIView *view, CGFloat radius, BOOL continuous, int tag) {
    if (!view) return;
    CALayer *l = view.layer;
    CGFloat lim = MIN(l.bounds.size.width, l.bounds.size.height) / 2.0;
    CGFloat r = radius;
    if (lim > 0 && r > lim) r = lim;
    if (r < 0) r = 0;
    WDStoreOrig(view);
    objc_setAssociatedObject(view, kWDTagKey, @(tag), WD_ASSOC);
    if (fabs(l.cornerRadius - r) < 0.25 && l.masksToBounds == (r > 0.5)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    l.cornerRadius = r;
    l.masksToBounds = r > 0.5;
    if (continuous) {
        if (@available(iOS 13.0, *)) {
            if ([l respondsToSelector:@selector(setCornerCurve:)]) {
                l.cornerCurve = kCACornerCurveContinuous;
            }
        }
    }
    [CATransaction commit];
}

void WDStyleRoundCorners(UIView *view, CGFloat radius, NSUInteger corners, BOOL continuous, int tag) {
    if (!view) return;
    CALayer *l = view.layer;
    CGFloat lim = MIN(l.bounds.size.width, l.bounds.size.height) / 2.0;
    CGFloat r = radius;
    if (lim > 0 && r > lim) r = lim;
    if (r < 0) r = 0;
    if (corners == 0) r = 0;
    WDStoreOrig(view);
    objc_setAssociatedObject(view, kWDTagKey, @(tag), WD_ASSOC);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    l.cornerRadius = r;
    l.maskedCorners = (CACornerMask)corners;
    l.masksToBounds = (r > 0.5 && corners != 0);
    if (continuous && r > 0.5) {
        if (@available(iOS 13.0, *)) {
            if ([l respondsToSelector:@selector(setCornerCurve:)]) {
                l.cornerCurve = kCACornerCurveContinuous;
            }
        }
    }
    [CATransaction commit];
}

#pragma mark - 单元格

static UIColor *WDGroupedFill(void) {
    if (@available(iOS 13.0, *)) return [UIColor systemGroupedBackgroundColor];
    return [UIColor groupTableViewBackgroundColor];
}

static UIColor *WDCardFill(void) {
    if (@available(iOS 13.0, *)) return [UIColor secondarySystemGroupedBackgroundColor];
    return [UIColor whiteColor];
}

static UIColor *WDResolvedOut(void) {
    if (!gColMaster || !gOutOn) return WDGroupedFill();
    BOOL dark = WDStyleDark();
    UIColor *c = WDHexC(dark ? gOutD : gOutL);
    if (!c && dark) c = WDHexC(gOutL);
    return c ?: WDGroupedFill();
}

static UIColor *WDResolvedIn(void) {
    if (!gColMaster || !gInOn) return WDCardFill();
    BOOL dark = WDStyleDark();
    UIColor *c = WDHexC(dark ? gInD : gInL);
    if (!c && dark) c = WDHexC(gInL);
    return c ?: WDCardFill();
}

BOOL WDStyleShouldSkip(UIView *view) {
    if (!view) return YES;
    const char *selfnm = class_getName(object_getClass(view));
    if (selfnm) {
        if (selfnm[0] == 'W' && selfnm[1] == 'D') return YES;
        if (strstr(selfnm, "MMGrowTextView")) return YES;
        if (strstr(selfnm, "GrowTextView")) return YES;
        if (strstr(selfnm, "MMInputTool")) return YES;
        if (strstr(selfnm, "InputToolContainer")) return YES;
        if (strstr(selfnm, "InputToolView")) return YES;
    }
    UIView *p = view;
    int d = 0;
    while (p && d < 10) {
        const char *nm = class_getName(object_getClass(p));
        if (nm) {
            if (nm[0] == 'W' && nm[1] == 'D') return YES;
            if (strstr(nm, "ContactTag")) return YES;
            if (strstr(nm, "RightTopMenu")) return YES;
            if (strstr(nm, "BarItemCustom")) return YES;
            if (strstr(nm, "MainFrameCustomBar")) return YES;
            if (strstr(nm, "MFTitleView")) return YES;
            if (strstr(nm, "MMBarButton")) return YES;
            if (strstr(nm, "WCPlugins")) return YES;
            if (strstr(nm, "MMGrowTextView") || strstr(nm, "MMInputTool") ||
                strstr(nm, "InputToolContainer")) return YES;
            if (strstr(nm, "NewMainFrame") && selfnm &&
                (strstr(selfnm, "NavigationBar") || strstr(selfnm, "BarBackground") ||
                 strstr(selfnm, "BarContent"))) return YES;
        }
        p = p.superview;
        d++;
    }
    return NO;
}

static BOOL WDTableIsTagList(UITableView *tv) {
    if (!tv) return NO;
    id del = tv.delegate;
    if (del) {
        const char *n = class_getName(object_getClass(del));
        if (n && strstr(n, "ContactTag")) return YES;
    }
    UIView *p = tv;
    int d = 0;
    while (p && d < 12) {
        const char *nm = class_getName(object_getClass(p));
        if (nm && strstr(nm, "ContactTag")) return YES;
        p = p.superview;
        d++;
    }
    return NO;
}

static UIColor *WDGapFillForView(UIView *view) {
    UIColor *want = WDResolvedOut();
    if (gColMaster && gOutOn) return want;
    UIView *sv = view;
    while (sv) {
        if ([sv isKindOfClass:[UITableView class]]) {
            UIColor *c = sv.backgroundColor;
            if (c && ![c isEqual:[UIColor clearColor]]) return c;
            break;
        }
        sv = sv.superview;
    }
    // 深色下 systemGroupedBackground 和首页会话底不是同一色，多设备卡会露灰块。
    if (WDStyleDark()) {
        if (@available(iOS 13.0, *)) return [UIColor systemBackgroundColor];
    }
    return WDGroupedFill();
}

static void WDPaintTableGap(UITableView *tv, UIColor *fill) {
    if (!tv) return;
    if (!objc_getAssociatedObject(tv, kWDTableBgKey)) {
        objc_setAssociatedObject(tv, kWDTableBgKey, tv.backgroundColor ?: (id)[NSNull null], WD_ASSOC);
    }
    tv.separatorColor = [UIColor clearColor];
    tv.separatorStyle = UITableViewCellSeparatorStyleNone;
    // 标了"尾部处理"的表（新的朋友等）：底色同样刷页面色，footer 已在挂载时清过
    if (objc_getAssociatedObject(tv, kWDTailClearKey)) {
        UIColor *page = fill ?: WDGapFillForView(tv) ?: WDGroupedFill();
        tv.backgroundColor = page;
        tv.opaque = YES;
        if (tv.backgroundView) tv.backgroundView.backgroundColor = page;
        return;
    }
    if (!fill) fill = WDGroupedFill();
    tv.backgroundColor = fill;
    tv.opaque = YES;
    if (tv.backgroundView) tv.backgroundView.backgroundColor = fill;
    tv.separatorColor = [UIColor clearColor];
    tv.separatorStyle = UITableViewCellSeparatorStyleNone;
}

static NSInteger WDCachedRows(UITableView *tv, NSInteger section) {
    if (!tv) return 1;
    NSInteger rows = 1;
    @try { rows = [tv numberOfRowsInSection:section]; } @catch (NSException *e) { rows = 1; }
    if (rows < 1) rows = 1;
    for (UITableViewCell *c in tv.visibleCells) {
        NSIndexPath *ip = [tv indexPathForCell:c];
        if (ip && ip.section == section && ip.row + 1 > rows) rows = ip.row + 1;
    }
    return rows;
}

static id WDContactsOwner(UITableView *tv, id del) {
    if (del && [del respondsToSelector:@selector(ConvertToNormalContactSection:)]) return del;
    UIResponder *r = del && [del isKindOfClass:[UIResponder class]] ? (UIResponder *)del : (UIResponder *)tv;
    int d = 0;
    while (r && d < 8) {
        const char *n = class_getName(object_getClass(r));
        if (n && strstr(n, "ContactsViewController") && !strstr(n, "Brand") && !strstr(n, "Tag")) return r;
        r = r.nextResponder;
        d++;
    }
    return nil;
}

static NSInteger WDContactsCategoryEnd(UITableView *tv, id del) {
    if (!tv) return 0;
    id own = WDContactsOwner(tv, del);
    if (!own) return 0;
    del = own;
    NSNumber *hit = objc_getAssociatedObject(tv, kWDCatCacheKey);
    if (hit) return hit.integerValue;
    NSInteger letter = 0;
    @try {
        if ([del respondsToSelector:@selector(ConvertToNormalContactSection:)]) {
            letter = ((NSInteger (*)(id, SEL, NSInteger))objc_msgSend)(del, @selector(ConvertToNormalContactSection:), 0);
        }
    } @catch (NSException *e) { letter = 0; }
    NSInteger end = letter;
    if (end <= 1) {
        NSInteger n = 0;
        @try { n = [tv numberOfSections]; } @catch (NSException *e) { n = 0; }
        if (n > 12) n = 12;
        for (NSInteger i = 0; i < n; i++) {
            NSString *title = nil;
            @try {
                if ([del respondsToSelector:@selector(tableView:titleForHeaderInSection:)]) {
                    title = ((id (*)(id, SEL, id, NSInteger))objc_msgSend)(del, @selector(tableView:titleForHeaderInSection:), tv, i);
                }
            } @catch (NSException *e) { title = nil; }
            if ([title isKindOfClass:[NSString class]] && title.length == 1) { end = i; break; }
        }
    }
    if (end > 1) objc_setAssociatedObject(tv, kWDCatCacheKey, @(end), WD_ASSOC);
    return end;
}

static NSUInteger WDSectionCornersAt(UITableView *tv, NSIndexPath *ip) {
    if (!tv || !ip) return 15;
    if (WDTableIsTagList(tv)) return 15;
    id del = tv.delegate;
    NSInteger catEnd = 0;
    if (del) catEnd = WDContactsCategoryEnd(tv, del);
    if (catEnd > 1 && ip.section >= 0 && ip.section < catEnd) {
        NSInteger lastSec = catEnd - 1;
        NSInteger lastRows = WDCachedRows(tv, lastSec);
        BOOL first = (ip.section == 0 && ip.row == 0);
        BOOL last = (ip.section == lastSec && ip.row == lastRows - 1);
        if (first && last) return 15;
        if (first) return (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner);
        if (last) return (kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner);
        return 0;
    }
    NSInteger rows = WDCachedRows(tv, ip.section);
    if (rows <= 1) return 15;
    if (ip.row == 0) return (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner);
    if (ip.row == rows - 1) return (kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner);
    return 0;
}

static NSUInteger WDSectionCorners(UITableViewCell *cell) {
    UIView *v = cell.superview;
    UITableView *tv = nil;
    while (v) {
        if ([v isKindOfClass:[UITableView class]]) { tv = (UITableView *)v; break; }
        v = v.superview;
    }
    if (!tv) return 15;
    NSIndexPath *ip = [tv indexPathForCell:cell];
    if (!ip) {
        CGPoint p = [cell.superview convertPoint:cell.center toView:tv];
        ip = [tv indexPathForRowAtPoint:p];
    }
    return WDSectionCornersAt(tv, ip);
}

static BOOL WDLooksLikeHairline(UIView *v) {
    if (!v) return NO;
    CGFloat h = v.bounds.size.height;
    CGFloat w = v.bounds.size.width;
    CGFloat scale = [UIScreen mainScreen].scale;
    CGFloat hair = (scale > 0.5) ? (1.0 / scale) : 0.5;
    if (h > 0.2 && h <= hair + 0.75 && w >= 24) return YES;
    if (w > 0.2 && w <= hair + 0.75 && h >= 24) return YES;
    return NO;
}

static void WDHideLineViews(UIView *v, int depth) {
    if (!v || depth > 6) return;
    const char *nm = class_getName(object_getClass(v));
    if (nm && (strstr(nm, "Separator") || strstr(nm, "separator") ||
               strstr(nm, "LineView") || strstr(nm, "lineView") ||
               strstr(nm, "Dash") || strstr(nm, "dash") ||
               strstr(nm, "_UITableViewCellSeparator") ||
               strstr(nm, "bottomLine") || strstr(nm, "BottomLine") ||
               strstr(nm, "topSeparator") || strstr(nm, "bottomSeparator"))) {
        v.hidden = YES;
        v.alpha = 0;
        return;
    }
    if (depth > 0 && WDLooksLikeHairline(v) && ![v isKindOfClass:[UILabel class]] &&
        ![v isKindOfClass:[UIImageView class]] && ![v isKindOfClass:[UIControl class]]) {
        v.hidden = YES;
        v.alpha = 0;
        return;
    }
    if (depth < 5) {
        for (UIView *s in v.subviews) WDHideLineViews(s, depth + 1);
    }
}

static void WDHideNativeSeparators(UITableViewCell *cell) {
    if ([cell respondsToSelector:@selector(setSeparatorInset:)]) {
        CGFloat w = cell.bounds.size.width;
        cell.separatorInset = UIEdgeInsetsMake(0, w, 0, 0);
    }
    WDHideLineViews(cell, 0);
    if (cell.contentView) WDHideLineViews(cell.contentView, 0);
}

// 朋友圈专用：分割线常常是 UIImageView 画的 1px 横条（上面的通用逻辑
// 为保头像把 UIImageView 排除了）。这里只命中「高 ≤2.5 且宽 >30」的
// 细横条 —— 头像/配图都是大图，不会误伤。
static void WDHideMomentsLines(UIView *v, int depth) {
    if (!v || depth > 7) return;
    const char *nm = class_getName(object_getClass(v));
    if (nm && (strstr(nm, "Separator") || strstr(nm, "separator") ||
               strstr(nm, "LineView") || strstr(nm, "lineView") ||
               strstr(nm, "bottomLine") || strstr(nm, "BottomLine"))) {
        v.hidden = YES;
        v.alpha = 0;
        return;
    }
    CGFloat h = v.bounds.size.height, w = v.bounds.size.width;
    if (depth > 0 && h > 0.5 && h <= 2.5 && w > 30 &&
        ![v isKindOfClass:[UILabel class]] && ![v isKindOfClass:[UIControl class]]) {
        v.hidden = YES;
        v.alpha = 0;
        if ([v isKindOfClass:[UIImageView class]]) ((UIImageView *)v).image = nil;
        return;
    }
    for (UIView *s in v.subviews) WDHideMomentsLines(s, depth + 1);
}

// 供 Tweak 的朋友圈详情兜底使用：隐藏 cell 子树里的发丝线/分割线
void WDStyleHideLines(UIView *v) {
    if (!v) return;
    WDHideMomentsLines(v, 0);
    if ([v isKindOfClass:[UITableViewCell class]]) {
        WDHideMomentsLines(((UITableViewCell *)v).contentView, 0);
    }
}

static void WDClearFillViews(UIView *v, int depth) {
    if (!v || depth > 3) return;
    const char *nm = class_getName(object_getClass(v));
    BOOL named = nm && (strstr(nm, "MainFrameItemView") ||
                        strstr(nm, "ContactsItemView") ||
                        strstr(nm, "subContent"));
    if (named) {
        v.backgroundColor = [UIColor clearColor];
        v.opaque = NO;
    }
    if ([v isKindOfClass:[UIImageView class]]) {
        CGRect f = v.frame;
        UIView *p = v.superview;
        // 只清「铺满整行的背景图」。头像（公众号/服务号列表）同样满足
        // "填满父视图"这个条件，之前没有尺寸门槛，把头像一起清成了空白。
        BOOL rowSized = p && p.bounds.size.width > 160 && p.bounds.size.height > 24;
        BOOL selfBig  = f.size.width > 140 && f.size.height > 24;
        if (rowSized && selfBig && f.origin.x < 1 &&
            f.size.width >= p.bounds.size.width - 2 && f.size.height >= p.bounds.size.height - 2) {
            v.backgroundColor = [UIColor clearColor];
            ((UIImageView *)v).image = nil;
            v.opaque = NO;
        }
    }
    if (depth < 2) {
        for (UIView *s in v.subviews) WDClearFillViews(s, depth + 1);
    }
}

static void WDNudgeInner(UIView *v, CGFloat dx) {
    if (!v) return;
    if (fabs(dx) < 0.5) {
        NSValue *orig = objc_getAssociatedObject(v, kWDOrigTFKey);
        if (orig) {
            v.transform = [orig CGAffineTransformValue];
            objc_setAssociatedObject(v, kWDOrigTFKey, nil, WD_ASSOC);
        }
        return;
    }
    NSValue *saved = objc_getAssociatedObject(v, kWDOrigTFKey);
    CGAffineTransform want = CGAffineTransformMakeTranslation(dx, 0);
    if (saved) {
        if (fabs(v.transform.tx - dx) < 0.25) return;
    } else {
        objc_setAssociatedObject(v, kWDOrigTFKey, [NSValue valueWithCGAffineTransform:v.transform], WD_ASSOC);
    }
    if (!CGAffineTransformEqualToTransform(v.transform, want)) v.transform = want;
}

static void WDClearNudge(UIView *v) {
    if (!v) return;
    NSValue *orig = objc_getAssociatedObject(v, kWDOrigTFKey);
    if (!orig) return;
    v.transform = [orig CGAffineTransformValue];
    objc_setAssociatedObject(v, kWDOrigTFKey, nil, WD_ASSOC);
}

static void WDClearNudgeDeep(UIView *v, int depth) {
    if (!v || depth > 6) return;
    WDClearNudge(v);
    for (UIView *s in v.subviews) WDClearNudgeDeep(s, depth + 1);
}

static UIView *WDCellItemView(UITableViewCell *cell) {
    if (!cell) return nil;
    static const char *keys[] = { "m_itemView", "m_contactsItemView", "contactsItemView", NULL };
    for (int i = 0; keys[i]; i++) {
        @try {
            id v = [cell valueForKey:[NSString stringWithUTF8String:keys[i]]];
            if ([v isKindOfClass:[UIView class]] && v != cell && v != cell.contentView) return (UIView *)v;
        } @catch (NSException *e) {}
    }
    NSMutableArray *q = [NSMutableArray array];
    if (cell.contentView) [q addObject:cell.contentView];
    [q addObject:cell];
    int n = 0;
    while (q.count && n < 28) {
        UIView *cur = q.firstObject;
        [q removeObjectAtIndex:0];
        n++;
        const char *nm = class_getName(object_getClass(cur));
        if (nm && (strstr(nm, "MainFrameItemView") || strstr(nm, "ContactsItemView") || strstr(nm, "FakeMainFrame"))) {
            if (cur != cell && cur != cell.contentView) return cur;
        }
        if (cur.subviews.count && n < 22) [q addObjectsFromArray:cur.subviews];
    }
    return nil;
}

static id WDSafeValue(id obj, const char *key) {
    if (!obj || !key) return nil;
    @try { return [obj valueForKey:[NSString stringWithUTF8String:key]]; } @catch (NSException *e) { return nil; }
}

// 引导箭头：名字里带 Arrow/Chevron/Disclosure，或者是靠右的细长小图标（返回键不在 cell 里，不受影响）
static BOOL WDLooksLikeArrow(UIView *v) {
    if (!v) return NO;
    const char *nm = class_getName(object_getClass(v));
    if (nm && (strstr(nm, "Arrow") || strstr(nm, "arrow") ||
               strstr(nm, "Disclosure") || strstr(nm, "disclosure") ||
               strstr(nm, "Chevron") || strstr(nm, "chevron"))) return YES;
    if ([v isKindOfClass:[UIImageView class]]) {
        CGRect f = v.frame;
        UIView *p = v.superview;
        CGFloat pw = p ? p.bounds.size.width : 0;
        if (pw > 60 && f.size.width > 2 && f.size.width <= 14 &&
            f.size.height >= 8 && f.size.height <= 26 && f.origin.x > pw - 40) return YES;
    }
    return NO;
}

static void WDShowArrows(UIView *root) {
    if (!root) return;
    id list = objc_getAssociatedObject(root, kWDArrowHiddenKey);
    if ([list isKindOfClass:[NSArray class]]) {
        for (UIView *v in (NSArray *)list) {
            if ([v isKindOfClass:[UIView class]]) { v.hidden = NO; v.alpha = 1.0; }
        }
    }
    objc_setAssociatedObject(root, kWDArrowHiddenKey, nil, WD_ASSOC);
}

static void WDHideArrows(UIView *v, int depth, NSMutableArray *sink) {
    if (!v || depth > 6) return;
    if (WDLooksLikeArrow(v)) {
        v.hidden = YES;
        v.alpha = 0;
        if (sink && ![sink containsObject:v]) [sink addObject:v];
        return;
    }
    if (depth <= 2) {
        static const char *keys[] = { "arrowImageView", "m_arrowImageView", "arrowView",
                                      "m_arrowView", "m_arrowIconView", "m_accessoryArrowView", NULL };
        for (int i = 0; keys[i]; i++) {
            id a = WDSafeValue(v, keys[i]);
            if ([a isKindOfClass:[UIView class]]) {
                ((UIView *)a).hidden = YES;
                ((UIView *)a).alpha = 0;
                if (sink && ![sink containsObject:a]) [sink addObject:a];
            }
        }
    }
    @try { [v setValue:@NO forKey:@"bShowRightArrow"]; } @catch (NSException *e) {}
    @try { [v setValue:@NO forKey:@"m_bShowRightArrow"]; } @catch (NSException *e) {}
    for (UIView *s in v.subviews) WDHideArrows(s, depth + 1, sink);
}

// 子树里是否是朋友圈动态卡片（WCList*CellView / SNS*），结果缓存在 cell 上
static BOOL WDMomentsScan(UIView *v, int depth) {
    if (!v || depth > 4) return NO;
    const char *nm = class_getName(object_getClass(v));
    if (nm && ((strstr(nm, "WCList") && strstr(nm, "CellView")) || strstr(nm, "SNS"))) return YES;
    for (UIView *s in v.subviews) if (WDMomentsScan(s, depth + 1)) return YES;
    return NO;
}

BOOL WDStyleIsMomentsCell(UITableViewCell *cell) {
    if (!cell) return NO;
    id c = objc_getAssociatedObject(cell, kWDMomentsKey);
    if (c) return [c boolValue];
    // 先看 cell 自己的类名：子树内容可能还没装进来，类名是最稳的信号
    const char *cn = class_getName(object_getClass(cell));
    if (cn && ((strstr(cn, "WCList") && strstr(cn, "CellView")) || strstr(cn, "SNS"))) {
        objc_setAssociatedObject(cell, kWDMomentsKey, @YES, WD_ASSOC);
        return YES;
    }
    // 内容可能还没装进来：命中才缓存，没命中下次布局再查
    if (WDMomentsScan(cell, 0)) {
        objc_setAssociatedObject(cell, kWDMomentsKey, @YES, WD_ASSOC);
        return YES;
    }
    return NO;
}

static BOOL WDIsContactsCategoryCell(UITableViewCell *cell, UITableView *tv, NSIndexPath *ip) {
    if (!cell) return NO;
    if (!tv) {
        UIView *sv = cell.superview;
        while (sv && ![sv isKindOfClass:[UITableView class]]) sv = sv.superview;
        if ([sv isKindOfClass:[UITableView class]]) tv = (UITableView *)sv;
    }
    if (!tv || WDTableIsTagList(tv)) return NO;
    if (!ip) ip = [tv indexPathForCell:cell];
    if (!ip) return NO;
    NSInteger catEnd = WDContactsCategoryEnd(tv, tv.delegate);
    return catEnd > 1 && ip.section >= 0 && ip.section < catEnd;
}

static void WDApplySelected(UITableViewCell *cell, CGFloat inset, CGFloat radius, NSUInteger corners) {
    if (!cell) return;
    CGRect bounds = cell.bounds;
    if (bounds.size.width < 32 || bounds.size.height < 8) return;
    UIView *host = cell.selectedBackgroundView;
    if (!host || !objc_getAssociatedObject(host, kWDSelKey)) {
        host = [[UIView alloc] initWithFrame:bounds];
        host.backgroundColor = [UIColor clearColor];
        host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        UIView *fill = [[UIView alloc] initWithFrame:bounds];
        fill.tag = 0x57445342;
        fill.userInteractionEnabled = NO;
        fill.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host addSubview:fill];
        objc_setAssociatedObject(host, kWDSelKey, @YES, WD_ASSOC);
        cell.selectedBackgroundView = host;
    }
    host.frame = bounds;
    host.backgroundColor = [UIColor clearColor];
    UIView *fill = [host viewWithTag:0x57445342];
    if (!fill) return;
    // 高亮块必须和卡片同一个洞、同一套圆角 —— 否则一点按整行变成方灰色块，
    // 看起来就像"内容错位 / 页面浮起来了"（通讯录五大类和「我」页资料卡都踩过）
    CGFloat inx = MAX(0, inset);
    if (inx > 0 && bounds.size.width <= inx * 2 + 40) inx = 0;
    BOOL moments = WDStyleIsMomentsCell(cell);
    CGFloat vgap = moments ? WD_MOMENTS_VGAP : 0;
    fill.frame = UIEdgeInsetsInsetRect(host.bounds, UIEdgeInsetsMake(vgap, inx, vgap, inx));
    if (fill.frame.size.width < 8 || fill.frame.size.height < 8) fill.frame = host.bounds;
    if (corners != 0 && radius > 0.5) {
        WDStyleRoundCorners(fill, radius, corners, YES, 0);
    } else {
        fill.layer.cornerRadius = 0;
        fill.layer.masksToBounds = NO;
    }
    fill.clipsToBounds = NO;
    if (@available(iOS 13.0, *)) {
        fill.backgroundColor = [UIColor tertiarySystemFillColor];
    } else {
        fill.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.12];
    }
    if (cell.selectionStyle == UITableViewCellSelectionStyleNone) {
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    WDDiagLogOnce([@"sel" stringByAppendingString:NSStringFromClass([cell class])],
                  @"[sel] %@ 高亮块 h=%.0f w=%.0f vgap=%.0f 圆角=%.0f",
                  NSStringFromClass([cell class]), fill.frame.size.height,
                  fill.frame.size.width, vgap,
                  fill.layer.cornerRadius);
}

static BOOL WDInsetByUs(UIView *v) {
    return v && objc_getAssociatedObject(v, kWDOrigFrameKey) != nil;
}

// 把容器左右各收 inx —— 宽度真的变窄，内容跟着缩进，不会像"整体位移"那样把右侧挤出卡片
static void WDFrameInset(UIView *v, CGFloat inx) {
    if (!v) return;
    UIView *p = v.superview;
    if (!p) return;
    if (inx < 1) {
        NSValue *orig = objc_getAssociatedObject(v, kWDOrigFrameKey);
        if (orig) {
            v.frame = [orig CGRectValue];
            objc_setAssociatedObject(v, kWDOrigFrameKey, nil, WD_ASSOC);
        }
        return;
    }
    CGFloat tx, tw;
    if (WDInsetByUs(p)) {           // 父层已经被我们内缩过，子层填满父层即可，避免叠加
        tx = 0;
        tw = p.bounds.size.width;
    } else {
        tx = inx;
        tw = p.bounds.size.width - inx * 2.0;
    }
    if (tw < 40) return;
    CGRect want = CGRectMake(tx, v.frame.origin.y, tw, v.frame.size.height);
    if (fabs(v.frame.origin.x - tx) < 0.5 && fabs(v.frame.size.width - tw) < 0.5) return;
    if (!objc_getAssociatedObject(v, kWDOrigFrameKey)) {
        objc_setAssociatedObject(v, kWDOrigFrameKey, [NSValue valueWithCGRect:v.frame], WD_ASSOC);
    }
    v.frame = want;
}

// 兜底：内部元素若仍超出容器（微信手动布局没跟上新宽度），
// 一律「收窄」而不是「平移」—— 平移只挪超出的那几个，会把一行的相对位置搞错位。
static void WDFitChild(UIView *s, CGFloat w) {
    CGRect f = s.frame;
    CGRect want = f;
    if (want.origin.x < 0) want.origin.x = 0;
    CGFloat over = want.origin.x + want.size.width - w;
    if (over > 1.0) {
        CGFloat nw = want.size.width - over;
        if (nw < 14.0) {
            want.origin.x = MAX(0, w - want.size.width); // 时间标签这类窄元素整体左移
        } else {
            want.size.width = nw;                        // 左对齐元素原地收窄
        }
    }
    if (fabs(want.origin.x - f.origin.x) < 0.5 && fabs(want.size.width - f.size.width) < 0.5) return;
    if (!objc_getAssociatedObject(s, kWDOrigFrameKey)) {
        objc_setAssociatedObject(s, kWDOrigFrameKey, [NSValue valueWithCGRect:f], WD_ASSOC);
    }
    s.frame = want;
}

static void WDClampChildren(UIView *host) {
    if (!host) return;
    CGFloat w = host.bounds.size.width;
    if (w < 40) return;
    for (UIView *s in host.subviews) {
        if (s.hidden || s.alpha < 0.05) continue;
        WDClearNudge(s);   // 清掉旧的位移补偿，避免两种方案叠加
        WDFitChild(s, w);
    }
}

// 还原时把收窄过的子元素也放回去
static void WDRestoreFramesDeep(UIView *v, int depth) {
    if (!v || depth > 4) return;
    NSValue *orig = objc_getAssociatedObject(v, kWDOrigFrameKey);
    if (orig) {
        v.frame = [orig CGRectValue];
        objc_setAssociatedObject(v, kWDOrigFrameKey, nil, WD_ASSOC);
    }
    for (UIView *s in v.subviews) WDRestoreFramesDeep(s, depth + 1);
}

static void WDBalanceInner(UITableViewCell *cell, CGFloat inset) {
    if (!cell) return;
    UIView *cv = cell.contentView ?: cell;
    if (inset < 1) {
        WDFrameInset(cv, 0);
        UIView *it = WDCellItemView(cell);
        if (it && it != cv) WDFrameInset(it, 0);
        WDClearNudgeDeep(cell, 0);
        return;
    }
    WDFrameInset(cv, inset);
    UIView *item = WDCellItemView(cell);
    if (item && item != cv) {
        WDFrameInset(item, inset);
        [item setNeedsLayout];
        @try { [item layoutIfNeeded]; } @catch (NSException *e) {}
        WDClampChildren(item);
    } else {
        [cv setNeedsLayout];
    }
    WDClampChildren(cv);
}

static void WDPlacePlate(UIView *host, CGRect bounds, CGFloat inset, CGFloat radius, NSUInteger corners, BOOL showSep, BOOL punch, BOOL asCellBg, CGFloat vgap) {
    WDCardPlate *plate = objc_getAssociatedObject(host, kWDPlateKey);
    if (![plate isKindOfClass:[WDCardPlate class]]) {
        plate = [[WDCardPlate alloc] initWithFrame:bounds];
        plate.userInteractionEnabled = NO;
        plate.opaque = NO;
        objc_setAssociatedObject(host, kWDPlateKey, plate, WD_ASSOC);
    }
    if (punch) {
        if (asCellBg && [host isKindOfClass:[UITableViewCell class]]) {
            UITableViewCell *cell = (UITableViewCell *)host;
            if (cell.backgroundView == plate) cell.backgroundView = nil;
        }
        if ([host isKindOfClass:[UITableViewCell class]]) {
            UITableViewCell *cell = (UITableViewCell *)host;
            if (plate.superview != host) {
                [host insertSubview:plate aboveSubview:cell.contentView];
            }
        } else {
            if (plate.superview != host) [host addSubview:plate];
            [host bringSubviewToFront:plate];
        }
    } else if (asCellBg && [host isKindOfClass:[UITableViewCell class]]) {
        UITableViewCell *cell = (UITableViewCell *)host;
        if (cell.backgroundView != plate) cell.backgroundView = plate;
    } else if (plate.superview != host) {
        [host insertSubview:plate atIndex:0];
    } else if (host.subviews.firstObject != plate) {
        [host sendSubviewToBack:plate];
    }
    BOOL changed = !CGRectEqualToRect(plate.frame, bounds) ||
                   fabs(plate.radius - radius) > 0.25 ||
                   plate.corners != corners ||
                   fabs(plate.inset - inset) > 0.25 ||
                   plate.punch != punch ||
                   plate.showSep != showSep;
    plate.frame = bounds;
    plate.radius = radius;
    plate.corners = corners;
    plate.inset = inset;
    plate.vInset = vgap;
    plate.punch = punch;
    plate.showSep = showSep;
    if (punch) {
        plate.fill.fillColor = WDGapFillForView(host).CGColor;
    } else {
        plate.fill.fillColor = WDResolvedIn().CGColor;
    }
    if (changed) [plate redraw];
}

void WDStyleView(UIView *view, CGFloat inset, CGFloat radius, BOOL continuous, int tag) {
    if (!view) return;
    if (WDStyleShouldSkip(view)) return;
    if ([view isKindOfClass:[UITableViewCell class]]) {
        WDStyleCell((UITableViewCell *)view, inset, radius, continuous, tag);
        return;
    }
    CGRect bounds = view.bounds;
    if (bounds.size.width < 24 || bounds.size.height < 8) {
        WDStyleRound(view, radius, continuous, tag);
        return;
    }
    CGFloat inx = MAX(0, inset);
    if (inx > 0 && bounds.size.width <= inx * 2 + 24) inx = 0;
    if (inx <= 0.5) {
        WDStyleRound(view, radius, continuous, tag);
        return;
    }

    objc_setAssociatedObject(view, kWDTagKey, @(tag), WD_ASSOC);
    WDRecordStyle(view, WDKindStyleView, inx, radius);
    if (!objc_getAssociatedObject(view, kWDOrigBgColorKey)) {
        UIColor *oc = view.backgroundColor;
        objc_setAssociatedObject(view, kWDOrigBgColorKey, oc ? (id)oc : (id)[NSNull null], WD_ASSOC);
    }
    const char *selfnm = class_getName(object_getClass(view));
    BOOL multi = selfnm && strstr(selfnm, "MultiDevice");
    if (multi) {
        id orig = objc_getAssociatedObject(view, kWDOrigBgColorKey);
        if ([orig isKindOfClass:[UIColor class]]) view.backgroundColor = (UIColor *)orig;
        view.opaque = YES;
    } else {
        view.backgroundColor = [UIColor clearColor];
        view.opaque = NO;
    }
    // 不 clip、不改子视图 frame —— 折叠横幅要点得着。多设备卡只打孔缩进，颜色保持原生。
    WDPlacePlate(view, bounds, inx, radius, 15, NO, YES, NO, 0);
    (void)continuous;
}

// 搜索栏识别放宽：类名带 Search 之外，还认「有 searchBox 属性」的视图，
// 首页/通讯录的搜索栏类名在不同版本里对不上号时也能刷到
BOOL WDStyleIsSearchBarLike(UIView *v) {
    if (!v) return NO;
    const char *nm = class_getName(object_getClass(v));
    if (nm && (strstr(nm, "SearchBar") || strstr(nm, "searchBar") ||
               strstr(nm, "SearchBox") || strstr(nm, "searchBox") ||
               strstr(nm, "SearchPanel") || strstr(nm, "searchField") ||
               strstr(nm, "SearchInput"))) return YES;
    if (WDSafeValue(v, "searchBoxContainer")) return YES;
    if (WDSafeValue(v, "searchBox")) return YES;
    return NO;
}

// 子树里有没有真正的输入框（只看 3 层，够用且快）
static BOOL WDHasTextFieldIn(UIView *v, int depth);
BOOL WDStyleHasTextField(UIView *v) {
    return WDHasTextFieldIn(v, 0);
}

// root 子树里是否包含 target
static BOOL WDSubtreeContains(UIView *root, UIView *target, int depth) {
    if (!root || depth > 6) return NO;
    if (root == target) return YES;
    for (UIView *s in root.subviews) if (WDSubtreeContains(s, target, depth + 1)) return YES;
    return NO;
}

static BOOL WDHasTextFieldIn(UIView *v, int depth) {
    if (!v || depth > 3) return NO;
    if ([v isKindOfClass:[UITextField class]]) return YES;
    if ([v isKindOfClass:[UISearchBar class]]) return YES;
    for (UIView *s in v.subviews) {
        const char *nm = class_getName(object_getClass(s));
        if (nm && nm[0] == 'W' && nm[1] == 'D') continue;
        if (WDHasTextFieldIn(s, depth + 1)) return YES;
    }
    return NO;
}

// 从外壳往下找真正的"那一条"搜索条：高度像输入条，且（像搜索条 或 内含输入框）
static UIView *WDFindSearchBar(UIView *v, int depth) {
    if (!v || depth > 5) return nil;
    for (UIView *s in v.subviews) {
        if (s.hidden || s.alpha < 0.05) continue;
        const char *nm = class_getName(object_getClass(s));
        if (nm && nm[0] == 'W' && nm[1] == 'D') continue;
        CGFloat h = s.bounds.size.height;
        if (h >= 20 && h <= 64 &&
            (WDStyleIsSearchBarLike(s) || WDHasTextFieldIn(s, 0))) return s;
    }
    for (UIView *s in v.subviews) {
        const char *nm = class_getName(object_getClass(s));
        if (nm && nm[0] == 'W' && nm[1] == 'D') continue;
        UIView *r = WDFindSearchBar(s, depth + 1);
        if (r) return r;
    }
    return nil;
}

// 最外层的那个"搜索栏本体"（表头清理时要跳过它和它的子树）
UIView *WDStyleFindSearchRoot(UIView *v) {
    if (!v) return nil;
    if (WDStyleIsSearchBarLike(v) ||
        (v.bounds.size.height <= 96 && WDHasTextFieldIn(v, 0))) return v;
    for (UIView *s in v.subviews) {
        if (s.hidden || s.alpha < 0.05) continue;
        UIView *r = WDStyleFindSearchRoot(s);
        if (r) return r;
    }
    return nil;
}

static UIView *WDSearchInnerBox(UIView *view);
static UIView *WDCapsuleAroundField(UITextField *tf, UIView *bar);
static UIView *WDSearchInnerBox(UIView *view) {
    if (!view) return nil;
    UIView *container = nil;
    static const char *keys[] = { "searchBoxContainer", "searchBox", "m_searchBox",
                                  "m_searchBoxContainer", NULL };
    for (int i = 0; keys[i] && !container; i++) {
        id box = WDSafeValue(view, keys[i]);
        if ([box isKindOfClass:[UIView class]] && box != view) container = (UIView *)box;
    }
    if (container) return container;
    if ([view isKindOfClass:[UISearchBar class]]) {
        @try {
            id tf = nil;
            if ([view respondsToSelector:@selector(getTextField)]) {
                tf = ((id (*)(id, SEL))objc_msgSend)(view, @selector(getTextField));
            }
            if (![tf isKindOfClass:[UIView class]]) tf = [view valueForKey:@"searchField"];
            if ([tf isKindOfClass:[UIView class]]) return (UIView *)tf;
        } @catch (NSException *e) {}
    }
    // 宽搜：在所有"内含输入框"的候选里挑最像输入条的那个 ——
    // 优先高度 ≤48 的（真正的一行输入条），再取最矮的。
    // 以前按"面积最小"挑会挑到整块 60~70pt 高的白底容器，整条搜索栏就变成了巨型胶囊。
    NSMutableArray *q = [NSMutableArray arrayWithArray:view.subviews];
    UIView *best = nil;
    CGFloat bestScore = CGFLOAT_MAX;
    int n = 0;
    while (q.count && n < 30) {
        UIView *cur = q.firstObject;
        [q removeObjectAtIndex:0];
        n++;
        const char *nm = class_getName(object_getClass(cur));
        if (nm && nm[0] == 'W' && nm[1] == 'D') continue;
        if ([cur isKindOfClass:[UITextField class]]) {
            return WDCapsuleAroundField((UITextField *)cur, view);
        }
        if (cur != view && WDHasTextFieldIn(cur, 0)) {
            CGFloat h = cur.bounds.size.height;
            CGFloat score = (h > 0 && h <= 48 ? h : 1000 + h);
            if (score < bestScore) { bestScore = score; best = cur; }
        }
        if (cur.subviews.count && n < 24) [q addObjectsFromArray:cur.subviews];
    }
    return best;
}

// 从输入框往上找"真正画了底"的那层胶囊：
// 条件 = 高度 ≤48 且有自己的背景色；遇到高度 >48 的容器就停（那是搜索栏的外壳，不是胶囊）
static UIView *WDCapsuleAroundField(UITextField *tf, UIView *bar) {
    UIView *best = nil;
    UIView *cur = tf;
    for (int i = 0; i < 5 && cur; i++) {
        UIView *p = cur.superview;
        if (!p || p == bar || p == tf) break;
        CGFloat h = p.bounds.size.height;
        if (h > 48) break;
        UIColor *bg = p.backgroundColor;
        BOOL painted = bg && ![bg isEqual:[UIColor clearColor]] && CGColorGetAlpha(bg.CGColor) > 0.05;
        if (painted || !best) best = p;   // 画了底的取更高一层（整颗胶囊）；都没画底时取最近的
        cur = p;
    }
    return best ?: tf;
}

// 摘掉可能残留的底板：搜索栏只要一层外观，底板 + 内层胶囊就是"双层搜索栏"
static void WDDetachPlate(UIView *v) {
    if (!v) return;
    id plate = objc_getAssociatedObject(v, kWDPlateKey);
    if ([plate isKindOfClass:[UIView class]]) {
        [(UIView *)plate removeFromSuperview];
        objc_setAssociatedObject(v, kWDPlateKey, nil, WD_ASSOC);
    }
}

// 缩进优先"把整条搜索栏收窄"，而不是去挪里面的胶囊：
// 收窄外层后微信自己的布局会把胶囊和文字一起带上，不会出现错位，也不会被自动布局打回原形。
static void WDSearchNarrow(UIView *bar, CGFloat inx) {
    if (!bar || inx < 0.5) return;
    UIView *p = bar.superview;
    if (!p) return;
    // 表格会强制子视图宽度，这种挪不动，交给胶囊兜底；
    // 表头容器（UITableViewHeaderFooterView）可以收，里面的子视图微信不会强制复位
    if ([p isKindOfClass:[UITableView class]]) return;
    if (p.bounds.size.width < bar.bounds.size.width + inx * 2.0 - 1.0) return;
    CGFloat w = p.bounds.size.width;
    CGRect want = CGRectMake(inx, bar.frame.origin.y, MAX(40, w - inx * 2.0), bar.frame.size.height);
    if (fabs(bar.frame.origin.x - want.origin.x) < 0.5 &&
        fabs(bar.frame.size.width - want.size.width) < 0.5) return;
    if (!objc_getAssociatedObject(bar, kWDOrigFrameKey)) {
        objc_setAssociatedObject(bar, kWDOrigFrameKey, [NSValue valueWithCGRect:bar.frame], WD_ASSOC);
    }
    bar.frame = want;
}

// 兜底：整条挪不动时再收窄胶囊（原地收窄，不做整体平移）
static void WDSearchNarrowBox(UIView *box, UIView *bar, CGFloat inx) {
    if (!box || !bar || inx < 0.5) return;
    CGFloat full = bar.bounds.size.width;
    if (full < 40) return;
    CGRect want = CGRectMake(inx, box.frame.origin.y, MAX(40, full - inx * 2.0), box.frame.size.height);
    if (fabs(box.frame.origin.x - want.origin.x) < 0.5 &&
        fabs(box.frame.size.width - want.size.width) < 0.5) return;
    if (!objc_getAssociatedObject(box, kWDOrigFrameKey)) {
        objc_setAssociatedObject(box, kWDOrigFrameKey, [NSValue valueWithCGRect:box.frame], WD_ASSOC);
    }
    box.frame = want;
}

static void WDClearMiddleLayers(UIView *root, UIView *capsule, NSMutableArray *sink);
static void WDClearPaintedBg(UIView *v);

void WDStyleSearch(UIView *view, CGFloat inset, CGFloat radius, BOOL continuous, int tag) {
    if (!view) return;
    if (WDStyleShouldSkip(view)) return;
    CGRect bounds = view.bounds;
    if (bounds.size.width < 24 || bounds.size.height < 8) return;

    CGFloat inx = MAX(0, inset);
    if (inx > 0 && bounds.size.width <= inx * 2 + 40) inx = 0;

    BOOL looksBar = WDStyleIsSearchBarLike(view) || WDHasTextFieldIn(view, 0);
    // 高度不像"那一条" → 这是外壳，往下找真正的搜索条
    if (!(looksBar && bounds.size.height <= 64.0)) {
        UIView *bar = WDFindSearchBar(view, 0);
        if (bar) {
            WDDiagLogOnce([@"descend" stringByAppendingString:NSStringFromClass([view class])],
                          @"[search] 外壳 %@ h=%.0f → 内条 %@ h=%.0f",
                          NSStringFromClass([view class]), view.bounds.size.height,
                          NSStringFromClass([bar class]), bar.bounds.size.height);
            WDStyleSearch(bar, inset, radius, continuous, tag);
            return;
        }
        // 整棵子树都没有输入框，说明根本不是搜索栏，不要乱刷
        if (!WDHasTextFieldIn(view, 0) || bounds.size.height > 96.0) return;
    }

    objc_setAssociatedObject(view, kWDTagKey, @(tag), WD_ASSOC);
    WDRecordStyle(view, WDKindStyleSearch, inx, radius);
    WDRequestRelayoutHook(object_getClass(view));

    // ★ 胶囊还没布局（h<20，首帧常见）时一步都不动：
    //   这里任何清理/上色都会把搜索栏留成一条全宽白带，而它之后可能
    //   再也不走 layout，就永远停在那个状态。样式已记录（上面），
    //   布局后由重贴钩子原样重跑 WDStyleSearch，那时胶囊高度是真实的。
    {
        UIView *c0 = WDSearchInnerBox(view);
        if (c0 && c0 != view && c0.bounds.size.height < 20.0) {
            WDDiagLogOnce([@"searchnotready" stringByAppendingString:NSStringFromClass([view class])],
                          @"[search] %@ 胶囊 %@ 未布局 h=%.0f → 本轮不动，布局后重刷",
                          NSStringFromClass([view class]), NSStringFromClass([c0 class]),
                          c0.bounds.size.height);
            return;
        }
    }

    NSMutableArray *sink = objc_getAssociatedObject(view, kWDClearedViewsKey);
    if (![sink isKindOfClass:[NSMutableArray class]]) sink = [NSMutableArray array];
    if (!objc_getAssociatedObject(view, kWDOrigBgColorKey)) {
        UIColor *oc = view.backgroundColor;
        objc_setAssociatedObject(view, kWDOrigBgColorKey, oc ? (id)oc : (id)[NSNull null], WD_ASSOC);
    }
    view.backgroundColor = [UIColor clearColor];
    view.opaque = NO;
    view.clipsToBounds = NO;
    WDClearPaintedBg(view);   // 条本身若带白色背景图（UIButton 常见），一并清掉
    @try {
        id line = [view valueForKey:@"bottomLineView"];
        if ([line isKindOfClass:[UIView class]]) {
            ((UIView *)line).hidden = YES;
            ((UIView *)line).alpha = 0;
        }
    } @catch (NSException *e) {}

    // 逐层剥外壳：选中"胶囊"后如果它还高于 60pt，说明拿到的仍是外壳不是输入条，
    // 清掉它的底再往里找一层 —— 保证最后画圆角的永远是真正的那条输入条
    UIView *capsule = nil;
    UIView *scope = view;
    for (int tries = 0; tries < 3; tries++) {
        capsule = WDSearchInnerBox(scope);
        if (!capsule || capsule == view) break;
        if (capsule.bounds.size.height <= 60.0) break;
        WDDiagLogOnce([@"shell" stringByAppendingString:NSStringFromClass([capsule class])],
                      @"[search] 外壳过高被剥掉: %@ h=%.0f w=%.0f",
                      NSStringFromClass([capsule class]), capsule.bounds.size.height, capsule.bounds.size.width);
        if (!objc_getAssociatedObject(capsule, kWDOrigBgColorKey)) {
            UIColor *bg = capsule.backgroundColor;
            objc_setAssociatedObject(capsule, kWDOrigBgColorKey, bg ? (id)bg : (id)[NSNull null], WD_ASSOC);
        }
        if (![sink containsObject:capsule]) [sink addObject:capsule];
        WDClearPaintedBg(capsule);
        scope = capsule;
        capsule = nil;
    }
    objc_setAssociatedObject(view, kWDClearedViewsKey, sink, WD_ASSOC);
    WDDiagLogOnce([@"searchbar" stringByAppendingString:NSStringFromClass([view class])],
                  @"[search] 条=%@ h=%.0f 胶囊=%@ h=%.0f 清壳=%lu",
                  NSStringFromClass([view class]), view.bounds.size.height,
                  capsule ? NSStringFromClass([capsule class]) : @"(无)",
                  capsule ? capsule.bounds.size.height : 0,
                  (unsigned long)sink.count);

    if (capsule && capsule != view) {
        // 只留一层：搜索栏本体透明，圆角给胶囊。再挂底板就成了"双层搜索栏"
        WDDetachPlate(view);
        CGFloat w0 = capsule.frame.size.width;
        WDSearchNarrow(view, inx);
        if (fabs(capsule.frame.size.width - w0) < 0.5) WDSearchNarrowBox(capsule, view, inx);
        CGFloat ch = capsule.bounds.size.height;
        // 全圆（半径=高/2）只对真正的输入条用；再高的容器全圆就变成巨型胶囊了
        CGFloat br = (ch > 0 && ch <= 48) ? MIN(radius, ch / 2.0) : MIN(radius, 18.0);
        WDStyleRound(capsule, br, continuous, tag);
        // 胶囊用卡片内色：外壳/表头已被清透明（露出页面灰底），
        // 白色圆角胶囊贴在灰底上 = 原生的「缩进 + 圆角」观感
        UIColor *capC = WDResolvedIn() ?: ({
            UIColor *c;
            if (@available(iOS 13.0, *)) c = [UIColor tertiarySystemFillColor];
            else c = [UIColor colorWithWhite:0.93 alpha:1.0];
            c;
        });
        capsule.backgroundColor = capC;
        @try { [view setValue:capC forKey:@"searchBoxContainerColor"]; } @catch (NSException *e) {}
        // 胶囊外面如果还套着画了底的容器（60~70pt 高的白条），一并清掉，
        // 否则就是截图里那种"巨型白色胶囊"
        WDClearMiddleLayers(view, capsule, sink);
        WDRequestRelayoutHook(object_getClass(capsule));
        return;
    }
    // 没有内层：它自己就是那一条，收窄后补一张圆角卡
    WDSearchNarrow(view, inx);
    WDPlacePlate(view, view.bounds, 0, radius, 15, NO, NO, NO, 0);
    CGFloat sh = view.bounds.size.height;
    WDStyleRound(view, (sh > 0 && sh <= 48) ? MIN(radius, sh / 2.0) : MIN(radius, 18.0), continuous, tag);
}

// 胶囊到搜索栏外壳之间凡是"画了底"的中间层都清透明（记录以便还原）。
// 白底不一定来自 backgroundColor —— 很常见是 UIButton 的白色背景图，
// 只清颜色的话那条"大搜索栏"依然全宽白带（v1.1.22 截图实锤）。
static void WDClearPaintedBg(UIView *v) {
    if (!v) return;
    UIColor *bg = v.backgroundColor;
    if (bg && ![bg isEqual:[UIColor clearColor]] && CGColorGetAlpha(bg.CGColor) > 0.05) {
        if (!objc_getAssociatedObject(v, kWDOrigBgColorKey)) {
            objc_setAssociatedObject(v, kWDOrigBgColorKey, bg, WD_ASSOC);
        }
        v.backgroundColor = [UIColor clearColor];
        v.opaque = NO;
    }
    if ([v isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)v;
        for (UIControlState st = UIControlStateNormal;
             st <= UIControlStateSelected; st++) {
            UIImage *img = [btn backgroundImageForState:st];
            if (img) {
                [btn setBackgroundImage:nil forState:st];
            }
        }
        [btn setBackgroundColor:[UIColor clearColor]];
    }
    if (v.layer) {
        CGColorRef lbg = v.layer.backgroundColor;
        if (lbg && CGColorGetAlpha(lbg) > 0.05) v.layer.backgroundColor = [UIColor clearColor].CGColor;
    }
}

static void WDClearMiddleLayers(UIView *root, UIView *capsule, NSMutableArray *sink) {
    if (!root || root == capsule || !sink) return;
    for (UIView *s in root.subviews) {
        if (!WDSubtreeContains(s, capsule, 0)) continue;
        if (s != capsule && s.bounds.size.height > 48) {
            if (!objc_getAssociatedObject(s, kWDOrigBgColorKey)) {
                UIColor *bg = s.backgroundColor;
                objc_setAssociatedObject(s, kWDOrigBgColorKey, bg ? (id)bg : (id)[NSNull null], WD_ASSOC);
            }
            if (![sink containsObject:s]) [sink addObject:s];
            WDClearPaintedBg(s);
        }
        WDClearMiddleLayers(s, capsule, sink);
    }
}

static void WDClearFillsDeep(UIView *v, int depth) {
    if (!v || depth > 8) return;
    const char *nm = class_getName(object_getClass(v));
    if (nm && strstr(nm, "WDCardPlate")) return;
    if (![v isKindOfClass:[UILabel class]] && ![v isKindOfClass:[UIImageView class]]) {
        v.backgroundColor = [UIColor clearColor];
        v.opaque = NO;
        if (v.layer) {
            v.layer.backgroundColor = [UIColor clearColor].CGColor;
            v.layer.shadowOpacity = 0;
            v.layer.shadowRadius = 0;
            v.layer.borderWidth = 0;
        }
    }
    if ([v isKindOfClass:[UIVisualEffectView class]]) {
        ((UIVisualEffectView *)v).effect = nil;
        v.backgroundColor = [UIColor clearColor];
        v.opaque = NO;
        v.hidden = YES;
    }
    if ([v isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)v;
        [btn setBackgroundImage:nil forState:UIControlStateNormal];
        [btn setBackgroundImage:nil forState:UIControlStateHighlighted];
        [btn setBackgroundImage:nil forState:UIControlStateSelected];
        btn.backgroundColor = [UIColor clearColor];
        btn.opaque = NO;
        if (btn.layer) {
            btn.layer.backgroundColor = [UIColor clearColor].CGColor;
            btn.layer.shadowOpacity = 0;
            btn.layer.cornerRadius = 0;
            btn.layer.masksToBounds = NO;
        }
    }
    if ([v isKindOfClass:[UIImageView class]]) {
        UIImageView *iv = (UIImageView *)v;
        UIView *p = v.superview;
        CGRect f = v.frame;
        BOOL bleed = !p || (f.origin.x < 4 && f.size.width >= p.bounds.size.width - 8);
        if (bleed) {
            iv.image = nil;
            iv.highlightedImage = nil;
            iv.backgroundColor = [UIColor clearColor];
            iv.opaque = NO;
            iv.layer.backgroundColor = [UIColor clearColor].CGColor;
            iv.layer.cornerRadius = 0;
            iv.layer.masksToBounds = NO;
        }
    }
    for (UIView *s in v.subviews) WDClearFillsDeep(s, depth + 1);
}

void WDStyleFold(UIView *view, CGFloat inset, CGFloat radius, BOOL continuous, int tag) {
    if (!view) return;
    CGRect bounds = view.bounds;
    if (bounds.size.width < 24 || bounds.size.height < 8) return;
    objc_setAssociatedObject(view, kWDTagKey, @(tag), WD_ASSOC);
    (void)inset; (void)radius;
    if (!objc_getAssociatedObject(view, kWDOrigBgColorKey)) {
        UIColor *oc = view.backgroundColor;
        objc_setAssociatedObject(view, kWDOrigBgColorKey, oc ? (id)oc : (id)[NSNull null], WD_ASSOC);
    }
    view.clipsToBounds = NO;
    view.layer.masksToBounds = NO;
    view.backgroundColor = [UIColor clearColor];
    view.opaque = NO;
    if (view.layer) {
        view.layer.backgroundColor = [UIColor clearColor].CGColor;
        view.layer.cornerRadius = 0;
        view.layer.shadowOpacity = 0;
    }
    WDClearFillsDeep(view, 0);
    static const char *keys[] = {
        "bannerBtn", "foldBtn", "bkgView", "backgroundView", "contentView",
        "m_bkgView", "m_backgroundView", "topSessionFoldView", NULL
    };
    for (int i = 0; keys[i]; i++) {
        @try {
            id btn = [view valueForKey:[NSString stringWithUTF8String:keys[i]]];
            if ([btn isKindOfClass:[UIView class]]) WDClearFillsDeep((UIView *)btn, 0);
        } @catch (NSException *e) {}
    }
    @try {
        id top = [view valueForKey:@"topSeparatorView"];
        if ([top isKindOfClass:[UIView class]]) { ((UIView *)top).hidden = YES; ((UIView *)top).alpha = 0; }
    } @catch (NSException *e) {}
    @try {
        id bot = [view valueForKey:@"bottomSeparatorView"];
        if ([bot isKindOfClass:[UIView class]]) { ((UIView *)bot).hidden = YES; ((UIView *)bot).alpha = 0; }
    } @catch (NSException *e) {}
    WDHideLineViews(view, 0);
    WDCardPlate *plate = objc_getAssociatedObject(view, kWDPlateKey);
    if ([plate isKindOfClass:[UIView class]]) {
        [plate removeFromSuperview];
        objc_setAssociatedObject(view, kWDPlateKey, nil, WD_ASSOC);
    }
    (void)continuous;
}

void WDStyleProfile(UIView *view, CGFloat inset, CGFloat radius, BOOL continuous, int tag) {
    if (!view) return;
    if ([view isKindOfClass:[UITableView class]] || [view isKindOfClass:[UICollectionView class]]) return;
    CGRect bounds = view.bounds;
    if (bounds.size.width < 40 || bounds.size.height < 24) return;
    objc_setAssociatedObject(view, kWDTagKey, @(tag), WD_ASSOC);
    CGFloat inx = MAX(0, inset);
    if (inx > 0 && bounds.size.width <= inx * 2 + 40) inx = 0;
    WDRecordStyle(view, WDKindStyleProfile, inx, radius);
    // 资料卡被微信按压时刷回白底：布局后自动重贴，不用等"进出一次页面"
    WDRequestRelayoutHook(object_getClass(view));
    if (!objc_getAssociatedObject(view, kWDOrigBgColorKey)) {
        UIColor *oc = view.backgroundColor;
        objc_setAssociatedObject(view, kWDOrigBgColorKey, oc ? (id)oc : (id)[NSNull null], WD_ASSOC);
    }
    view.opaque = NO;
    view.backgroundColor = [UIColor clearColor];
    view.clipsToBounds = NO;
    view.layer.masksToBounds = NO;
    @try {
        id bg = [view valueForKey:@"backgroundView"];
        if ([bg isKindOfClass:[UIView class]]) {
            UIView *bv = (UIView *)bg;
            bv.backgroundColor = [UIColor clearColor];
            bv.opaque = NO;
            bv.clipsToBounds = NO;
        }
    } @catch (NSException *e) {}
    @try {
        id sep = [view valueForKey:@"topSeparator"];
        if ([sep isKindOfClass:[UIView class]]) { ((UIView *)sep).hidden = YES; ((UIView *)sep).alpha = 0; }
    } @catch (NSException *e) {}
    WDHideLineViews(view, 0);
    WDPlacePlate(view, bounds, inx, radius, 15, NO, YES, NO, 0);
    // 资料卡和顶栏剥离开：顶部留一条缝，让四个圆角都露出来
    CGFloat topGap = 10.0;
    CGRect hole = UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(0, inx, 0, inx));
    if (bounds.size.height > topGap * 2.0 + 40.0) {
        hole = UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(topGap, inx, 0, inx));
    }
    CGFloat rad = MIN(radius, MIN(hole.size.width, hole.size.height) / 2.0);
    UIView *fill = objc_getAssociatedObject(view, kWDProfileFillKey);
    if (![fill isKindOfClass:[UIView class]]) {
        fill = [[UIView alloc] initWithFrame:hole];
        fill.userInteractionEnabled = NO;
        objc_setAssociatedObject(view, kWDProfileFillKey, fill, WD_ASSOC);
        [view insertSubview:fill atIndex:0];
    }
    fill.frame = hole;
    fill.backgroundColor = WDResolvedIn();
    fill.layer.cornerRadius = rad;
    fill.layer.masksToBounds = YES;
    fill.clipsToBounds = YES;
    // 盖在圆角卡上面的整块白色容器会让圆角看不见（"我"页顶栏下方就是这样），统一清透明
    for (UIView *s in view.subviews) {
        if (s == fill || s == (UIView *)objc_getAssociatedObject(view, kWDPlateKey)) continue;
        if ([s isKindOfClass:[UILabel class]] || [s isKindOfClass:[UIControl class]]) continue;
        if (s.bounds.size.width >= view.bounds.size.width * 0.9 &&
            s.bounds.size.height >= view.bounds.size.height * 0.6) {
            s.backgroundColor = [UIColor clearColor];
            s.opaque = NO;
            if ([s isKindOfClass:[UIImageView class]]) ((UIImageView *)s).image = nil;
        }
    }
    if (continuous) {
        if (@available(iOS 13.0, *)) {
            if ([fill.layer respondsToSelector:@selector(setCornerCurve:)]) {
                fill.layer.cornerCurve = kCACornerCurveContinuous;
            }
        }
    }
    WDCardPlate *plate = objc_getAssociatedObject(view, kWDPlateKey);
    if ([plate isKindOfClass:[UIView class]]) [view bringSubviewToFront:plate];
}

static UIView *WDMeProfileHost(UIViewController *vc) {
    if (!vc || !vc.isViewLoaded) return nil;
    UIView *header = nil;
    @try {
        id tv = [vc valueForKey:@"frontTableView"];
        if ([tv isKindOfClass:[UITableView class]]) {
            UIView *th = ((UITableView *)tv).tableHeaderView;
            WDDiagLogOnce([@"mehdr" stringByAppendingString:NSStringFromClass([vc class])],
                          @"[me] %@ frontTableView=%@ 表头=%@ h=%.0f",
                          NSStringFromClass([vc class]),
                          tv ? NSStringFromClass([tv class]) : @"(无)",
                          th ? NSStringFromClass([th class]) : @"(无)",
                          th ? th.bounds.size.height : 0);
            if (th && th.bounds.size.width >= 160 &&
                th.bounds.size.height >= 64 && th.bounds.size.height <= 360) {
                const char *hn = class_getName(object_getClass(th));
                if (!(hn && (strstr(hn, "SearchBar") || strstr(hn, "SearchPanel")))) header = th;
            }
        }
    } @catch (NSException *e) {}
    if (header) {
        WDDiagLogOnce([@"mehost" stringByAppendingString:NSStringFromClass([header class])],
                      @"[me] 资料卡宿主(表头)=%@ h=%.0f", NSStringFromClass([header class]), header.bounds.size.height);
        return header;
    }
    UIView *headHost = nil;
    @try {
        id head = [vc valueForKey:@"headImage"];
        WDDiagLogOnce([@"mehead" stringByAppendingString:NSStringFromClass([vc class])],
                      @"[me] headImage=%@", head ? NSStringFromClass([head class]) : @"(无)");
        if ([head isKindOfClass:[UIView class]]) {
            UIView *p = ((UIView *)head).superview;
            int u = 0;
            while (p && u < 6) {
                if (p == vc.view) break;
                if ([p isKindOfClass:[UITableView class]] || [p isKindOfClass:[UITableViewCell class]]) break;
                CGFloat h = p.bounds.size.height;
                CGFloat w = p.bounds.size.width;
                if (w >= 160 && h >= 64 && h <= 360) headHost = p;
                p = p.superview;
                u++;
            }
        }
    } @catch (NSException *e) {}
    if (headHost) return headHost;
    @try {
        id d = [vc valueForKey:@"textStateDetailView"];
        if ([d isKindOfClass:[UIView class]]) {
            UIView *dv = (UIView *)d;
            if (dv.bounds.size.height >= 24 && dv.bounds.size.height <= 360) return dv;
        }
    } @catch (NSException *e) {}
    return nil;
}

void WDStyleMePage(UIViewController *vc, CGFloat inset, CGFloat radius, BOOL continuous, int tag) {
    if (!vc || !vc.isViewLoaded) return;
    UIView *host = WDMeProfileHost(vc);
    WDDiagLogOnce([@"mepage" stringByAppendingString:NSStringFromClass([vc class])],
                  @"[me] WDStyleMePage %@ 宿主=%@", NSStringFromClass([vc class]),
                  host ? NSStringFromClass([host class]) : @"(没找到)");
    if (host) WDStyleProfile(host, inset, radius, continuous, tag);
    @try {
        id d = [vc valueForKey:@"textStateDetailView"];
        if ([d isKindOfClass:[UIView class]] && (UIView *)d != host) {
            UIView *dv = (UIView *)d;
            UIView *p = dv.superview;
            BOOL nested = NO;
            int u = 0;
            while (p && u < 8) {
                if (p == host) { nested = YES; break; }
                p = p.superview;
                u++;
            }
            if (!nested) WDStyleProfile(dv, inset, radius, continuous, tag);
        }
    } @catch (NSException *e) {}
}

static void WDClearHeaderRecur(UIView *v, int depth, UIView *keep) {
    if (!v || depth > 5) return;
    if (v == keep) return;   // 搜索栏子树不碰（胶囊底色会被它清掉）
    v.backgroundColor = [UIColor clearColor];
    v.opaque = NO;
    const char *nm = class_getName(object_getClass(v));
    if ([v isKindOfClass:[UIImageView class]] || (nm && strstr(nm, "Background"))) {
        // 同上：小尺寸的头像素材不清空，只清整幅背景图
        CGRect f = v.frame;
        if ([v isKindOfClass:[UIImageView class]] && f.size.width > 120 && f.size.height > 24) {
            ((UIImageView *)v).image = nil;
        }
    }
    if (nm && (strstr(nm, "Separator") || strstr(nm, "LineView") || strstr(nm, "lineView") || strstr(nm, "Dash"))) {
        v.hidden = YES;
        v.alpha = 0;
        return;
    }
    if (depth > 0 && WDLooksLikeHairline(v) && ![v isKindOfClass:[UILabel class]] &&
        ![v isKindOfClass:[UIControl class]]) {
        v.hidden = YES;
        v.alpha = 0;
        return;
    }
    for (UIView *s in v.subviews) WDClearHeaderRecur(s, depth + 1, keep);
}

void WDStyleClearHeader(UIView *view) {
    WDStyleClearHeaderExcept(view, nil);
}

// keep = 搜索栏根：表头里带搜索栏时，清表头但保留搜索栏子树
void WDStyleClearHeaderExcept(UIView *view, UIView *keep) {
    if (!view) return;
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UITableViewHeaderFooterView *hf = (UITableViewHeaderFooterView *)view;
        hf.contentView.backgroundColor = [UIColor clearColor];
        hf.backgroundView = [[UIView alloc] init];
        hf.backgroundView.backgroundColor = [UIColor clearColor];
        hf.tintColor = [UIColor clearColor];
    }
    WDClearHeaderRecur(view, 0, keep);
    UIView *p = view.superview;
    int u = 0;
    while (p && u < 5) {
        if ([p isKindOfClass:[UITableView class]] || [p isKindOfClass:[UICollectionView class]] ||
            [p isKindOfClass:[UIWindow class]]) break;
        const char *pn = class_getName(object_getClass(p));
        if (pn && (strstr(pn, "NavigationBar") || strstr(pn, "TabBar"))) break;
        p.backgroundColor = [UIColor clearColor];
        p.opaque = NO;
        if ([p isKindOfClass:[UIImageView class]]) ((UIImageView *)p).image = nil;
        if ([p isKindOfClass:[UIVisualEffectView class]]) ((UIVisualEffectView *)p).effect = nil;
        p = p.superview;
        u++;
    }
}

void WDStyleHostCard(UIView *host, CGFloat inset, CGFloat radius, BOOL continuous, int tag) {
    if (!host) return;
    if ([host isKindOfClass:[UITableViewCell class]]) {
        WDStyleCell((UITableViewCell *)host, inset, radius, continuous, tag);
        return;
    }
    CGRect bounds = host.bounds;
    if (bounds.size.width < 40 || bounds.size.height < 24) return;
    CGFloat inx = MAX(0, inset);
    if (inx > 0 && bounds.size.width <= inx * 2 + 40) inx = 0;
    objc_setAssociatedObject(host, kWDTagKey, @(tag), WD_ASSOC);
    if (!objc_getAssociatedObject(host, kWDOrigBgColorKey)) {
        UIColor *oc = host.backgroundColor;
        objc_setAssociatedObject(host, kWDOrigBgColorKey, oc ? (id)oc : (id)[NSNull null], WD_ASSOC);
    }
    host.backgroundColor = WDResolvedIn();
    host.opaque = YES;
    host.clipsToBounds = NO;
    WDPlacePlate(host, bounds, inx, radius, 15, NO, YES, NO, 0);
    (void)continuous;
}

void WDStyleCellAt(UITableViewCell *cell, UITableView *tv, NSIndexPath *ip, CGFloat inset, CGFloat radius, BOOL continuous, int tag) {
    if (!cell) return;
    if (WDStyleShouldSkip(cell)) return;
    CGRect bounds = cell.bounds;
    if (bounds.size.width < 32 || bounds.size.height < 8) return;

    objc_setAssociatedObject(cell, kWDTagKey, @(tag), WD_ASSOC);

    CGFloat inx = MAX(0, inset);
    if (inx > 0 && bounds.size.width <= inx * 2 + 40) inx = 0;
    WDRecordStyle(cell, WDKindStyleCell, inx, radius);
    if (!tv) {
        UIView *sv = cell.superview;
        while (sv && ![sv isKindOfClass:[UITableView class]]) sv = sv.superview;
        if ([sv isKindOfClass:[UITableView class]]) tv = (UITableView *)sv;
    }
    if (tv && WDTableIsTagList(tv)) return;
    NSUInteger corners = ip ? WDSectionCornersAt(tv, ip) : WDSectionCorners(cell);
    if (bounds.size.width < 24) return;

    if (tv) WDPaintTableGap(tv, WDGapFillForView(tv));

    if (!objc_getAssociatedObject(cell, kWDOrigBgKey)) {
        UIView *orig = cell.backgroundView;
        objc_setAssociatedObject(cell, kWDOrigBgKey, orig ? (id)orig : (id)[NSNull null], WD_ASSOC);
        UIColor *oc = cell.backgroundColor;
        objc_setAssociatedObject(cell, kWDOrigBgColorKey, oc ? (id)oc : (id)[NSNull null], WD_ASSOC);
    }

    BOOL showSep = (corners == 0) || ((corners & (kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner)) == 0);
    // 朋友圈：每条动态一张独立卡 —— 四角全圆、上下留缝（分隔线也就自然没了）
    BOOL moments = WDStyleIsMomentsCell(cell);
    if (moments) {
        corners = 15;
        showSep = NO;
    }
    CGFloat vgap = moments ? WD_MOMENTS_VGAP : 0;
    WDPlacePlate(cell, bounds, inx, radius, corners, showSep, YES, NO, vgap);
    if (moments) WDHideMomentsLines(cell, 0);

    UIColor *inC = WDResolvedIn();
    cell.backgroundColor = inC;
    cell.opaque = YES;
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.clipsToBounds = NO;
    if (corners != 0 && radius > 0.5) {
        WDStyleRoundCorners(cell, radius, corners, continuous, tag);
        cell.layer.masksToBounds = YES;
    } else {
        WDRevertRound(cell);
        cell.layer.masksToBounds = NO;
    }
    if ([cell respondsToSelector:@selector(setBkgColor:)]) {
        @try { [cell setValue:inC forKey:@"bkgColor"]; } @catch (NSException *e) {}
    }
    WDHideNativeSeparators(cell);
    WDClearFillViews(cell, 0);
    WDClearFillViews(cell.contentView, 0);
    BOOL catRow = WDIsContactsCategoryCell(cell, tv, ip);
    WDDiagLogOnce([@"cellat" stringByAppendingString:NSStringFromClass([cell class])],
                  @"[cellAt] %@ sec=%ld row=%ld corners=%lu moments=%d inx=%.0f r=%.0f",
                  NSStringFromClass([cell class]),
                  (long)(ip ? ip.section : -1), (long)(ip ? ip.row : -1),
                  (unsigned long)corners, moments ? 1 : 0, inx, radius);
    // 引导箭头：所有卡片行都隐藏（导航栏返回键不在 cell 内，不受影响）
    NSMutableArray *sink = [NSMutableArray array];
    WDHideArrows(cell, 0, sink);
    if (cell.accessoryType == UITableViewCellAccessoryDisclosureIndicator) {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    if (cell.accessoryView) {
        cell.accessoryView.hidden = YES;
        cell.accessoryView.alpha = 0;
        if (![sink containsObject:cell.accessoryView]) [sink addObject:cell.accessoryView];
    }
    if (sink.count) {
        NSMutableArray *all = objc_getAssociatedObject(cell, kWDArrowHiddenKey);
        if ([all isKindOfClass:[NSMutableArray class]]) {
            for (UIView *v in sink) if (![all containsObject:v]) [all addObject:v];
            objc_setAssociatedObject(cell, kWDArrowHiddenKey, all, WD_ASSOC);
        } else {
            objc_setAssociatedObject(cell, kWDArrowHiddenKey, sink, WD_ASSOC);
        }
    }
    if (catRow) WDClearNudgeDeep(cell, 0);
    // 五个大类（新的朋友/群聊/标签/公众号/服务号）也要内容缩进：
    // 旧的"位移补偿"会挤歪它们所以曾经跳过，现在改成收窄容器宽度，可以统一处理
    WDBalanceInner(cell, inx);
    WDApplySelected(cell, inx, radius, corners);
    (void)continuous;
}

void WDStyleCell(UITableViewCell *cell, CGFloat inset, CGFloat radius, BOOL continuous, int tag) {
    WDStyleCellAt(cell, nil, nil, inset, radius, continuous, tag);
}

#pragma mark - 设置页单元格

void WDStyleSettingsCell(UITableViewCell *cell, CGFloat inset, CGFloat radius, NSUInteger corners, BOOL continuous) {
    if (!cell) return;
    CGRect bounds = cell.bounds;
    if (bounds.size.width < 32 || bounds.size.height < 8) return;

    CGFloat inx = MAX(0, inset);
    if (inx > 0 && bounds.size.width <= inx * 2 + 40) inx = 0;
    CGRect plateF = UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(0, inx, 0, inx));

    if (!objc_getAssociatedObject(cell, kWDOrigBgKey)) {
        UIView *orig = cell.backgroundView;
        objc_setAssociatedObject(cell, kWDOrigBgKey, orig ? (id)orig : (id)[NSNull null], WD_ASSOC);
        UIColor *oc = cell.backgroundColor;
        objc_setAssociatedObject(cell, kWDOrigBgColorKey, oc ? (id)oc : (id)[NSNull null], WD_ASSOC);
    }

    WDCardPlate *plate = objc_getAssociatedObject(cell, kWDPlateKey);
    if (![plate isKindOfClass:[WDCardPlate class]]) {
        plate = [[WDCardPlate alloc] initWithFrame:plateF];
        objc_setAssociatedObject(cell, kWDPlateKey, plate, WD_ASSOC);
        cell.backgroundView = plate;
        cell.backgroundColor = [UIColor clearColor];
    }
    BOOL changed = (fabs(plate.radius - radius) > 0.25) || (plate.corners != corners);
    plate.radius = radius;
    plate.corners = corners;
    plate.inset = 0;
    plate.punch = NO;
    plate.showSep = NO;
    plate.fill.fillColor = WDResolvedIn().CGColor;
    if (!CGRectEqualToRect(plate.frame, plateF)) plate.frame = plateF;
    if (changed) [plate redraw];
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];
    (void)continuous;
}

#pragma mark - 还原

int WDStyleTagOf(UIView *view) {
    if (!view) return -1;
    id v = objc_getAssociatedObject(view, kWDTagKey);
    if ([v respondsToSelector:@selector(intValue)]) return [v intValue];
    return -1;
}

void WDStyleRevertView(UIView *view) {
    if (!view) return;
    NSValue *of = objc_getAssociatedObject(view, kWDOrigFrameKey);
    if (of) {
        view.frame = [of CGRectValue];
        objc_setAssociatedObject(view, kWDOrigFrameKey, nil, WD_ASSOC);
    }
    WDShowArrows(view);
    if ([view isKindOfClass:[UITableViewCell class]]) {
        UITableViewCell *cell = (UITableViewCell *)view;
        id plate = objc_getAssociatedObject(cell, kWDPlateKey);
        if (plate) {
            if (cell.backgroundView == plate) {
                id orig = objc_getAssociatedObject(cell, kWDOrigBgKey);
                cell.backgroundView = [orig isKindOfClass:[UIView class]] ? (UIView *)orig : nil;
            }
            if ([plate isKindOfClass:[UIView class]]) [(UIView *)plate removeFromSuperview];
            objc_setAssociatedObject(cell, kWDPlateKey, nil, WD_ASSOC);
        }
        id obc = objc_getAssociatedObject(cell, kWDOrigBgColorKey);
        if (obc) {
            cell.backgroundColor = [obc isKindOfClass:[UIColor class]] ? (UIColor *)obc : nil;
            objc_setAssociatedObject(cell, kWDOrigBgColorKey, nil, WD_ASSOC);
        }
        objc_setAssociatedObject(cell, kWDOrigBgKey, nil, WD_ASSOC);
        // 还原内容容器内缩与隐藏掉的箭头
        WDFrameInset(cell.contentView ?: cell, 0);
        UIView *it = WDCellItemView(cell);
        if (it && it != cell.contentView) WDFrameInset(it, 0);
        WDRestoreFramesDeep(cell, 0);
        WDShowArrows(cell);
        WDClearNudgeDeep(cell, 0);
        WDRevertRound(cell.contentView);
        cell.contentView.layer.cornerRadius = 0;
        cell.contentView.layer.masksToBounds = NO;
        UIView *sv = cell.superview;
        while (sv && ![sv isKindOfClass:[UITableView class]]) sv = sv.superview;
        if ([sv isKindOfClass:[UITableView class]]) {
            id ob = objc_getAssociatedObject(sv, kWDTableBgKey);
            if (ob) {
                sv.backgroundColor = [ob isKindOfClass:[UIColor class]] ? (UIColor *)ob : nil;
                objc_setAssociatedObject(sv, kWDTableBgKey, nil, WD_ASSOC);
            }
        }
    } else {
        id plate = objc_getAssociatedObject(view, kWDPlateKey);
        if ([plate isKindOfClass:[UIView class]]) {
            [(UIView *)plate removeFromSuperview];
            objc_setAssociatedObject(view, kWDPlateKey, nil, WD_ASSOC);
        }
        UIView *pfill = objc_getAssociatedObject(view, kWDProfileFillKey);
        if ([pfill isKindOfClass:[UIView class]]) {
            [pfill removeFromSuperview];
            objc_setAssociatedObject(view, kWDProfileFillKey, nil, WD_ASSOC);
        }
        // 搜索栏沿途清掉的白底容器，一个个放回去
        NSArray *cleared = objc_getAssociatedObject(view, kWDClearedViewsKey);
        for (UIView *cv in cleared) {
            if (![cv isKindOfClass:[UIView class]]) continue;
            id obc = objc_getAssociatedObject(cv, kWDOrigBgColorKey);
            cv.backgroundColor = [obc isKindOfClass:[UIColor class]] ? (UIColor *)obc : nil;
            objc_setAssociatedObject(cv, kWDOrigBgColorKey, nil, WD_ASSOC);
        }
        objc_setAssociatedObject(view, kWDClearedViewsKey, nil, WD_ASSOC);
        UIView *box = WDSearchInnerBox(view);
        if (box) {
            NSValue *bf = objc_getAssociatedObject(box, kWDOrigFrameKey);            if (bf) {
                box.frame = [bf CGRectValue];
                objc_setAssociatedObject(box, kWDOrigFrameKey, nil, WD_ASSOC);
            }
            WDRevertRound(box);
        }
        id obc = objc_getAssociatedObject(view, kWDOrigBgColorKey);
        if (obc) {
            view.backgroundColor = [obc isKindOfClass:[UIColor class]] ? (UIColor *)obc : nil;
            objc_setAssociatedObject(view, kWDOrigBgColorKey, nil, WD_ASSOC);
        }
        UIView *sv = view.superview;
        while (sv && ![sv isKindOfClass:[UITableView class]] && ![sv isKindOfClass:[UIScrollView class]]) {
            sv = sv.superview;
        }
        if (sv) {
            id ob = objc_getAssociatedObject(sv, kWDTableBgKey);
            if (ob) {
                sv.backgroundColor = [ob isKindOfClass:[UIColor class]] ? (UIColor *)ob : nil;
                objc_setAssociatedObject(sv, kWDTableBgKey, nil, WD_ASSOC);
            }
        }
    }
    WDRevertRound(view);
    objc_setAssociatedObject(view, kWDTagKey, nil, WD_ASSOC);
}

#pragma mark - 重贴（系统重新布局后把样式贴回去）

static BOOL WDRelayoutBusy(UIView *v) {
    return [objc_getAssociatedObject(v, kWDStyleBusyKey) boolValue];
}

// 侧滑操作条：微信把操作按钮（标为未读/不显示/删除/备注）原生存到
// cell 右缘（= 屏幕边），卡片内缩后按钮会冲出卡片右边界。
// 兼容两种结构：按钮条自己是右缘子视图；或全宽容器里按钮位于右半区。
static void WDClampSwipeStrips(UITableViewCell *cell, CGFloat inx) {
    if (!cell || inx < 1) return;
    CGFloat w = cell.bounds.size.width, h = cell.bounds.size.height;
    if (w < 100 || h < 30) return;
    CGFloat limit = w - inx;
    NSArray *scopes = [cell.subviews arrayByAddingObjectsFromArray:cell.contentView.subviews];
    for (UIView *s in scopes) {
        if (s.hidden) continue;
        if (s.superview != cell && s.superview != cell.contentView) continue;
        const char *nm = class_getName(object_getClass(s));
        if (nm && nm[0] == 'W' && nm[1] == 'D') continue;
        CGRect f = s.frame;
        if (f.size.height < h - 10 || f.size.width < 40) continue;
        // 主内容容器（origin≈0 且铺满整行）不钳
        if (f.origin.x < 2 && f.size.width >= w - 2) continue;
        CGFloat maxX = f.origin.x + f.size.width;
        if (maxX <= limit + 0.5) continue;
        CGFloat oldMax = maxX;
        f.origin.x -= (maxX - limit);
        s.frame = f;
        WDDiagLogOnce([@"swipe" stringByAppendingString:NSStringFromClass([s class])],
                      @"[swipe] %@ (cell=%@) 操作条右缘 %.0f → %.0f",
                      NSStringFromClass([s class]), NSStringFromClass([cell class]),
                      oldMax, f.origin.x + f.size.width);
        // 按钮若是彩色图/底，顺带给条左缘圆角观感（不裁内容）
    }
}

// 卡片行：只重贴底板与内容内缩，不走完整流程（列表滚动时 layoutSubviews 很频繁）
void WDStyleCellRelayout(UITableViewCell *cell) {
    if (!cell) return;
    if (WDRelayoutBusy(cell)) return;
    NSNumber *n = objc_getAssociatedObject(cell, kWDStyleInsetKey);
    if (!n || WDStyleTagOf(cell) < 0) return;
    if ([objc_getAssociatedObject(cell, kWDStyleKindKey) intValue] != WDKindStyleCell) return;
    objc_setAssociatedObject(cell, kWDStyleBusyKey, @YES, WD_ASSOC);
    @try {
        CGRect b = cell.bounds;
        if (b.size.width >= 32 && b.size.height >= 8) {
            CGFloat inx = [n doubleValue];
            CGFloat rad = [(NSNumber *)objc_getAssociatedObject(cell, kWDStyleRadiusKey) doubleValue];
            BOOL moments = WDStyleIsMomentsCell(cell);
            NSUInteger corners = moments ? 15 : WDSectionCorners(cell);
            BOOL showSep = moments ? NO :
                           ((corners == 0) ||
                            ((corners & (kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner)) == 0));
            CGFloat vgap = moments ? WD_MOMENTS_VGAP : 0;
            WDPlacePlate(cell, b, inx, rad, corners, showSep, YES, NO, vgap);
            WDBalanceInner(cell, inx);
            WDClampSwipeStrips(cell, inx);
            if (moments) WDHideMomentsLines(cell, 0);
        }
    } @catch (NSException *e) {}
    objc_setAssociatedObject(cell, kWDStyleBusyKey, nil, WD_ASSOC);
}

// 搜索栏 / 资料卡等：系统布局把它们打回原形后原样重贴
void WDStyleRelayoutView(UIView *v) {
    if (!v) return;
    if (WDRelayoutBusy(v)) return;
    NSNumber *k = objc_getAssociatedObject(v, kWDStyleKindKey);
    if (!k) return;
    int tag = WDStyleTagOf(v);
    if (tag < 0) return;
    CGFloat inx = [(NSNumber *)objc_getAssociatedObject(v, kWDStyleInsetKey) doubleValue];
    CGFloat rad = [(NSNumber *)objc_getAssociatedObject(v, kWDStyleRadiusKey) doubleValue];
    objc_setAssociatedObject(v, kWDStyleBusyKey, @YES, WD_ASSOC);
    @try {
        switch ([k intValue]) {
            case WDKindStyleSearch:  WDStyleSearch(v, inx, rad, gStyleCont, tag); break;
            case WDKindStyleProfile: WDStyleProfile(v, inx, rad, gStyleCont, tag); break;
            case WDKindStyleView:    WDStyleView(v, inx, rad, gStyleCont, tag); break;
            default: break;
        }
    } @catch (NSException *e) {}
    objc_setAssociatedObject(v, kWDStyleBusyKey, nil, WD_ASSOC);
}

#pragma mark - 页面尾部留白透明（新的朋友等）

static UITableView *WDFindTableIn(UIView *v, int depth) {
    if (!v || depth > 5) return nil;
    if ([v isKindOfClass:[UITableView class]]) return (UITableView *)v;
    for (UIView *s in v.subviews) {
        if ([s isKindOfClass:[UITableView class]]) return (UITableView *)s;
    }
    for (UIView *s in v.subviews) {
        UITableView *t = WDFindTableIn(s, depth + 1);
        if (t) return t;
    }
    return nil;
}

void WDStyleClearTableTail(UIView *root) {
    UITableView *tv = WDFindTableIn(root, 0);
    if (!tv) return;
    // 用页面底色而不是全透明：上一版清成透明会露出黑色的 window，页面直接变黑
    UIColor *page = WDGapFillForView(tv) ?: WDResolvedOut();
    if (!objc_getAssociatedObject(tv, kWDTableBgKey)) {
        objc_setAssociatedObject(tv, kWDTableBgKey, tv.backgroundColor ?: (id)[NSNull null], WD_ASSOC);
    }
    objc_setAssociatedObject(tv, kWDTailClearKey, @YES, WD_ASSOC);
    tv.backgroundColor = page;
    tv.opaque = YES;
    if (tv.backgroundView) {
        tv.backgroundView.backgroundColor = page;
        tv.backgroundView.opaque = NO;
        tv.backgroundView.hidden = NO;
    }
    tv.separatorColor = [UIColor clearColor];
    tv.separatorStyle = UITableViewCellSeparatorStyleNone;
    if (tv.tableFooterView) WDStyleClearHeader(tv.tableFooterView);
    // 表格底下若还有一层白色容器（内容短时露出一大片），同样刷成页面底色
    UIView *p = tv.superview;
    int d = 0;
    while (p && d < 4) {
        if ([p isKindOfClass:[UIWindow class]]) break;
        const char *pn = class_getName(object_getClass(p));
        if (pn && (strstr(pn, "NavigationBar") || strstr(pn, "TabBar"))) break;
        p.backgroundColor = page;
        p.opaque = YES;
        p = p.superview;
        d++;
    }
}

#pragma mark - 重排

static void WDInvalidateRecur(UIView *v, int depth) {
    if (!v || depth > 12) return;
    const char *nm = class_getName(object_getClass(v));
    if (nm && nm[0] == 'W' && nm[1] == 'D') return;
    [v setNeedsLayout];
    for (UIView *s in v.subviews) WDInvalidateRecur(s, depth + 1);
}

void WDStyleInvalidate(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return;
    for (UIWindow *w in app.windows) WDInvalidateRecur(w, 0);
}
