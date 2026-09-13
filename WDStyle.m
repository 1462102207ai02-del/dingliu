#import "WDStyle.h"
#import "WDPrefs.h"
#import "WDCatalog.h"

static const void *kWDCardViewKey = &kWDCardViewKey;
static BOOL gApplying = NO;

static BOOL WDBusy(void) {
    return gApplying;
}

static UIView *WDSuperviewForInset(UIView *v) {
    UIView *p = v.superview;
    if (!p) return nil;
    // 导航栏/TabBar 的直接父视图经常和自身同宽，继续往上找到更宽的容器
    CGFloat w = v.bounds.size.width;
    UIView *best = p;
    for (int i = 0; i < 6 && p; i++, p = p.superview) {
        if (p.bounds.size.width > best.bounds.size.width + 1.0) best = p;
        if (p.bounds.size.width >= w + 8.0) return p;
    }
    return best;
}

static UITableView *WDTableOfCell(UIView *cell) {
    for (UIView *p = cell.superview; p; p = p.superview) {
        if ([p isKindOfClass:[UITableView class]]) return (UITableView *)p;
    }
    return nil;
}

static NSIndexPath *WDIndexPath(UITableView *tv, UITableViewCell *cell) {
    if (!tv || !cell) return nil;
    NSIndexPath *ip = [tv indexPathForCell:cell];
    if (ip) return ip;
    // 即将展示但尚未入屏
    CGPoint pt = [cell.superview convertPoint:cell.center toView:tv];
    return [tv indexPathForRowAtPoint:pt];
}

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

static void WDFitInsetFrame(UIView *v, CGFloat inset) {
    if (!v || inset <= 0) return;
    UIView *parent = WDSuperviewForInset(v);
    if (!parent) return;
    CGRect pb = parent.bounds;
    CGFloat newW = pb.size.width - inset * 2.0;
    if (newW < 48.0) return;
    CGRect f = v.frame;
    // 相对父视图坐标重算，绝不在当前 frame 上累加
    CGRect inParent = [v.superview convertRect:pb fromView:parent];
    CGFloat newX = inParent.origin.x + inset;
    if (fabs(f.origin.x - newX) < 0.5 && fabs(f.size.width - newW) < 0.5) return;
    f.origin.x = newX;
    f.size.width = newW;
    gApplying = YES;
    v.frame = f;
    gApplying = NO;
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

#pragma mark - 顶栏 / 底栏

void WDApplyChrome(UIView *view, const WDItem *item) {
    if (!view || !item || WDBusy()) return;
    if (!WDItemOn(item)) return;
    WDFitInsetFrame(view, WDItemInset(item));
    WDRoundLayer(view.layer, WDItemRadius(item));
}

#pragma mark - 横幅

void WDApplyBanner(UIView *view, const WDItem *item) {
    if (!view || !item || WDBusy()) return;
    if (!WDItemOn(item)) return;
    WDFitInsetFrame(view, WDItemInset(item));
    WDRoundLayer(view.layer, WDItemRadius(item));
}

#pragma mark - 普通视图 / 气泡

void WDApplyView(UIView *view, const WDItem *item) {
    if (!view || !item || WDBusy()) return;
    if (!WDItemOn(item)) return;
    CGFloat inset = WDItemInset(item);
    if (inset > 0) WDFitInsetFrame(view, inset);
    WDRoundLayer(view.layer, WDItemRadius(item));
}

void WDApplyBubble(UIView *view, const WDItem *item) {
    if (!view || !item || WDBusy()) return;
    if (!WDItemOn(item)) return;
    // 气泡只圆角，默认不缩进，避免把气泡挤成一条
    WDRoundLayer(view.layer, WDItemRadius(item));
}

#pragma mark - 列表卡片底板

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

static UIRectCorner WDCornersForCell(UITableView *tv, NSIndexPath *ip) {
    // 默认每行独立成卡（四角圆角），和顶栏/底栏/横幅同一语言
    (void)tv; (void)ip;
    return UIRectCornerAllCorners;
}

void WDApplyCell(UITableViewCell *cell, UITableView *tv, NSIndexPath *ip, const WDItem *item) {
    if (!cell || !item || WDBusy()) return;
    if (!WDItemOn(item)) return;

    if (!tv) tv = WDTableOfCell(cell);
    CGFloat inset = WDItemInset(item);
    if (tv && inset > 0) {
        CGFloat tableW = tv.bounds.size.width;
        CGFloat newW = tableW - inset * 2.0;
        if (newW > 48.0) {
            CGRect f = cell.frame;
            // 相对 table 宽度重算
            if (fabs(f.origin.x - inset) > 0.5 || fabs(f.size.width - newW) > 0.5) {
                f.origin.x = inset;
                f.size.width = newW;
                gApplying = YES;
                cell.frame = f;
                gApplying = NO;
            }
        }
    }

    WDCardPlate *plate = objc_getAssociatedObject(cell, kWDCardViewKey);
    if (![plate isKindOfClass:[WDCardPlate class]]) {
        plate = [[WDCardPlate alloc] initWithFrame:cell.bounds];
        objc_setAssociatedObject(cell, kWDCardViewKey, plate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cell.backgroundView = plate;
        cell.backgroundColor = [UIColor clearColor];
        if ([cell.contentView.backgroundColor isEqual:[UIColor whiteColor]] ||
            cell.contentView.backgroundColor != nil) {
            cell.contentView.backgroundColor = [UIColor clearColor];
        }
    }
    plate.frame = cell.bounds;
    plate.corners = WDCornersForCell(tv, ip ?: WDIndexPath(tv, cell));
    plate.radius = WDItemRadius(item);
    [plate redraw];

    // 系统分割线藏掉，卡片自己就是边界
    cell.separatorInset = UIEdgeInsetsMake(0, cell.bounds.size.width, 0, 0);
    if ([cell respondsToSelector:@selector(setLayoutMargins:)]) {
        cell.layoutMargins = UIEdgeInsetsZero;
    }
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
