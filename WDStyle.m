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
    // 滑动菜单 cell：只圆角 contentView，不换 backgroundView、不 clip 自身，避免挡侧滑
    static Class kMultiMenu = Nil;
    static dispatch_once_t onceMM;
    dispatch_once(&onceMM, ^{ kMultiMenu = objc_getClass("MMMultiMenuTableViewCell"); });
    const char *cn = object_getClassName(cell);
    if ((kMultiMenu && [cell isKindOfClass:kMultiMenu]) || (cn && strstr(cn, "MultiMenu"))) {
        WDStyleRound(cell.contentView, radius, continuous, tag);
        return;
    }

    CGRect bounds = cell.bounds;
    if (bounds.size.width < 32 || bounds.size.height < 8) return;

    objc_setAssociatedObject(cell, kWDTagKey, @(tag), WD_ASSOC);

    CGFloat inx = MAX(0, inset);
    if (inx > 0 && bounds.size.width <= inx * 2 + 40) inx = 0;
    // 整段卡片：左右缩进，中间行左右平直，只有首尾四角。
    NSUInteger corners = WDSectionCorners(cell);
    CGRect plateF = UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(0, inx, 0, inx));
    if (plateF.size.width < 24 || plateF.size.height < 4) return;

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
    BOOL changed = !CGRectEqualToRect(plate.frame, plateF) ||
                   fabs(plate.radius - radius) > 0.25 ||
                   plate.corners != corners;
    plate.frame = plateF;
    plate.radius = radius;
    plate.corners = corners;
    if (changed) [plate redraw];
    cell.opaque = NO;
    if ([cell respondsToSelector:@selector(setSeparatorInset:)]) {
        cell.separatorInset = UIEdgeInsetsMake(0, 16 + inx, 0, inx);
    }
    // contentView 同样缩进。中间行不圆角，左右是平的。不写 cell.frame。
    WDApplyInset(cell, plateF);
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
