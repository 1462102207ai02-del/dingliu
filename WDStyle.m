#import "WDStyle.h"
#import <string.h>

static const void *kWDPlateKey = &kWDPlateKey;

@interface WDCardPlate : UIView
@property (nonatomic, strong) CAShapeLayer *fill;
@property (nonatomic, assign) CGFloat radius;
@end

@implementation WDCardPlate
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingNone;
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
    UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:rad];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fill.frame = r;
    _fill.path = p.CGPath;
    [CATransaction commit];
}
@end

void WDStyleRound(UIView *view, CGFloat radius, BOOL continuous) {
    if (!view) return;
    CALayer *l = view.layer;
    CGFloat lim = MIN(l.bounds.size.width, l.bounds.size.height) / 2.0;
    CGFloat r = radius;
    if (lim > 0 && r > lim) r = lim;
    if (r < 0) r = 0;
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

void WDStyleCell(UITableViewCell *cell, CGFloat inset, CGFloat radius, BOOL continuous) {
    if (!cell) return;
    // 滑动菜单 cell：只圆角 contentView，不换 backgroundView、不 clip 自身，避免挡侧滑
    const char *cn = object_getClassName(cell);
    if (cn && strstr(cn, "MultiMenu")) {
        WDStyleRound(cell.contentView, radius, continuous);
        return;
    }

    CGRect bounds = cell.bounds;
    if (bounds.size.width < 32 || bounds.size.height < 8) return;

    CGFloat inx = MAX(0, inset);
    CGRect plateF = (inx > 0 && bounds.size.width > inx * 2 + 40)
        ? UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(1.5, inx, 1.5, inx))
        : UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(1.0, 0, 1.0, 0));

    WDCardPlate *plate = objc_getAssociatedObject(cell, kWDPlateKey);
    if (![plate isKindOfClass:[WDCardPlate class]]) {
        UIView *existing = cell.backgroundView;
        if (existing && ![existing isKindOfClass:[WDCardPlate class]]) {
            WDStyleRound(cell.contentView, radius, continuous);
            return;
        }
        plate = [[WDCardPlate alloc] initWithFrame:plateF];
        objc_setAssociatedObject(cell, kWDPlateKey, plate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cell.backgroundView = plate;
        cell.backgroundColor = [UIColor clearColor];
    }
    if (!CGRectEqualToRect(plate.frame, plateF)) plate.frame = plateF;
    if (fabs(plate.radius - radius) > 0.25) {
        plate.radius = radius;
        [plate redraw];
    }
    WDStyleRound(cell.contentView, 0, continuous);
}

void WDStyleInvalidate(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return;
    for (UIWindow *w in app.windows) [w setNeedsLayout];
}
