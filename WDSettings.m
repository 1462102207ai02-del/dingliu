#import "WDSettings.h"
#import "WDPrefs.h"
#import "WDCatalog.h"

@interface WDClassDetailController : UITableViewController
@property (nonatomic, copy) NSString *className;
@property (nonatomic, assign) const WDItem *item;
@end

@implementation WDClassDetailController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [NSString stringWithUTF8String:self.item->zh];
    self.tableView.rowHeight = 52;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 0 ? 3 : 1;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? [NSString stringWithFormat:@"%s  ·  %s", self.item->zh, self.item->cls] : @" ";
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return @"半径 / 缩进留空则跟随全局。气泡默认不缩进。";
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"d"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"d"];
    c.accessoryView = nil;
    c.accessoryType = UITableViewCellAccessoryNone;
    c.detailTextLabel.text = nil;
    c.textLabel.textColor = [UIColor labelColor];
    WDPrefs *p = [WDPrefs shared];
    NSString *name = self.className;
    if (ip.section == 1) {
        c.textLabel.text = @"恢复本类默认";
        c.textLabel.textColor = [UIColor systemRedColor];
        return c;
    }
    if (ip.row == 0) {
        c.textLabel.text = @"启用";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [p enabledForClass:name def:self.item->defOn != 0];
        [sw addTarget:self action:@selector(onSwitch:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
        return c;
    }
    UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 160, 30)];
    sl.minimumValue = 0;
    sl.maximumValue = ip.row == 1 ? 32 : 28;
    sl.continuous = YES;
    [sl addTarget:self action:@selector(onSlider:) forControlEvents:UIControlEventValueChanged];
    if (ip.row == 1) {
        c.textLabel.text = @"圆角";
        sl.tag = 1;
        sl.value = [p radiusForClass:name def:self.item->defRadius];
        c.detailTextLabel.text = [NSString stringWithFormat:@"%.0f", sl.value];
    } else {
        c.textLabel.text = @"双侧缩进";
        sl.tag = 2;
        sl.value = [p insetForClass:name def:self.item->defInset];
        c.detailTextLabel.text = [NSString stringWithFormat:@"%.0f", sl.value];
    }
    c.accessoryView = sl;
    return c;
}
- (void)onSwitch:(UISwitch *)sw {
    [[WDPrefs shared] setEnabled:sw.on forClass:self.className];
}
- (void)onSlider:(UISlider *)sl {
    if (sl.tag == 1) [[WDPrefs shared] setRadius:sl.value forClass:self.className];
    else [[WDPrefs shared] setInset:sl.value forClass:self.className];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:sl.tag inSection:0]]
                          withRowAnimation:UITableViewRowAnimationNone];
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1) {
        [[WDPrefs shared] resetClass:self.className];
        [tv reloadData];
    }
}
@end

@implementation WDSettingsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = WD_DISPLAY_NAME;
    self.tableView.rowHeight = 48;
    if (@available(iOS 13.0, *)) {
        self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    }
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone
                                        target:self action:@selector(close)];
}
- (void)close {
    if (self.presentingViewController) [self dismissViewControllerAnimated:YES completion:nil];
    else [self.navigationController popViewControllerAnimated:YES];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return 2 + WDGroupCount; // 全局 + 12 分组 + 重置
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 4;
    if (s == WDGroupCount + 1) return 1;
    return WDCatalogIndexesForGroup((int)(s - 1)).count;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"全局";
    if (s == WDGroupCount + 1) return @" ";
    return WDGroupTitle((int)(s - 1));
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return [NSString stringWithFormat:@"%@ v%@  ·  微信 8.0.70+ / iOS 14+", WD_DISPLAY_NAME, WD_VERSION];
    if (s == WDGroupCount + 1) return @"每个类都有独立开关、圆角、双侧缩进。改完回到页面即时生效。";
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    WDPrefs *p = [WDPrefs shared];
    if (ip.section == 0) {
        UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"g"];
        if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"g"];
        c.accessoryView = nil;
        c.accessoryType = UITableViewCellAccessoryNone;
        c.detailTextLabel.text = nil;
        if (ip.row == 0) {
            c.textLabel.text = @"总开关";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = p.master;
            [sw addTarget:self action:@selector(masterChanged:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
        } else if (ip.row == 1) {
            c.textLabel.text = @"连续曲率";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = p.continuous;
            [sw addTarget:self action:@selector(contChanged:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
        } else if (ip.row == 2) {
            c.textLabel.text = @"全局圆角";
            UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 150, 30)];
            sl.minimumValue = 0; sl.maximumValue = 32; sl.value = p.globalRadius; sl.tag = 1;
            [sl addTarget:self action:@selector(globalSlider:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sl;
            c.detailTextLabel.text = [NSString stringWithFormat:@"%.0f", p.globalRadius];
        } else {
            c.textLabel.text = @"全局缩进";
            UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 150, 30)];
            sl.minimumValue = 0; sl.maximumValue = 28; sl.value = p.globalInset; sl.tag = 2;
            [sl addTarget:self action:@selector(globalSlider:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sl;
            c.detailTextLabel.text = [NSString stringWithFormat:@"%.0f", p.globalInset];
        }
        return c;
    }
    if (ip.section == WDGroupCount + 1) {
        UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"r"];
        if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"r"];
        c.textLabel.text = @"全部恢复默认";
        c.textLabel.textColor = [UIColor systemRedColor];
        c.textLabel.textAlignment = NSTextAlignmentCenter;
        return c;
    }
    NSArray *idxs = WDCatalogIndexesForGroup((int)(ip.section - 1));
    const WDItem *it = &WDCatalogItems()[[idxs[ip.row] intValue]];
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    c.textLabel.text = [NSString stringWithUTF8String:it->zh];
    c.detailTextLabel.text = @(it->cls);
    c.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = [p enabledForClass:@(it->cls) def:it->defOn != 0];
    sw.tag = [idxs[ip.row] intValue];
    [sw addTarget:self action:@selector(classSwitch:) forControlEvents:UIControlEventValueChanged];
    c.accessoryView = sw;
    return c;
}
- (void)masterChanged:(UISwitch *)sw { [WDPrefs shared].master = sw.on; }
- (void)contChanged:(UISwitch *)sw { [WDPrefs shared].continuous = sw.on; }
- (void)globalSlider:(UISlider *)sl {
    if (sl.tag == 1) [WDPrefs shared].globalRadius = sl.value;
    else [WDPrefs shared].globalInset = sl.value;
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:sl.tag + 1 inSection:0]]
                          withRowAnimation:UITableViewRowAnimationNone];
}
- (void)classSwitch:(UISwitch *)sw {
    const WDItem *it = &WDCatalogItems()[(int)sw.tag];
    [[WDPrefs shared] setEnabled:sw.on forClass:@(it->cls)];
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) return;
    if (ip.section == WDGroupCount + 1) {
        [[WDPrefs shared] resetAll];
        [tv reloadData];
        return;
    }
    NSArray *idxs = WDCatalogIndexesForGroup((int)(ip.section - 1));
    const WDItem *it = &WDCatalogItems()[[idxs[ip.row] intValue]];
    WDClassDetailController *d = [[WDClassDetailController alloc] initWithStyle:UITableViewStyleGrouped];
    d.className = @(it->cls);
    d.item = it;
    [self.navigationController pushViewController:d animated:YES];
}
@end

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
