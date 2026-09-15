#import "WDStyle.h"
#import "WDPrefs.h"
#import <string.h>
#import <stdio.h>

static const void *kWDPlateKey       = &kWDPlateKey;
static const void *kWDTagKey         = &kWDTagKey;
static const void *kWDOrigRadiusKey  = &kWDOrigRadiusKey;
static const void *kWDOrigMaskKey    = &kWDOrigMaskKey;
static const void *kWDOrigCurveKey   = &kWDOrigCurveKey;
static const void *kWDOrigCornersKey = &kWDOrigCornersKey;
static const void *kWDOrigBgKey      = &kWDOrigBgKey;
static const void *kWDOrigBgColorKey = &kWDOrigBgColorKey;
static const void *kWDInsetKey       = &kWDInsetKey;
static const void *kWDTableBgKey     = &kWDTableBgKey;
static const void *kWDOrigTFKey      = &kWDOrigTFKey;
static const void *kWDRowsCacheKey   = &kWDRowsCacheKey;
static const void *kWDCatCacheKey    = &kWDCatCacheKey;
static const void *kWDSelKey         = &kWDSelKey;
static const void *kWDSearchBoxFrameKey = &kWDSearchBoxFrameKey;
static const void *kWDProfileFillKey = &kWDProfileFillKey;
static const void *kWDOrigFrameKey    = &kWDOrigFrameKey;
static const void *kWDArrowHiddenKey  = &kWDArrowHiddenKey;
static const void *kWDTailClearKey    = &kWDTailClearKey;

static BOOL gColMaster = YES;
static BOOL gInOn = NO;
static BOOL gOutOn = NO;
static char gInL[16];
static char gInD[16];
static char gOutL[16];
static char gOutD[16];

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

#define WD_ASSOC OBJC_ASSOCIATION_RETAIN_NONATOMIC

@interface WDCardPlate : UIView
@property (nonatomic, strong) CAShapeLayer *fill;
@property (nonatomic, strong) CAShapeLayer *sep;
@property (nonatomic, assign) CGFloat radius;
@property (nonatomic, assign) NSUInteger corners;
@property (nonatomic, assign) CGFloat inset;
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
    CGRect hole = UIEdgeInsetsInsetRect(r, UIEdgeInsetsMake(0, inx, 0, inx));
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
    // 标了"尾部透明"的表（新的朋友等）不刷底色，否则每次 cell 布局都会把留白涂回去
    if (objc_getAssociatedObject(tv, kWDTailClearKey)) {
        tv.backgroundColor = [UIColor clearColor];
        tv.opaque = NO;
        if (tv.backgroundView) {
            tv.backgroundView.backgroundColor = [UIColor clearColor];
            tv.backgroundView.hidden = YES;
        }
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

static void WDNudgeKey(UIView *host, const char *key, CGFloat dx) {
    if (!host || !key) return;
    @try {
        id v = [host valueForKey:[NSString stringWithUTF8String:key]];
        if ([v isKindOfClass:[UIView class]]) WDNudgeInner((UIView *)v, dx);
    } @catch (NSException *e) {}
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
    (void)inset; (void)radius; (void)corners;
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
    fill.frame = host.bounds;
    fill.layer.cornerRadius = 0;
    fill.layer.masksToBounds = NO;
    fill.clipsToBounds = NO;
    if (@available(iOS 13.0, *)) {
        fill.backgroundColor = [UIColor tertiarySystemFillColor];
    } else {
        fill.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.12];
    }
    if (cell.selectionStyle == UITableViewCellSelectionStyleNone) {
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
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

// 兜底：内部元素若仍超出容器（微信手动布局没跟上新宽度），把它拉回卡片内
static void WDClampChildren(UIView *host) {
    if (!host) return;
    CGFloat w = host.bounds.size.width;
    if (w < 40) return;
    for (UIView *s in host.subviews) {
        if (s.hidden || s.alpha < 0.05) continue;
        CGRect f = s.frame;
        CGFloat over = CGRectGetMaxX(f) - w;
        if (over > 1.0) WDNudgeInner(s, -over);
        else if (f.origin.x < -1.0) WDNudgeInner(s, -f.origin.x);
        else WDClearNudge(s);
    }
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

static void WDPlacePlate(UIView *host, CGRect bounds, CGFloat inset, CGFloat radius, NSUInteger corners, BOOL showSep, BOOL punch, BOOL asCellBg) {
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
    WDPlacePlate(view, bounds, inx, radius, 15, NO, YES, NO);
    (void)continuous;
}

static UIView *WDSearchInnerBox(UIView *view) {
    if (!view) return nil;
    UIView *container = nil;
    static const char *keys[] = { "searchBoxContainer", "searchBox", "m_searchBox",
                                  "m_searchBoxContainer", "searchTextField", "m_textField", NULL };
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
        for (UIView *sub in view.subviews) {
            if ([sub isKindOfClass:[UITextField class]]) return sub;
            for (UIView *c in sub.subviews) {
                if ([c isKindOfClass:[UITextField class]]) return c;
            }
        }
    }
    for (UIView *sub in view.subviews) {
        const char *nm = class_getName(object_getClass(sub));
        if (nm && (strstr(nm, "SearchBox") || strstr(nm, "searchBox") || strstr(nm, "SearchText"))) return sub;
    }
    // 兜底：找到真正的输入框，取它的容器（外层胶囊）而不是输入框本身
    NSMutableArray *q = [NSMutableArray arrayWithArray:view.subviews];
    int n = 0;
    while (q.count && n < 24) {
        UIView *cur = q.firstObject;
        [q removeObjectAtIndex:0];
        n++;
        if ([cur isKindOfClass:[UITextField class]]) {
            UIView *p = cur.superview;
            if (p && p != view && p.bounds.size.height <= 52 && p.bounds.size.width > view.bounds.size.width * 0.5) return p;
            return cur;
        }
        if (cur.subviews.count && n < 20) [q addObjectsFromArray:cur.subviews];
    }
    return nil;
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

static void WDSetSearchSpacer(UIView *bar, const char *key, CGFloat width) {
    if (!bar || !key) return;
    @try {
        id sp = [bar valueForKey:[NSString stringWithUTF8String:key]];
        if (![sp isKindOfClass:[UIView class]]) return;
        UIView *spacer = (UIView *)sp;
        NSLayoutConstraint *w = nil;
        for (NSLayoutConstraint *c in spacer.constraints) {
            if (c.firstAttribute == NSLayoutAttributeWidth && c.secondItem == nil) { w = c; break; }
        }
        if (w) {
            if (fabs(w.constant - width) > 0.5) w.constant = width;
        } else {
            NSLayoutConstraint *nw = [spacer.widthAnchor constraintEqualToConstant:width];
            nw.priority = UILayoutPriorityRequired - 1;
            nw.active = YES;
        }
    } @catch (NSException *e) {}
}

static void WDApplySearchStackInset(UIView *bar, CGFloat inx) {
    if (!bar) return;
    UIStackView *root = nil;
    @try {
        id r = [bar valueForKey:@"rootStackView"];
        if ([r isKindOfClass:[UIStackView class]]) root = (UIStackView *)r;
    } @catch (NSException *e) {}
    if (root) {
        root.insetsLayoutMarginsFromSafeArea = NO;
        root.layoutMarginsRelativeArrangement = YES;
        UIEdgeInsets cur = root.layoutMargins;
        if (fabs(cur.left - inx) > 0.5 || fabs(cur.right - inx) > 0.5) {
            root.layoutMargins = UIEdgeInsetsMake(cur.top, inx, cur.bottom, inx);
        }
        return;
    }
    WDSetSearchSpacer(bar, "leftBoxSpacer", inx);
    WDSetSearchSpacer(bar, "rightBoxSpacer", inx);
}

static BOOL WDSearchIsWrapper(UIView *view) {
    if (!view) return YES;
    const char *nm = class_getName(object_getClass(view));
    if (nm && (strstr(nm, "SearchPanel") || strstr(nm, "SearchBarContainer") ||
               strstr(nm, "ContactsSearch") || strstr(nm, "NewContactsSearch"))) return YES;
    if (view.bounds.size.height > 56) return YES;
    return NO;
}

static void WDStyleSearchInnerOnly(UIView *view, CGFloat inset, CGFloat radius, BOOL continuous, int tag, int depth) {
    if (!view || depth > 5) return;
    const char *nm = class_getName(object_getClass(view));
    BOOL bar = nm && (strstr(nm, "WCSearchBar") || strstr(nm, "MMUISearchBar") ||
                      strstr(nm, "FavSearchBar") || strstr(nm, "WAMainFrameTaskBarSearchBar"));
    if (bar && view.bounds.size.height <= 56) {
        WDStyleSearch(view, inset, radius, continuous, tag);
        return;
    }
    for (UIView *s in view.subviews) WDStyleSearchInnerOnly(s, inset, radius, continuous, tag, depth + 1);
}

void WDStyleSearch(UIView *view, CGFloat inset, CGFloat radius, BOOL continuous, int tag) {
    if (!view) return;
    if (WDStyleShouldSkip(view)) return;
    CGRect bounds = view.bounds;
    if (bounds.size.width < 24 || bounds.size.height < 8) return;
    if (WDSearchIsWrapper(view)) {
        const char *selfnm = class_getName(object_getClass(view));
        BOOL selfIsBar = selfnm && (strstr(selfnm, "WCSearchBar") || strstr(selfnm, "MMUISearchBar") ||
                                    strstr(selfnm, "FavSearchBar") || strstr(selfnm, "WAMainFrameTaskBarSearchBar"));
        if (!selfIsBar || bounds.size.height > 56) {
            WDStyleSearchInnerOnly(view, inset, radius, continuous, tag, 0);
            return;
        }
    }
    objc_setAssociatedObject(view, kWDTagKey, @(tag), WD_ASSOC);
    CGFloat inx = MAX(0, inset);
    if (inx > 0 && bounds.size.width <= inx * 2 + 40) inx = 0;
    if (!objc_getAssociatedObject(view, kWDOrigBgColorKey)) {
        UIColor *oc = view.backgroundColor;
        objc_setAssociatedObject(view, kWDOrigBgColorKey, oc ? (id)oc : (id)[NSNull null], WD_ASSOC);
    }
    view.backgroundColor = [UIColor clearColor];
    view.opaque = NO;
    view.clipsToBounds = NO;
    @try {
        id line = [view valueForKey:@"bottomLineView"];
        if ([line isKindOfClass:[UIView class]]) {
            ((UIView *)line).hidden = YES;
            ((UIView *)line).alpha = 0;
        }
    } @catch (NSException *e) {}
    if (inx > 0.5) WDApplySearchStackInset(view, inx);

    UIView *capsule = nil;
    @try {
        id c = [view valueForKey:@"searchBoxContainer"];
        if ([c isKindOfClass:[UIView class]]) capsule = (UIView *)c;
    } @catch (NSException *e) {}
    if (!capsule) {
        @try {
            id box = [view valueForKey:@"searchBox"];
            if ([box isKindOfClass:[UIView class]]) capsule = (UIView *)box;
        } @catch (NSException *e) {}
    }
    if (!capsule) capsule = WDSearchInnerBox(view);
    if (capsule && capsule != view) {
        // 只有一层：搜索栏本体透明，圆角与缩进都给内部输入框（外层再挂底板就会变"双层搜索栏"）
        WDDetachPlate(view);
        if (inx > 0.5) {
            UIView *p = capsule.superview ?: view;
            CGFloat full = p.bounds.size.width;
            // 自动布局那套（stack/spacer）没生效时才直接改 frame
            if (full > 40 && capsule.bounds.size.width > full - inx * 1.2) {
                if (!objc_getAssociatedObject(capsule, kWDOrigFrameKey)) {
                    objc_setAssociatedObject(capsule, kWDOrigFrameKey,
                                             [NSValue valueWithCGRect:capsule.frame], WD_ASSOC);
                }
                CGFloat h = capsule.frame.size.height;
                CGFloat y = capsule.frame.origin.y;
                CGRect want = CGRectMake(inx, y, MAX(40, full - inx * 2.0), h);
                if (fabs(capsule.frame.origin.x - want.origin.x) > 0.5 ||
                    fabs(capsule.frame.size.width - want.size.width) > 0.5) {
                    capsule.frame = want;
                }
            }
        }
        CGFloat br = MIN(radius, capsule.bounds.size.height > 1 ? capsule.bounds.size.height / 2.0 : radius);
        WDStyleRound(capsule, br, continuous, tag);
        if (gColMaster && gInOn) {
            UIColor *inC = WDResolvedIn();
            if (inC) capsule.backgroundColor = inC;
        }
        if (gColMaster && gInOn) {
            @try { [view setValue:WDResolvedIn() forKey:@"searchBoxContainerColor"]; } @catch (NSException *e) {}
        }
        return;
    }
    if (![view isKindOfClass:[UISearchBar class]]) {
        const char *selfnm = class_getName(object_getClass(view));
        BOOL selfIsBar = selfnm && (strstr(selfnm, "WCSearchBar") || strstr(selfnm, "MMUISearchBar"));
        if (!selfIsBar) {
            for (UIView *s in view.subviews) {
                const char *sn = class_getName(object_getClass(s));
                if (sn && (strstr(sn, "WCSearchBar") || strstr(sn, "MMUISearchBar") ||
                           strstr(sn, "SearchBar") || strstr(sn, "searchBox"))) {
                    WDStyleSearch(s, inset, radius, continuous, tag);
                    return;
                }
            }
        }
    }
    if ([view isKindOfClass:[UISearchBar class]]) {
        UIView *tf = WDSearchInnerBox(view);
        if (tf && tf != view) {
            // 同样只保留一层：圆角 + 缩进都落在输入框上，不再额外挂底板
            WDDetachPlate(view);
            if (inx > 0.5) {
                if (!objc_getAssociatedObject(tf, kWDOrigFrameKey)) {
                    objc_setAssociatedObject(tf, kWDOrigFrameKey, [NSValue valueWithCGRect:tf.frame], WD_ASSOC);
                }
                CGRect want = CGRectMake(inx, tf.frame.origin.y,
                                         MAX(40, bounds.size.width - inx * 2.0), tf.frame.size.height);
                if (fabs(tf.frame.origin.x - want.origin.x) > 0.5 ||
                    fabs(tf.frame.size.width - want.size.width) > 0.5) {
                    tf.frame = want;
                }
            }
            CGFloat br = MIN(radius, tf.bounds.size.height > 1 ? tf.bounds.size.height / 2.0 : radius);
            WDStyleRound(tf, br, continuous, tag);
            return;
        }
        if (inx > 0.5) WDPlacePlate(view, bounds, inx, radius, 15, NO, YES, NO);
        return;
    }
    if (inx > 0.5) WDPlacePlate(view, bounds, inx, radius, 15, NO, YES, NO);
    else WDStyleRound(view, MIN(radius, view.bounds.size.height / 2.0), continuous, tag);
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
    WDPlacePlate(view, bounds, inx, radius, 15, NO, YES, NO);
    CGRect hole = UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(0, inx, 0, inx));
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
            if (th && th.bounds.size.width >= 160 &&
                th.bounds.size.height >= 64 && th.bounds.size.height <= 360) {
                const char *hn = class_getName(object_getClass(th));
                if (!(hn && (strstr(hn, "SearchBar") || strstr(hn, "SearchPanel")))) header = th;
            }
        }
    } @catch (NSException *e) {}
    if (header) return header;
    UIView *headHost = nil;
    @try {
        id head = [vc valueForKey:@"headImage"];
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

static void WDClearHeaderRecur(UIView *v, int depth) {
    if (!v || depth > 5) return;
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
    for (UIView *s in v.subviews) WDClearHeaderRecur(s, depth + 1);
}

void WDStyleClearHeader(UIView *view) {
    if (!view) return;
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UITableViewHeaderFooterView *hf = (UITableViewHeaderFooterView *)view;
        hf.contentView.backgroundColor = [UIColor clearColor];
        hf.backgroundView = [[UIView alloc] init];
        hf.backgroundView.backgroundColor = [UIColor clearColor];
        hf.tintColor = [UIColor clearColor];
    }
    if ([view isKindOfClass:[UILabel class]]) {
        ((UILabel *)view).backgroundColor = [UIColor clearColor];
        view.opaque = NO;
    }
    if ([view isKindOfClass:[UIVisualEffectView class]]) {
        ((UIVisualEffectView *)view).effect = nil;
        view.backgroundColor = [UIColor clearColor];
    }
    WDClearHeaderRecur(view, 0);
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
    WDPlacePlate(host, bounds, inx, radius, 15, NO, YES, NO);
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
    WDPlacePlate(cell, bounds, inx, radius, corners, showSep, YES, NO);

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
    if (catRow) {
        WDClearNudgeDeep(cell, 0);
    } else {
        WDBalanceInner(cell, inx);
    }
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
        if ([objc_getAssociatedObject(cell, kWDInsetKey) boolValue]) {
            cell.contentView.frame = UIEdgeInsetsInsetRect(cell.bounds, UIEdgeInsetsZero);
            objc_setAssociatedObject(cell, kWDInsetKey, nil, WD_ASSOC);
        }
        // 还原内容容器内缩与隐藏掉的箭头
        WDFrameInset(cell.contentView ?: cell, 0);
        UIView *it = WDCellItemView(cell);
        if (it && it != cell.contentView) WDFrameInset(it, 0);
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
        UIView *box = WDSearchInnerBox(view);
        if (box) {
            NSValue *sf = objc_getAssociatedObject(box, kWDSearchBoxFrameKey);
            if (sf) {
                box.frame = [sf CGRectValue];
                objc_setAssociatedObject(box, kWDSearchBoxFrameKey, nil, WD_ASSOC);
            }
            NSValue *bf = objc_getAssociatedObject(box, kWDOrigFrameKey);
            if (bf) {
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
    if (!objc_getAssociatedObject(tv, kWDTableBgKey)) {
        objc_setAssociatedObject(tv, kWDTableBgKey, tv.backgroundColor ?: (id)[NSNull null], WD_ASSOC);
    }
    objc_setAssociatedObject(tv, kWDTailClearKey, @YES, WD_ASSOC);
    tv.backgroundColor = [UIColor clearColor];
    tv.opaque = NO;
    if (tv.backgroundView) {
        tv.backgroundView.backgroundColor = [UIColor clearColor];
        tv.backgroundView.opaque = NO;
        tv.backgroundView.hidden = YES;
    }
    tv.separatorColor = [UIColor clearColor];
    tv.separatorStyle = UITableViewCellSeparatorStyleNone;
    if (tv.tableFooterView) WDStyleClearHeader(tv.tableFooterView);
    UIView *p = tv.superview;
    int d = 0;
    while (p && d < 4) {
        if ([p isKindOfClass:[UIWindow class]]) break;
        const char *pn = class_getName(object_getClass(p));
        if (pn && (strstr(pn, "NavigationBar") || strstr(pn, "TabBar"))) break;
        p.backgroundColor = [UIColor clearColor];
        p.opaque = NO;
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
