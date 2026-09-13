#import "WDStyle.h"
#import <string.h>

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
        CGRect sr = CGRectMake(hole.origin.x + 16, r.size.height - 1.0 / [UIScreen mainScreen].scale,
                               hole.size.width - 32, 1.0 / [UIScreen mainScreen].scale);
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

#pragma mark - 圆角（记录原值，可还原）

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

#pragma mark - 单元格（遮罩缩进：不改内容坐标，避免卡死/时间位移）

static UIColor *WDGroupedFill(void) {
    if (@available(iOS 13.0, *)) return [UIColor systemGroupedBackgroundColor];
    return [UIColor groupTableViewBackgroundColor];
}

static UIColor *WDCardFill(void) {
    if (@available(iOS 13.0, *)) return [UIColor secondarySystemGroupedBackgroundColor];
    return [UIColor whiteColor];
}

static UIColor *WDGapFillForView(UIView *view) {
    UIView *sv = view;
    while (sv) {
        if ([sv isKindOfClass:[UITableView class]]) {
            UIColor *c = sv.backgroundColor;
            if (c && ![c isEqual:[UIColor clearColor]]) return c;
            break;
        }
        sv = sv.superview;
    }
    return WDGroupedFill();
}

static void WDPaintTableGap(UITableView *tv, UIColor *fill) {
    if (!tv) return;
    if (!objc_getAssociatedObject(tv, kWDTableBgKey)) {
        objc_setAssociatedObject(tv, kWDTableBgKey, tv.backgroundColor ?: (id)[NSNull null], WD_ASSOC);
    }
    if (!fill) fill = WDGroupedFill();
    tv.backgroundColor = fill;
    tv.opaque = YES;
    if (tv.backgroundView) tv.backgroundView.backgroundColor = fill;
    tv.separatorColor = [UIColor clearColor];
}

static NSUInteger WDSectionCornersAt(UITableView *tv, NSIndexPath *ip) {
    if (!tv || !ip) return 15;
    // 通讯录顶部五大类（新的朋友/群聊/标签/公众号/企业微信）可能拆成多个 section，合成一整片。
    id del = tv.delegate;
    if (del && [del respondsToSelector:@selector(ConvertToNormalContactSection:)]) {
        NSInteger firstLetter = 0;
        @try {
            firstLetter = ((NSInteger (*)(id, SEL, NSInteger))objc_msgSend)(del, @selector(ConvertToNormalContactSection:), 0);
        } @catch (NSException *e) { firstLetter = 0; }
        if (firstLetter > 1 && ip.section >= 0 && ip.section < firstLetter) {
            NSInteger lastSec = firstLetter - 1;
            NSInteger lastRows = 0;
            @try { lastRows = [tv numberOfRowsInSection:lastSec]; } @catch (NSException *e) { lastRows = 1; }
            BOOL first = (ip.section == 0 && ip.row == 0);
            BOOL last = (ip.section == lastSec && ip.row == lastRows - 1);
            if (first && last) return 15;
            if (first) return (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner);
            if (last) return (kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner);
            return 0;
        }
    }
    NSInteger rows = 0;
    @try { rows = [tv numberOfRowsInSection:ip.section]; } @catch (NSException *e) { return 15; }
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

static void WDHideNativeSeparators(UITableViewCell *cell) {
    if ([cell respondsToSelector:@selector(setSeparatorInset:)]) {
        CGFloat w = cell.bounds.size.width;
        cell.separatorInset = UIEdgeInsetsMake(0, w, 0, 0);
    }
    for (UIView *s in cell.subviews) {
        const char *nm = class_getName(object_getClass(s));
        if (!nm) continue;
        if (strstr(nm, "Separator") || strstr(nm, "separator")) {
            s.hidden = YES;
            s.alpha = 0;
        }
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
        if (p && f.origin.x < 1 && f.size.width >= p.bounds.size.width - 2 && f.size.height >= p.bounds.size.height - 2) {
            v.backgroundColor = [UIColor clearColor];
            ((UIImageView *)v).image = nil;
            v.opaque = NO;
        }
    }
    if (depth < 2) {
        for (UIView *s in v.subviews) WDClearFillViews(s, depth + 1);
    }
}

static void WDPlacePlate(UIView *host, CGRect bounds, CGFloat inset, CGFloat radius, NSUInteger corners, BOOL showSep, BOOL punch, BOOL asCellBg) {
    WDCardPlate *plate = objc_getAssociatedObject(host, kWDPlateKey);
    if (![plate isKindOfClass:[WDCardPlate class]]) {
        plate = [[WDCardPlate alloc] initWithFrame:bounds];
        plate.userInteractionEnabled = NO;
        plate.opaque = NO;
        objc_setAssociatedObject(host, kWDPlateKey, plate, WD_ASSOC);
    }
    // 打孔必须盖在内容之上，灰缝才看得见；且绝不接收点击（折叠横幅/滑动菜单要点得着）。
    // 设置页底板仍用 backgroundView，避免挡住控件。
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
        } else if (plate.superview != host) {
            [host addSubview:plate];
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
        UIColor *gap = WDGapFillForView(host);
        plate.fill.fillColor = gap.CGColor;
    } else {
        plate.fill.fillColor = WDCardFill().CGColor;
    }
    if (changed) [plate redraw];
}

void WDStyleView(UIView *view, CGFloat inset, CGFloat radius, BOOL continuous, int tag) {
    if (!view) return;
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
    view.backgroundColor = [UIColor clearColor];
    view.opaque = NO;
    // 不 clip、不改子视图 frame —— 折叠横幅要点得着。
    WDPlacePlate(view, bounds, inx, radius, 15, NO, YES, NO);
    (void)continuous;
}

void WDStyleSearch(UIView *view, CGFloat inset, CGFloat radius, BOOL continuous, int tag) {
    if (!view) return;
    CGRect bounds = view.bounds;
    if (bounds.size.width < 24 || bounds.size.height < 8) return;
    objc_setAssociatedObject(view, kWDTagKey, @(tag), WD_ASSOC);
    if (!objc_getAssociatedObject(view, kWDOrigBgColorKey)) {
        UIColor *oc = view.backgroundColor;
        objc_setAssociatedObject(view, kWDOrigBgColorKey, oc ? (id)oc : (id)[NSNull null], WD_ASSOC);
    }
    view.backgroundColor = [UIColor clearColor];
    view.opaque = NO;

    CGFloat inx = MAX(0, inset);
    if (inx > 0 && bounds.size.width <= inx * 2 + 24) inx = 0;

    UIView *inner = nil;
    for (UIView *s in view.subviews) {
        const char *nm = class_getName(object_getClass(s));
        if (nm && (strstr(nm, "SearchBox") || strstr(nm, "searchBox") || strstr(nm, "SearchText"))) {
            inner = s; break;
        }
    }
    if (!inner) {
        for (UIView *s in view.subviews) {
            if (s.bounds.size.width > bounds.size.width * 0.5 && s.bounds.size.height > 20) { inner = s; break; }
        }
    }
    UIView *container = nil;
    @try {
        id box = [view valueForKey:@"searchBoxContainer"];
        if ([box isKindOfClass:[UIView class]]) container = (UIView *)box;
    } @catch (NSException *e) {}
    if (!container) {
        @try {
            id box = [view valueForKey:@"searchBox"];
            if ([box isKindOfClass:[UIView class]]) container = (UIView *)box;
        } @catch (NSException *e) {}
    }
    if (!container) container = inner;

    if (container && container != view) {
        WDStyleRound(container, radius, continuous, tag);
        container.clipsToBounds = YES;
        container.layer.masksToBounds = YES;
        // 首页搜索是两层：外层 searchBoxContainer 负责圆角，内层 searchBox 跟外层对齐。
        for (UIView *s in container.subviews) {
            if (s.bounds.size.width > container.bounds.size.width * 0.6) {
                WDStyleRound(s, radius, continuous, tag);
            }
        }
    } else {
        WDStyleRound(view, radius, continuous, tag);
    }
    if (inx > 0.5) WDPlacePlate(view, bounds, inx, radius, 15, NO, YES, NO);
}

static void WDClearHeaderRecur(UIView *v, int depth) {
    if (!v || depth > 3) return;
    v.backgroundColor = [UIColor clearColor];
    v.opaque = NO;
    const char *nm = class_getName(object_getClass(v));
    if ([v isKindOfClass:[UIImageView class]] || (nm && strstr(nm, "Background"))) {
        if ([v isKindOfClass:[UIImageView class]]) ((UIImageView *)v).image = nil;
    }
    if (nm && (strstr(nm, "Separator") || strstr(nm, "LineView") || strstr(nm, "lineView") || strstr(nm, "Dash"))) {
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
    WDClearHeaderRecur(view, 0);
}

void WDStyleCellAt(UITableViewCell *cell, UITableView *tv, NSIndexPath *ip, CGFloat inset, CGFloat radius, BOOL continuous, int tag) {
    if (!cell) return;
    CGRect bounds = cell.bounds;
    if (bounds.size.width < 32 || bounds.size.height < 8) return;

    objc_setAssociatedObject(cell, kWDTagKey, @(tag), WD_ASSOC);

    CGFloat inx = MAX(0, inset);
    if (inx > 0 && bounds.size.width <= inx * 2 + 40) inx = 0;
    NSUInteger corners = ip ? WDSectionCornersAt(tv, ip) : WDSectionCorners(cell);
    if (bounds.size.width < 24) return;

    if (!tv) {
        UIView *sv = cell.superview;
        while (sv && ![sv isKindOfClass:[UITableView class]]) sv = sv.superview;
        if ([sv isKindOfClass:[UITableView class]]) tv = (UITableView *)sv;
    }
    if (tv) WDPaintTableGap(tv, WDGapFillForView(tv));

    if (!objc_getAssociatedObject(cell, kWDOrigBgKey)) {
        UIView *orig = cell.backgroundView;
        objc_setAssociatedObject(cell, kWDOrigBgKey, orig ? (id)orig : (id)[NSNull null], WD_ASSOC);
        UIColor *oc = cell.backgroundColor;
        objc_setAssociatedObject(cell, kWDOrigBgColorKey, oc ? (id)oc : (id)[NSNull null], WD_ASSOC);
    }

    BOOL showSep = (corners == 0) || ((corners & (kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner)) == 0);
    WDPlacePlate(cell, bounds, inx, radius, corners, showSep, YES, NO);

    cell.backgroundColor = [UIColor clearColor];
    cell.opaque = NO;
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.clipsToBounds = NO;
    // 不改 contentView.frame / layoutMargins / 内部 ItemView.frame。
    if ([cell respondsToSelector:@selector(setBkgColor:)]) {
        @try { [cell setValue:[UIColor clearColor] forKey:@"bkgColor"]; } @catch (NSException *e) {}
    }
    WDHideNativeSeparators(cell);
    WDClearFillViews(cell, 0);
    WDClearFillViews(cell.contentView, 0);
    (void)continuous;
}

void WDStyleCell(UITableViewCell *cell, CGFloat inset, CGFloat radius, BOOL continuous, int tag) {
    WDStyleCellAt(cell, nil, nil, inset, radius, continuous, tag);
}

#pragma mark - 设置页单元格卡片化

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
        WDRevertRound(cell.contentView);
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

#pragma mark - 全量重排

static void WDInvalidateRecur(UIView *v, int depth) {
    if (!v || depth > 12) return;
    [v setNeedsLayout];
    for (UIView *s in v.subviews) WDInvalidateRecur(s, depth + 1);
}

void WDStyleInvalidate(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return;
    for (UIWindow *w in app.windows) WDInvalidateRecur(w, 0);
}
