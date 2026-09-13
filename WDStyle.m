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
@property (nonatomic, assign) CGFloat radius;
@property (nonatomic, assign) NSUInteger corners;
@end

@implementation WDCardPlate
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingNone;
        _corners = 15; // 默认四角
        _fill = [CAShapeLayer layer];
        _fill.fillColor = [UIColor whiteColor].CGColor;
        if (@available(iOS 13.0, *)) {
            _fill.fillColor = [UIColor secondarySystemGroupedBackgroundColor].CGColor;
        }
        [self.layer addSublayer:_fill];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [self redraw];
}
- (void)traitCollectionDidChange:(UITraitCollection *)prev {
    [super traitCollectionDidChange:prev];
    if (@available(iOS 13.0, *)) {
        _fill.fillColor = [UIColor secondarySystemGroupedBackgroundColor].CGColor;
        [self redraw];
    }
}
- (void)redraw {
    CGRect r = self.bounds;
    if (r.size.width < 1 || r.size.height < 1) {
        _fill.path = NULL;
        return;
    }
    CGFloat rad = MIN(_radius, MIN(r.size.width, r.size.height) / 2.0);
    UIRectCorner uc = 0;
    NSUInteger c = _corners;
    if (c & kCALayerMinXMinYCorner) uc |= UIRectCornerTopLeft;
    if (c & kCALayerMaxXMinYCorner) uc |= UIRectCornerTopRight;
    if (c & kCALayerMinXMaxYCorner) uc |= UIRectCornerBottomLeft;
    if (c & kCALayerMaxXMaxYCorner) uc |= UIRectCornerBottomRight;
    UIBezierPath *p = nil;
    if (uc == 0 || rad <= 0.2) p = [UIBezierPath bezierPathWithRect:r];
    else p = [UIBezierPath bezierPathWithRoundedRect:r byRoundingCorners:uc cornerRadii:CGSizeMake(rad, rad)];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fill.frame = r;
    _fill.path = p.CGPath;
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

#pragma mark - 单元格（整段卡片：左右缩进，中间行左右平直）

static UIColor *WDGroupedFill(void) {
    if (@available(iOS 13.0, *)) return [UIColor systemGroupedBackgroundColor];
    return [UIColor groupTableViewBackgroundColor];
}

static UIColor *WDCardFill(void) {
    if (@available(iOS 13.0, *)) return [UIColor secondarySystemGroupedBackgroundColor];
    return [UIColor whiteColor];
}

static void WDApplyInset(UITableViewCell *cell, CGRect target) {
    UIView *cv = cell.contentView;
    CGRect cur = cv.frame;
    if (fabs(cur.origin.x - target.origin.x) < 0.5 &&
        fabs(cur.origin.y - target.origin.y) < 0.5 &&
        fabs(cur.size.width - target.size.width) < 0.5 &&
        fabs(cur.size.height - target.size.height) < 0.5) return;
    objc_setAssociatedObject(cell, kWDInsetKey, @YES, WD_ASSOC);
    cv.frame = target;
}

static void WDPaintGroupedHost(UIView *view) {
    if (!view) return;
    UIView *sv = view.superview;
    while (sv) {
        if ([sv isKindOfClass:[UITableView class]] || [sv isKindOfClass:[UIScrollView class]]) break;
        if (!sv.superview) break;
        sv = sv.superview;
    }
    if (!sv) sv = view.superview;
    if (!sv) return;
    if (!objc_getAssociatedObject(sv, kWDTableBgKey)) {
        objc_setAssociatedObject(sv, kWDTableBgKey, sv.backgroundColor ?: (id)[NSNull null], WD_ASSOC);
    }
    UIColor *fill = WDGroupedFill();
    sv.backgroundColor = fill;
    sv.opaque = YES;
    if ([sv isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)sv;
        if (tv.backgroundView) tv.backgroundView.backgroundColor = fill;
    }
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

    WDStoreOrig(view);
    objc_setAssociatedObject(view, kWDTagKey, @(tag), WD_ASSOC);
    WDPaintGroupedHost(view);

    if (!objc_getAssociatedObject(view, kWDOrigBgColorKey)) {
        UIColor *oc = view.backgroundColor;
        objc_setAssociatedObject(view, kWDOrigBgColorKey, oc ? (id)oc : (id)[NSNull null], WD_ASSOC);
    }
    view.backgroundColor = [UIColor clearColor];
    view.opaque = NO;
    view.clipsToBounds = NO;

    CGRect plateF = UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(0, inx, 0, inx));
    if (plateF.size.width < 24 || plateF.size.height < 4) {
        WDStyleRound(view, radius, continuous, tag);
        return;
    }

    WDCardPlate *plate = objc_getAssociatedObject(view, kWDPlateKey);
    if (![plate isKindOfClass:[WDCardPlate class]]) {
        plate = [[WDCardPlate alloc] initWithFrame:plateF];
        plate.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        objc_setAssociatedObject(view, kWDPlateKey, plate, WD_ASSOC);
        [view insertSubview:plate atIndex:0];
    } else if (plate.superview != view) {
        [view insertSubview:plate atIndex:0];
    } else if (view.subviews.firstObject != plate) {
        [view sendSubviewToBack:plate];
    }
    plate.frame = plateF;
    plate.radius = radius;
    plate.corners = 15;
    plate.fill.fillColor = WDCardFill().CGColor;
    [plate redraw];

    WDStyleRoundCorners(view, 0, 0, continuous, tag);
    view.layer.masksToBounds = NO;
}

static NSUInteger WDSectionCorners(UITableViewCell *cell) {
    UIView *v = cell.superview;
    UITableView *tv = nil;
    while (v) {
        if ([v isKindOfClass:[UITableView class]]) { tv = (UITableView *)v; break; }
        v = v.superview;
    }
    if (!tv) return 0;
    NSIndexPath *ip = [tv indexPathForCell:cell];
    if (!ip) {
        CGPoint p = [cell.superview convertPoint:cell.center toView:tv];
        ip = [tv indexPathForRowAtPoint:p];
    }
    if (!ip) return 0;
    NSInteger rows = [tv numberOfRowsInSection:ip.section];
    if (rows <= 1) return 15;
    if (ip.row == 0) return (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner);
    if (ip.row == rows - 1) return (kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner);
    return 0;
}

void WDStyleCell(UITableViewCell *cell, CGFloat inset, CGFloat radius, BOOL continuous, int tag) {
    if (!cell) return;
    CGRect bounds = cell.bounds;
    if (bounds.size.width < 32 || bounds.size.height < 8) return;

    objc_setAssociatedObject(cell, kWDTagKey, @(tag), WD_ASSOC);

    CGFloat inx = MAX(0, inset);
    if (inx > 0 && bounds.size.width <= inx * 2 + 40) inx = 0;
    NSUInteger corners = WDSectionCorners(cell);
    CGRect plateF = UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(0, inx, 0, inx));
    if (plateF.size.width < 24 || plateF.size.height < 4) return;

    UIView *sv = cell.superview;
    while (sv && ![sv isKindOfClass:[UITableView class]]) sv = sv.superview;
    if ([sv isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)sv;
        if (!objc_getAssociatedObject(tv, kWDTableBgKey)) {
            objc_setAssociatedObject(tv, kWDTableBgKey, tv.backgroundColor ?: (id)[NSNull null], WD_ASSOC);
        }
        UIColor *fill = WDGroupedFill();
        tv.backgroundColor = fill;
        tv.opaque = YES;
        if (tv.backgroundView) tv.backgroundView.backgroundColor = fill;
    }

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
    }
    BOOL changed = !CGRectEqualToRect(plate.frame, plateF) ||
                   fabs(plate.radius - radius) > 0.25 ||
                   plate.corners != corners;
    plate.frame = plateF;
    plate.radius = radius;
    plate.corners = corners;
    plate.fill.fillColor = WDCardFill().CGColor;
    if (changed) [plate redraw];

    // 单元格本体透明，左右露分组灰底，看起来才是「缩进」。不写 cell.frame。
    cell.backgroundColor = [UIColor clearColor];
    cell.opaque = NO;
    if ([cell respondsToSelector:@selector(setSeparatorInset:)]) {
        cell.separatorInset = UIEdgeInsetsMake(0, 16 + inx, 0, inx);
    }
    WDApplyInset(cell, plateF);
    cell.contentView.backgroundColor = [UIColor clearColor];
    WDStyleRoundCorners(cell.contentView, radius, corners, continuous, tag);
    cell.contentView.clipsToBounds = (corners != 0);
    if (cell.selectedBackgroundView) {
        cell.selectedBackgroundView.frame = plateF;
        WDStyleRoundCorners(cell.selectedBackgroundView, radius, corners, continuous, tag);
    }
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
    if (!CGRectEqualToRect(plate.frame, plateF)) plate.frame = plateF;
    if (changed) [plate redraw];
    if (inx > 0) WDApplyInset(cell, plateF);
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
