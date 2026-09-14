#ifndef WDSettings_h
#define WDSettings_h

#import <UIKit/UIKit.h>

@interface WDCell : UITableViewCell
@property (nonatomic, strong) UISwitch *sw;
@property (nonatomic, strong) UITextField *num;
@property (nonatomic, strong) UIView *dot;
@end

@interface WDListController : UITableViewController
- (WDCell *)wdCell:(UITableView *)tv ident:(NSString *)rid style:(UITableViewCellStyle)st;
- (UISwitch *)wdSwitch:(WDCell *)c action:(SEL)a on:(BOOL)on enabled:(BOOL)enabled;
- (UITextField *)wdNumber:(WDCell *)c value:(NSString *)v placeholder:(NSString *)ph tag:(NSInteger)tag;
- (UIView *)wdDot:(WDCell *)c color:(UIColor *)color;
- (void)wdNumberDone:(UITextField *)f;
@end

@interface WDSettingsController : WDListController <UIDocumentPickerDelegate, UIColorPickerViewControllerDelegate>
@end

void WDPushSettings(void);

#endif
