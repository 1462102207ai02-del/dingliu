// WechatDuo — 微信全页面卡片化
// 视觉：连续圆角 + 列表卡片底板缩进。热路径不写 frame / 不设 mask / 不分配 NSString。

#ifndef WDCommon_h
#define WDCommon_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define WD_VERSION_C    "1.0.3"
#define WD_VERSION      @WD_VERSION_C
#define WD_DISPLAY_NAME @"WechatDuo"
#define WD_SETTINGS_CLS @"WDSettingsController"
#define WD_LOG_NAME     @"WechatDuo.log"

typedef NS_ENUM(NSInteger, WDGroup) {
    WDGroupNav     = 0,
    WDGroupTab     = 1,
    WDGroupBanner  = 2,
    WDGroupSearch  = 3,
    WDGroupList    = 4,
    WDGroupHeader  = 5,
    WDGroupInput   = 6,
    WDGroupBubble  = 7,
    WDGroupToast   = 8,
    WDGroupSheet   = 9,
    WDGroupFinder  = 10,
    WDGroupPay     = 11,
    WDGroupCount   = 12
};

typedef NS_ENUM(NSInteger, WDKind) {
    WDKindChrome = 0,
    WDKindBanner = 1,
    WDKindCell   = 2,
    WDKindView   = 3,
    WDKindBubble = 4
};

typedef struct {
    const char *cls;
    const char *zh;
    int group;
    int kind;
    float defRadius;
    float defInset;
    int   defOn;
} WDItem;

#endif
