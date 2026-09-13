#import "WDStyle.h"
#import "WDPrefs.h"
#import "WDCatalog.h"

static const void *kWDCardViewKey = &kWDCardViewKey;
static BOOL gApplying = NO;

static BOOL WDBusy(void) { return gApplying; }

static void WDRoundLayer(CALayer *l, CGFloat r) {
    if (!l || r < 0) return;
    CGFloat limit = MIN(l.bounds.size.width, l.bounds.size.height) / 2.0;
    if (limit > 0) r = MIN(r, limit);
    l.cornerRadius = r;
    l.masksToBounds = YES;
    if ([WDPrefs shared].continuous) {
        if (@available(iOS 13.0, *)) {
            if ([l respondsToSelector:@selector(setCornerCurve:)]) {
                l.cornerCurve = kCACornerCurveContinuous;
            }
        }
    }
}

static BOOL WDItemOn(const WDItem *it) {
    if (!it) return NO;
    WDPrefs *p = [WDPrefs shared];
    if (!p.master) return NO;
    return [p enabledForClass:@(it->cls) def:it->defOn != 0];
}

static CGFloat WDItemRadius(const WDItem *it) {
    return [[WDPrefs shared] radiusForClass:@(it->cls) def:it->defRadius];
}

static CGFloat WDItemInset(const WDItem *it) {
    return [[WDPrefs shared] insetForClass:@(it->cls) def:it->defInset];
}

#pragma mark - 卡片底板（不改宿主 frame）

@interface WDCardPlate : UIView
@property (nonatomic, strong) CAShapeLayer *fill;
@property (nonatomic, assign) UIRectCorner corners;
@property (nonatomic, assign) CGFloat radius;
@end

@implementation WDCardPlate
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
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
    }
}
- (void)redraw {
    CGRect r = self.bounds;
    if (CGRectIsEmpty(r) || r.size.width < 1 || r.size.height < 1) {
        _fill.path = NULL;
        return;
    }
    CGFloat rad = MIN(_radius, MIN(r.size.width, r.size.height) / 2.0);
    UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:r
                                            byRoundingCorners:_corners
                                                  cornerRadii:CGSizeMake(rad, rad)];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fill.frame = r;
    _fill.path = p.CGPath;
    [CATransaction commit];
}
@end

// 用 mask 做出双侧缩进+圆角，绝不写 view.frame
static void WDMaskInsetRound(UIView *v, CGFloat inset, CGFloat radius) {
    if (!v) return;
    CGRect b = v.bounds;
    if (b.size.width < 8 || b.size.height < 2) return;
    CGFloat x = MAX(0, inset);
    CGRect r = CGRectMake(x, 0, b.size.width - x * 2.0, b.size.height);
    if (r.size.width < 24.0) {
        v.layer.mask = nil;
        WDRoundLayer(v.layer, radius);
        return;
    }
    CAShapeLayer *mask = ([v.layer.mask isKindOfClass:[CAShapeLayer class]])
        ? (CAShapeLayer *)v.layer.mask : [CAShapeLayer layer];
    UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:radius];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    mask.frame = b;
    mask.path = p.CGPath;
    if (v.layer.mask != mask) v.layer.mask = mask;
    [CATransaction commit];
}

static void WDClearMask(UIView *v) {
    if (v.layer.mask) v.layer.mask = nil;
}

#pragma mark - 顶栏 / 底栏 / 横幅 / 普通视图

void WDApplyChrome(UIView *view, const WDItem *item) {
    if (!view || !item || WDBusy()) return;
    if (!WDItemOn(item)) { WDClearMask(view); return; }
    gApplying = YES;
    WDMaskInsetRound(view, WDItemInset(item), WDItemRadius(item));
    gApplying = NO;
}

void WDApplyBanner(UIView *view, const WDItem *item) {
    if (!view || !item || WDBusy()) return;
    if (!WDItemOn(item)) { WDClearMask(view); return; }
    gApplying = YES;
    WDMaskInsetRound(view, WDItemInset(item), WDItemRadius(item));
    gApplying = NO;
}

void WDApplyView(UIView *view, const WDItem *item) {
    if (!view || !item || WDBusy()) return;
    if (!WDItemOn(item)) { WDClearMask(view); return; }
    gApplying = YES;
    CGFloat inset = WDItemInset(item);
    if (inset > 0) WDMaskInsetRound(view, inset, WDItemRadius(item));
    else {
        WDClearMask(view);
        WDRoundLayer(view.layer, WDItemRadius(item));
    }
    gApplying = NO;
}

void WDApplyBubble(UIView *view, const WDItem *item) {
    if (!view || !item || WDBusy()) return;
    if (!WDItemOn(item)) return;
    gApplying = YES;
    WDRoundLayer(view.layer, WDItemRadius(item));
    gApplying = NO;
}

#pragma mark - 列表：底板缩进，cell.frame 不动

void WDApplyCell(UITableViewCell *cell, UITableView *tv, NSIndexPath *ip, const WDItem *item) {
    if (!cell || !item || WDBusy()) return;
    (void)tv; (void)ip;
    if (!WDItemOn(item)) return;

    CGFloat inset = WDItemInset(item);
    CGRect bounds = cell.bounds;
    CGRect plateF = (inset > 0 && bounds.size.width > inset * 2 + 48)
        ? UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(1.5, inset, 1.5, inset))
        : bounds;

    gApplying = YES;
    WDCardPlate *plate = objc_getAssociatedObject(cell, kWDCardViewKey);
    if (![plate isKindOfClass:[WDCardPlate class]]) {
        plate = [[WDCardPlate alloc] initWithFrame:plateF];
        objc_setAssociatedObject(cell, kWDCardViewKey, plate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cell.backgroundView = plate;
        cell.backgroundColor = [UIColor clearColor];
        UIColor *cvbg = cell.contentView.backgroundColor;
        if (cvbg) cell.contentView.backgroundColor = [UIColor clearColor];
    } else if (!CGRectEqualToRect(plate.frame, plateF)) {
        plate.frame = plateF;
    }
    plate.corners = UIRectCornerAllCorners;
    plate.radius = WDItemRadius(item);
    [plate redraw];

    UIEdgeInsets want = UIEdgeInsetsMake(0, bounds.size.width, 0, 0);
    if (!UIEdgeInsetsEqualToEdgeInsets(cell.separatorInset, want)) {
        cell.separatorInset = want;
    }
    gApplying = NO;
}

void WDStyleVisibleTables(void) {
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
        while (stack.count) {
            UIView *v = stack.lastObject;
            [stack removeLastObject];
            if ([v isKindOfClass:[UITableView class]]) {
                [(UITableView *)v reloadData];
            }
            [stack addObjectsFromArray:v.subviews];
        }
    }
}
