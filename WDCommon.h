// WechatDuo — 微信全页面卡片化
// v1.1.5：打孔遮罩不改内容坐标；置顶横幅可点；聊天背景/气泡不动；搜索栏跟首页缩进。
//
// 视觉：连续圆角 + 分区级卡片（双侧缩进，只有首尾四角）。
// 热路径约束：不设 layer.mask、不写 content frame、不分配 NSString。

#ifndef WDCommon_h
#define WDCommon_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define WD_VERSION_C    "1.1.5"
#define WD_VERSION      @WD_VERSION_C
#define WD_DISPLAY_NAME @"WechatDuo"
#define WD_SETTINGS_CLS @"WDSettingsController"
#define WD_LOG_NAME     @"WechatDuo.log"

// 设置项分类：按微信页面顺序排列
typedef NS_ENUM(NSInteger, WDPage) {
    WDPageHome     = 0,   // 首页·微信
    WDPageContacts = 1,   // 通讯录
    WDPageDiscover = 2,   // 发现·朋友圈·视频号
    WDPageMe       = 3,   // 我
    WDPageChat     = 4,   // 聊天
    WDPageSearch   = 5,   // 搜索
    WDPagePay      = 6,   // 钱包·支付
    WDPageCommon   = 7,   // 通用·浮层
    WDPageCount    = 8
};

// 元素类型（详情页展示用）
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
    const char *cls;    // 主类名
    const char *alias;  // 备选类名（版本间改名），可空
    const char *zh;     // 中文简称
    int page;           // 所属页面（WDPage）
    int group;          // 元素类型（WDGroup）
    int kind;           // 装饰方式（WDKind）
    float defRadius;
    float defInset;
    int   defOn;
} WDItem;

// 四个 Tab（微信 / 通讯录 / 发现 / 我）→ 页面编号
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
