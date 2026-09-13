// WechatDuo 设置页
// v1.1.0
//   - 设置项按「页面顺序」分类，不再一屏铺开上百项
//   - 数值一律用输入框（不留滑杆），颜色一律用系统原生取色器
//   - 设置页自身也是卡片化 + 圆角 + 双侧缩进
//   - 总开关一关：所有独立开关置灰，插件整体不生效

#import "WDSettings.h"
#import "WDPrefs.h"
#import "WDCatalog.h"
#import "WDStyle.h"

#define WD_RADIUS_MAX 40.0
#define WD_INSET_MAX  32.0

#pragma mark - 单元格

@implementation WDCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        self.textLabel.font = [UIFont systemFontOfSize:16];
        self.detailTextLabel.font = [UIFont systemFontOfSize:12];
        if (@available(iOS 13.0, *)) {
            self.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        }
    }
    return self;
}
- (void)prepareForReuse {
    [super prepareForReuse];
    [self.sw removeFromSuperview];  self.sw = nil;
    [self.num removeFromSuperview]; self.num = nil;
    [self.dot removeFromSuperview]; self.dot = nil;
    self.accessoryType = UITableViewCellAccessoryNone;
    self.accessoryView = nil;
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
    self.userInteractionEnabled = YES;
    self.textLabel.text = nil;
    self.textLabel.textAlignment = NSTextAlignmentNatural;
    self.detailTextLabel.text = nil;
    if (@available(iOS 13.0, *)) {
        self.textLabel.textColor = [UIColor labelColor];
        self.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        self.textLabel.textColor = [UIColor blackColor];
        self.detailTextLabel.textColor = [UIColor grayColor];
    }
}
- (void)layoutSubviews {
    [super layoutSubviews];
    UIView *cv = self.contentView;
    CGFloat w = cv.bounds.size.width, h = cv.bounds.size.height;
    CGFloat right = 14;
    if (self.sw) {
        CGRect f = self.sw.frame;
        f.origin.x = w - f.size.width - 8;
        f.origin.y = (h - f.size.height) / 2.0;
        self.sw.frame = f;
        right = f.size.width + 20;
    } else if (self.num) {
        CGRect f = self.num.frame;
        f.size.height = 30;
        f.origin.x = w - f.size.width - 10;
        f.origin.y = (h - f.size.height) / 2.0;
        self.num.frame = f;
        right = f.size.width + 20;
    } else if (self.dot) {
        CGRect f = self.dot.frame;
        f.origin.x = w - f.size.width - (self.accessoryType == UITableViewCellAccessoryNone ? 14 : 34);
        f.origin.y = (h - f.size.height) / 2.0;
        self.dot.frame = f;
        right = w - f.origin.x + 8;
    }
    CGRect tf = self.textLabel.frame;
    if (tf.size.width > 0) {
        CGFloat maxW = MAX(80, w - tf.origin.x - right);
        if (tf.size.width > maxW) tf.size.width = maxW;
        self.textLabel.frame = tf;
    }
    CGRect df = self.detailTextLabel.frame;
    if (df.size.width > 0) {
        CGFloat maxW = MAX(80, w - df.origin.x - right);
        if (df.size.width > maxW) df.size.width = maxW;
        self.detailTextLabel.frame = df;
    }
}
@end

#pragma mark - 列表基类（卡片化 + 控件工厂）

@implementation WDListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 52;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 13.0, *)) {
        self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    } else {
        self.tableView.backgroundColor = [UIColor groupTableViewBackgroundColor];
    }
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 28, 0, 28);
}

- (WDCell *)wdCell:(UITableView *)tv ident:(NSString *)rid style:(UITableViewCellStyle)st {
    WDCell *c = (WDCell *)[tv dequeueReusableCellWithIdentifier:rid];
    if (!c) c = [[WDCell alloc] initWithStyle:st reuseIdentifier:rid];
    return c;
}

- (UISwitch *)wdSwitch:(WDCell *)c action:(SEL)a on:(BOOL)on enabled:(BOOL)enabled {
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    sw.on = on;
    sw.enabled = enabled;
    sw.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [sw addTarget:self action:a forControlEvents:UIControlEventValueChanged];
    [c.contentView addSubview:sw];
    c.sw = sw;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    return sw;
}

- (UITextField *)wdNumber:(WDCell *)c value:(NSString *)v placeholder:(NSString *)ph tag:(NSInteger)tag {
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 88, 30)];
    f.borderStyle = UITextBorderStyleRoundedRect;
    f.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    f.returnKeyType = UIReturnKeyDone;
    f.textAlignment = NSTextAlignmentCenter;
    f.font = [UIFont systemFontOfSize:15];
    f.text = v ?: @"";
    f.placeholder = ph ?: @"";
    f.tag = tag;
    f.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    [f addTarget:self action:@selector(wdNumberDone:) forControlEvents:UIControlEventEditingDidEnd];
    [f addTarget:self action:@selector(wdNumberDone:) forControlEvents:UIControlEventEditingDidEndOnExit];
    [c.contentView addSubview:f];
    c.num = f;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    return f;
}

- (UIView *)wdDot:(WDCell *)c color:(UIColor *)color {
    UIView *d = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 26, 26)];
    d.backgroundColor = color ?: [UIColor clearColor];
    d.layer.cornerRadius = 13;
    d.layer.masksToBounds = YES;
    if (@available(iOS 13.0, *)) {
        d.layer.borderColor = [UIColor separatorColor].CGColor;
    } else {
        d.layer.borderColor = [UIColor lightGrayColor].CGColor;
    }
    d.layer.borderWidth = 1.0;
    d.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [c.contentView addSubview:d];
    c.dot = d;
    return d;
}

- (void)wdNumberDone:(UITextField *)f {
    [f resignFirstResponder];
}

- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)ip {
    NSInteger rows = [tv numberOfRowsInSection:ip.section];
    NSUInteger corners = 0;
    if (rows <= 1) corners = 15;
    else if (ip.row == 0) corners = (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner);
    else if (ip.row == rows - 1) corners = (kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner);
    WDPrefs *p = [WDPrefs shared];
    CGFloat r = MIN(p.globalRadius, 14);
    WDStyleSettingsCell(cell, p.globalInset, r, corners, p.continuous);
}

@end

#pragma mark - 单个类的详细设置

@interface WDClassDetailController : WDListController
@property (nonatomic, assign) int idx;
- (const WDItem *)item;
- (NSString *)clsName;
@end

@implementation WDClassDetailController

- (void)viewDidLoad {
    [super viewDidLoad];
    const WDItem *it = &WDCatalogItems()[self.idx];
    self.title = [NSString stringWithUTF8String:it->zh];
}

- (const WDItem *)item { return &WDCatalogItems()[self.idx]; }
- (NSString *)clsName { return [NSString stringWithUTF8String:self.item->cls]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 0 ? 3 : 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s != 0) return nil;
    const WDItem *it = self.item;
    return [NSString stringWithFormat:@"%@ · %s", WDGroupTitle(it->group), it->cls];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s != 0) return nil;
    WDPrefs *p = [WDPrefs shared];
    return [NSString stringWithFormat:@"留空 = 跟随全局（圆角 %.0f / 缩进 %.0f）。气泡不缩进。",
            p.globalRadius, p.globalInset];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    WDPrefs *p = [WDPrefs shared];
    NSString *name = self.clsName;
    const WDItem *it = self.item;
    BOOL master = p.master;

    if (ip.section == 1) {
        WDCell *c = [self wdCell:tv ident:@"d.reset" style:UITableViewCellStyleDefault];
        c.textLabel.text = @"恢复本类默认";
        c.textLabel.textAlignment = NSTextAlignmentCenter;
        c.textLabel.textColor = [UIColor systemRedColor];
        return c;
    }

    WDCell *c = [self wdCell:tv ident:@"d.row" style:UITableViewCellStyleDefault];
    if (ip.row == 0) {
        c.textLabel.text = @"启用";
        [self wdSwitch:c action:@selector(onSwitch:) on:[p enabledForClass:name def:it->defOn != 0] enabled:master];
        if (!master) c.textLabel.textColor = [UIColor secondaryLabelColor];
        return c;
    }
    BOOL isRadius = (ip.row == 1);
    c.textLabel.text = isRadius ? @"圆角" : @"双侧缩进";
    NSString *val = @"";
    CGFloat global = isRadius ? p.globalRadius : p.globalInset;
    if (isRadius) {
        if ([p hasCustomRadius:name]) val = [NSString stringWithFormat:@"%.0f", [p radiusForClass:name def:it->defRadius]];
    } else {
        if ([p hasCustomInset:name]) val = [NSString stringWithFormat:@"%.0f", [p insetForClass:name def:it->defInset]];
    }
    [self wdNumber:c value:val
       placeholder:[NSString stringWithFormat:@"%.0f", global]
               tag:(isRadius ? 1 : 2)];
    c.num.enabled = master;
    if (!master) c.textLabel.textColor = [UIColor secondaryLabelColor];
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1) {
        [[WDPrefs shared] resetClass:self.clsName];
        [tv reloadData];
    }
}

- (void)onSwitch:(UISwitch *)sw {
    [[WDPrefs shared] setEnabled:sw.on forClass:self.clsName];
}

- (void)wdNumberDone:(UITextField *)f {
    [super wdNumberDone:f];
    NSString *raw = [f.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *name = self.clsName;
    WDPrefs *p = [WDPrefs shared];
    if (raw.length == 0) {
        if (f.tag == 1) [p clearRadiusForClass:name];
        else [p clearInsetForClass:name];
        return;
    }
    CGFloat v = [raw floatValue];
    if (v < 0) v = 0;
    if (f.tag == 1) {
        if (v > WD_RADIUS_MAX) v = WD_RADIUS_MAX;
        [p setRadius:v forClass:name];
    } else {
        if (v > WD_INSET_MAX) v = WD_INSET_MAX;
        [p setInset:v forClass:name];
    }
}

@end

#pragma mark - 某一页的元素列表

@interface WDClassListController : WDListController
@property (nonatomic, assign) int page;
@end

@implementation WDClassListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = WDPageTitle(self.page);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return (NSInteger)WDCatalogIndexesForPage(self.page).count;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    return @"点某一项可单独设置圆角与缩进。这里的开关受总开关控制。";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    WDPrefs *p = [WDPrefs shared];
    NSArray *idxs = WDCatalogIndexesForPage(self.page);
    const WDItem *it = &WDCatalogItems()[[idxs[(NSUInteger)ip.row] intValue]];
    WDCell *c = [self wdCell:tv ident:@"c.row" style:UITableViewCellStyleSubtitle];
    c.textLabel.text = [NSString stringWithUTF8String:it->zh];
    c.detailTextLabel.text = @(it->cls);
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    UISwitch *sw = [self wdSwitch:c action:@selector(onSwitch:)
                               on:[p enabledForClass:@(it->cls) def:it->defOn != 0]
                          enabled:p.master];
    sw.tag = [idxs[(NSUInteger)ip.row] intValue];
    // 这一行还要能点进去看详情，所以不能被开关把选中样式关掉
    c.selectionStyle = UITableViewCellSelectionStyleDefault;
    if (!p.master) c.textLabel.textColor = [UIColor secondaryLabelColor];
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (![WDPrefs shared].master) return;
    NSArray *idxs = WDCatalogIndexesForPage(self.page);
    WDClassDetailController *d = [[WDClassDetailController alloc] initWithStyle:UITableViewStyleGrouped];
    d.idx = [idxs[(NSUInteger)ip.row] intValue];
    [self.navigationController pushViewController:d animated:YES];
}

- (void)onSwitch:(UISwitch *)sw {
    const WDItem *it = &WDCatalogItems()[(int)sw.tag];
    [[WDPrefs shared] setEnabled:sw.on forClass:@(it->cls)];
}

@end

#pragma mark - 页面背景色（原生取色器）

@interface WDColorController : WDListController <UIColorPickerViewControllerDelegate>
@property (nonatomic, assign) int page;
@property (nonatomic, assign) BOOL pickingDark;
@end

@implementation WDColorController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [NSString stringWithFormat:@"%@ 背景", WDTabTitle(self.page)];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return s == 0 ? 3 : 1; }

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s != 0) return nil;
    return @"浅色 / 深色分别设定。深色没单独设时沿用浅色值。取色器为系统原生控件，支持透明度。";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    WDPrefs *p = [WDPrefs shared];
    if (ip.section == 1) {
        WDCell *c = [self wdCell:tv ident:@"bg.reset" style:UITableViewCellStyleDefault];
        c.textLabel.text = @"恢复本页默认";
        c.textLabel.textAlignment = NSTextAlignmentCenter;
        c.textLabel.textColor = [UIColor systemRedColor];
        return c;
    }
    WDCell *c = [self wdCell:tv ident:@"bg.row" style:UITableViewCellStyleValue1];
    if (ip.row == 0) {
        c.textLabel.text = @"启用本页背景色";
        [self wdSwitch:c action:@selector(onSwitch:) on:[p bgEnabledForPage:self.page] enabled:p.master];
        if (!p.master) c.textLabel.textColor = [UIColor secondaryLabelColor];
        return c;
    }
    BOOL dark = (ip.row == 2);
    c.textLabel.text = dark ? @"深色模式" : @"浅色模式";
    NSString *hex = [p bgHexForPage:self.page dark:dark];
    c.detailTextLabel.text = hex.length ? hex : @"未设置";
    [self wdDot:c color:WDColorForHex(hex)];
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (!p.master) {
        c.textLabel.textColor = [UIColor secondaryLabelColor];
        c.userInteractionEnabled = NO;
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    WDPrefs *p = [WDPrefs shared];
    if (!p.master) return;
    if (ip.section == 1) {
        [p resetPage:self.page];
        [tv reloadData];
        return;
    }
    if (ip.row == 0) return;
    self.pickingDark = (ip.row == 2);
    [self openPicker];
}

- (void)onSwitch:(UISwitch *)sw {
    [[WDPrefs shared] setBgEnabled:sw.on forPage:self.page];
    [self.tableView reloadData];
}

- (void)openPicker {
    if (@available(iOS 14.0, *)) {
        WDPrefs *p = [WDPrefs shared];
        UIColorPickerViewController *vc = [[UIColorPickerViewController alloc] init];
        vc.delegate = self;
        vc.supportsAlpha = YES;
        vc.title = self.pickingDark ? @"深色模式背景" : @"浅色模式背景";
        UIColor *cur = WDColorForHex([p bgHexForPage:self.page dark:self.pickingDark]);
        if (cur) vc.selectedColor = cur;
        [self presentViewController:vc animated:YES completion:nil];
        return;
    }
    // iOS 14 以下兜底：手写十六进制
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"背景色"
                                                               message:@"填写 #RRGGBB 或 #AARRGGBB"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = [[WDPrefs shared] bgHexForPage:self.page dark:self.pickingDark] ?: @"";
        tf.placeholder = @"#RRGGBB";
    }];
    __weak typeof(self) ws = self;
    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        NSString *t = a.textFields.firstObject.text ?: @"";
        [[WDPrefs shared] setBgHex:t forPage:ws.page dark:ws.pickingDark];
        [ws.tableView reloadData];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)vc {
    NSString *hex = WDHexForColor(vc.selectedColor);
    if (hex) [[WDPrefs shared] setBgHex:hex forPage:self.page dark:self.pickingDark];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)vc {
    NSString *hex = WDHexForColor(vc.selectedColor);
    if (hex) [[WDPrefs shared] setBgHex:hex forPage:self.page dark:self.pickingDark];
    [self.tableView reloadData];
}

@end

#pragma mark - 根设置页

@implementation WDSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = WD_DISPLAY_NAME;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone
                                        target:self action:@selector(close)];
}

- (void)close {
    [self.view endEditing:YES];
    if (self.presentingViewController) [self dismissViewControllerAnimated:YES completion:nil];
    else [self.navigationController popViewControllerAnimated:YES];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 4;
    if (s == 1) return 4;                 // 四个 Tab 背景色
    if (s == 2) return (NSInteger)WDPageCount;
    return 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"全局";
    if (s == 1) return @"页面背景色";
    if (s == 2) return @"按页面分类设置";
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return [NSString stringWithFormat:@"%@ v%@  ·  微信 8.0.70+ / iOS 14+", WD_DISPLAY_NAME, WD_VERSION];
    if (s == 1) return @"微信首页四个板块的背景色，浅色 / 深色可分别自定义。";
    if (s == 2) return @"按微信页面顺序分类，点进去只看到该页的元素。";
    return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    WDPrefs *p = [WDPrefs shared];
    BOOL master = p.master;

    if (ip.section == 3) {
        WDCell *c = [self wdCell:tv ident:@"r" style:UITableViewCellStyleDefault];
        c.textLabel.text = @"全部恢复默认";
        c.textLabel.textAlignment = NSTextAlignmentCenter;
        c.textLabel.textColor = [UIColor systemRedColor];
        return c;
    }

    if (ip.section == 1) {
        int page = WDPageForTabIndex((int)ip.row);
        WDCell *c = [self wdCell:tv ident:@"bg" style:UITableViewCellStyleValue1];
        c.textLabel.text = WDTabTitle(page);
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        NSString *hex = [p bgHexForPage:page dark:NO];
        c.detailTextLabel.text = [p bgEnabledForPage:page] ? (hex.length ? hex : @"已启用") : @"未启用";
        [self wdDot:c color:WDColorForHex(hex)];
        if (!master) {
            c.textLabel.textColor = [UIColor secondaryLabelColor];
            c.userInteractionEnabled = NO;
        }
        return c;
    }

    if (ip.section == 2) {
        WDCell *c = [self wdCell:tv ident:@"p" style:UITableViewCellStyleValue1];
        c.textLabel.text = WDPageTitle((int)ip.row);
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        NSUInteger n = WDCatalogIndexesForPage((int)ip.row).count;
        c.detailTextLabel.text = [NSString stringWithFormat:@"%lu 项", (unsigned long)n];
        if (!master) {
            c.textLabel.textColor = [UIColor secondaryLabelColor];
            c.userInteractionEnabled = NO;
        }
        return c;
    }

    WDCell *c = [self wdCell:tv ident:@"g" style:UITableViewCellStyleValue1];
    if (ip.row == 0) {
        c.textLabel.text = @"总开关";
        [self wdSwitch:c action:@selector(masterChanged:) on:master enabled:YES];
        return c;
    }
    if (ip.row == 1) {
        c.textLabel.text = @"连续曲率";
        [self wdSwitch:c action:@selector(contChanged:) on:p.continuous enabled:master];
    } else if (ip.row == 2) {
        c.textLabel.text = @"全局圆角";
        [self wdNumber:c value:[NSString stringWithFormat:@"%.0f", p.globalRadius]
           placeholder:@"14" tag:1];
        c.num.enabled = master;
    } else {
        c.textLabel.text = @"全局缩进";
        [self wdNumber:c value:[NSString stringWithFormat:@"%.0f", p.globalInset]
           placeholder:@"12" tag:2];
        c.num.enabled = master;
    }
    if (!master) c.textLabel.textColor = [UIColor secondaryLabelColor];
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (![WDPrefs shared].master && ip.section != 0) return;
    if (ip.section == 1) {
        WDColorController *v = [[WDColorController alloc] initWithStyle:UITableViewStyleGrouped];
        v.page = WDPageForTabIndex((int)ip.row);
        [self.navigationController pushViewController:v animated:YES];
        return;
    }
    if (ip.section == 2) {
        WDClassListController *v = [[WDClassListController alloc] initWithStyle:UITableViewStyleGrouped];
        v.page = (int)ip.row;
        [self.navigationController pushViewController:v animated:YES];
        return;
    }
    if (ip.section == 3) {
        [[WDPrefs shared] resetAll];
        [tv reloadData];
    }
}

- (void)masterChanged:(UISwitch *)sw {
    [WDPrefs shared].master = sw.on;
    [self.tableView reloadData];
}
- (void)contChanged:(UISwitch *)sw {
    [WDPrefs shared].continuous = sw.on;
}
- (void)wdNumberDone:(UITextField *)f {
    [super wdNumberDone:f];
    NSString *raw = [f.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    CGFloat v = [raw floatValue];
    if (v < 0) v = 0;
    if (f.tag == 1) {
        if (v > WD_RADIUS_MAX) v = WD_RADIUS_MAX;
        [WDPrefs shared].globalRadius = v;
    } else {
        if (v > WD_INSET_MAX) v = WD_INSET_MAX;
        [WDPrefs shared].globalInset = v;
    }
}

@end

#pragma mark - 入口

void WDPushSettings(void) {
    UIViewController *top = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (!w.isKeyWindow && w.windowLevel != UIWindowLevelNormal) continue;
        UIViewController *r = w.rootViewController;
        while (r.presentedViewController) r = r.presentedViewController;
        if ([r isKindOfClass:[UINavigationController class]])
            r = [(UINavigationController *)r topViewController];
        if (r) { top = r; if (w.isKeyWindow) break; }
    }
    if (!top) return;
    WDSettingsController *s = [[WDSettingsController alloc] initWithStyle:UITableViewStyleGrouped];
    if (top.navigationController) {
        [top.navigationController pushViewController:s animated:YES];
    } else {
        UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:s];
        nc.modalPresentationStyle = UIModalPresentationFullScreen;
        [top presentViewController:nc animated:YES completion:nil];
    }
}
