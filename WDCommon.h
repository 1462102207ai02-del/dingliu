// WechatDuo — 微信全页面卡片化
// 视觉策略：连续圆角 + 双侧缩进（相对父视图宽度重算，绝不累加）+ 卡片底板
// 不依赖 Substrate / Logos，纯 runtime，TrollFools 裸 dylib。

#ifndef WDCommon_h
#define WDCommon_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define WD_VERSION      @"1.0.1"
#define WD_DISPLAY_NAME @"WechatDuo"
#define WD_SETTINGS_CLS @"WDSettingsController"
#define WD_LOG_NAME     @"WechatDuo.log"

typedef NS_ENUM(NSInteger, WDGroup) {
    WDGroupNav     = 0,  // 顶栏
    WDGroupTab     = 1,  // 底栏
    WDGroupBanner  = 2,  // 横幅
    WDGroupSearch  = 3,  // 搜索
    WDGroupList    = 4,  // 列表
    WDGroupHeader  = 5,  // 区头
    WDGroupInput   = 6,  // 输入
    WDGroupBubble  = 7,  // 气泡
    WDGroupToast   = 8,  // 提示
    WDGroupSheet   = 9,  // 弹层
    WDGroupFinder  = 10, // 视频号
    WDGroupPay     = 11, // 钱包
    WDGroupCount   = 12
};

typedef NS_ENUM(NSInteger, WDKind) {
    WDKindChrome = 0,  // 顶栏/底栏/输入栏：相对 window/superview 缩进
    WDKindBanner = 1,  // 横幅/通知条
    WDKindCell   = 2,  // 列表 cell：按 section 位置切圆角
    WDKindView   = 3,  // 普通视图：自身圆角 + 可选缩进
    WDKindBubble = 4   // 气泡：只圆角不缩进（避免把气泡挤扁）
};

typedef struct {
    const char *cls;
    const char *zh;
    int group;
    int kind;
    float defRadius;   // 0 = 跟随全局
    float defInset;    // 0 = 跟随全局；气泡默认 0
    int   defOn;       // 1 默认开
} WDItem;

#endif
