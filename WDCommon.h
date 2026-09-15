#ifndef WDCommon_h
#define WDCommon_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define WD_VERSION_C    "1.1.21"
#define WD_VERSION      @WD_VERSION_C
#define WD_DISPLAY_NAME @"WechatDuo"
#define WD_SETTINGS_CLS @"WDSettingsController"
#define WD_LOG_NAME     @"WechatDuo.log"

typedef NS_ENUM(NSInteger, WDPage) {
    WDPageHome     = 0,
    WDPageContacts = 1,
    WDPageDiscover = 2,
    WDPageMe       = 3,
    WDPageChat     = 4,
    WDPageSearch   = 5,
    WDPagePay      = 6,
    WDPageCommon   = 7,
    WDPageCount    = 8
};

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
    const char *alias;
    const char *zh;
    int page;
    int group;
    int kind;
    float defRadius;
    float defInset;
    int   defOn;
} WDItem;

static inline int WDPageForTabIndex(int tabIndex) {
    switch (tabIndex) {
        case 0: return (int)WDPageHome;
        case 1: return (int)WDPageContacts;
        case 2: return (int)WDPageDiscover;
        case 3: return (int)WDPageMe;
        default: return -1;
    }
}

#endif
