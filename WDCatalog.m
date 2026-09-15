#import "WDCatalog.h"
#import <string.h>

static const WDItem kItems[] = {
    // ===== 首页·微信 =====
    {"NewMainFrameCell",                  "MainFrameCell",  "会话行",     WDPageHome,     WDGroupList,   WDKindCell,   16, 12, 1},
    {"MainFrameSectionFoldView",          NULL,             "置顶横幅",   WDPageHome,     WDGroupBanner, WDKindBanner, 14, 12, 1},
    {"MFWebMMBtn",                        NULL,             "网页登录钮", WDPageHome,     WDGroupBanner, WDKindBanner, 14,  0, 1},
    {"MultiDeviceCardView",               NULL,             "多设备卡",   WDPageHome,     WDGroupBanner, WDKindBanner, 14, 12, 1},
    {"WCSearchBar",                       NULL,             "首页搜索",   WDPageHome,     WDGroupSearch, WDKindView,   14, 12, 1},

    // ===== 通讯录 =====
    {"NewContactsItemCell",               NULL,             "联系人行",   WDPageContacts, WDGroupList,   WDKindCell,   14, 12, 1},
    {"NewContactsSearchPanelView",        NULL,             "联系人搜索", WDPageContacts, WDGroupSearch, WDKindView,   14, 12, 1},
    {"BrandProfileItemBaseCell",          NULL,             "公众号行",   WDPageContacts, WDGroupList,   WDKindCell,   14, 12, 1},

    // ===== 发现·朋友圈·视频号 =====
    {"WCListFeedCellView",                NULL,             "朋友圈动态", WDPageDiscover, WDGroupFinder, WDKindView,   12, 10, 1},
    {"WCListTextCellView",                NULL,             "朋友圈文字", WDPageDiscover, WDGroupFinder, WDKindView,   12, 10, 1},
    {"WCListMusicCellViewNew",            NULL,             "朋友圈音乐", WDPageDiscover, WDGroupFinder, WDKindView,   12, 10, 1},
    {"WCContentItemViewTemplateNote",     NULL,             "朋友圈笔记", WDPageDiscover, WDGroupFinder, WDKindView,   12, 10, 1},
    {"WCImageView",                       NULL,             "朋友圈图",   WDPageDiscover, WDGroupFinder, WDKindView,   10,  0, 1},
    {"WCSightView",                       NULL,             "小视频",     WDPageDiscover, WDGroupFinder, WDKindView,   10,  0, 1},
    {"WCFinderFeedStaticCoverView",       NULL,             "视频号封面", WDPageDiscover, WDGroupFinder, WDKindView,   12,  0, 1},
    {"WCFinderFeedImageCDNView",          NULL,             "视频号图",   WDPageDiscover, WDGroupFinder, WDKindView,   12,  0, 1},
    {"WCFinderFeedStaticCoverCollectionViewCell", NULL,     "视频号格",   WDPageDiscover, WDGroupFinder, WDKindView,   12,  0, 1},
    {"WCFinderCommentImageView",          NULL,             "评论图",     WDPageDiscover, WDGroupFinder, WDKindView,   10,  0, 1},
    {"WCFinderHeadImageView",             NULL,             "视频号头像", WDPageDiscover, WDGroupFinder, WDKindView,    0,  0, 1},
    {"WCFinderWXContactEntranceView",     NULL,             "视频号入口", WDPageDiscover, WDGroupFinder, WDKindView,   14, 10, 1},
    {"WCFinderCommentAdTableViewCell",    NULL,             "视频号评论行", WDPageDiscover, WDGroupList, WDKindCell,   14, 12, 1},
    {"WCCommentInputView",                NULL,             "评论输入",   WDPageDiscover, WDGroupInput,  WDKindView,   14, 10, 1},
    {"WCFinderCommentInputBackView",      NULL,             "视频号输入", WDPageDiscover, WDGroupInput,  WDKindView,   14, 10, 1},
    {"TingSharedAudioView",               NULL,             "听一听",     WDPageDiscover, WDGroupFinder, WDKindView,   12, 10, 1},

    // ===== 我 =====
    {"ThirdPartyServiceListCell",         NULL,             "服务行",     WDPageMe,       WDGroupList,   WDKindCell,   14, 12, 0},
    {"StorageDeleteInfoCell",             NULL,             "存储行",     WDPageMe,       WDGroupList,   WDKindCell,   14, 12, 1},
    {"WCFinderMyTabFinderCardView",       NULL,             "我的视频号", WDPageMe,       WDGroupFinder, WDKindView,   16, 12, 1},
    {"BrandMyTabEntranceCardView",        NULL,             "我的公众号", WDPageMe,       WDGroupFinder, WDKindView,   16, 12, 1},
    {"TextStateProfileCardContentView",   NULL,             "我页资料卡", WDPageMe,       WDGroupBanner, WDKindView,   16, 12, 1},

    // ===== 聊天（不碰气泡、不碰聊天行/聊天背景） =====
    {"MMNewMsgContentNavBar",             NULL,             "聊天顶栏",   WDPageChat,     WDGroupNav,    WDKindChrome, 16, 10, 1},
    {"MMMsgContentNavBar",                NULL,             "会话顶栏",   WDPageChat,     WDGroupNav,    WDKindChrome, 16, 10, 1},
    {"MMInputToolView",                   NULL,             "输入工具栏", WDPageChat,     WDGroupTab,    WDKindChrome, 16, 10, 0},
    {"InputToolContainerView",            NULL,             "输入容器",   WDPageChat,     WDGroupTab,    WDKindChrome, 16, 10, 0},
    {"SelectAttachmentView",              NULL,             "附件面板",   WDPageChat,     WDGroupTab,    WDKindView,   16, 10, 1},
    {"QuickReplyMsgNotifyView",           NULL,             "快捷回复条", WDPageChat,     WDGroupBanner, WDKindBanner, 14, 12, 1},
    {"VoIPInvitationBreadthInviteView",   NULL,             "通话邀请条", WDPageChat,     WDGroupBanner, WDKindBanner, 14, 12, 1},
    {"VoIPInvitationBreadthQuickReplyView", NULL,           "通话快捷条", WDPageChat,     WDGroupBanner, WDKindBanner, 14, 12, 1},
    {"MMGrowTextView",                    NULL,             "输入框",     WDPageChat,     WDGroupInput,  WDKindView,   14, 10, 0},
    {"MMGrowTextViewWithExtras",          NULL,             "扩展输入框", WDPageChat,     WDGroupInput,  WDKindView,   14, 10, 0},
    {"MMInputMsgReferView",               NULL,             "引用条",     WDPageChat,     WDGroupInput,  WDKindView,   12, 10, 1},
    {"SharePreConfirmSheetView",          NULL,             "转发确认",   WDPageChat,     WDGroupSheet,  WDKindView,   16, 12, 1},
    {"SharePreConfirmHeadView",           NULL,             "转发头",     WDPageChat,     WDGroupSheet,  WDKindView,   14, 12, 1},
    {"SharePreConfirmSuccessView",        NULL,             "转发成功",   WDPageChat,     WDGroupSheet,  WDKindView,   16, 12, 1},
    {"WCRedEnvelopesReceiveHomeView",     NULL,             "红包封面",   WDPageChat,     WDGroupSheet,  WDKindView,   18, 16, 1},
    {"MsgFileBrowseItemView",             NULL,             "文件浏览项", WDPageChat,     WDGroupSheet,  WDKindView,   12, 10, 1},
    {"FavRecordReferView",                NULL,             "收藏引用",   WDPageChat,     WDGroupSheet,  WDKindView,   12, 10, 1},

    // ===== 搜索 =====
    {"MMUISearchBar",                     NULL,             "微信搜索",   WDPageSearch,   WDGroupSearch, WDKindView,   14, 12, 1},
    {"FavSearchBar",                      NULL,             "收藏搜索",   WDPageSearch,   WDGroupSearch, WDKindView,   14, 12, 1},
    {"WAMainFrameTaskBarSearchBar",       NULL,             "小程序搜索", WDPageSearch,   WDGroupSearch, WDKindView,   14, 12, 1},

    // ===== 钱包·支付 =====
    {"WCPayWalletEntryHeaderView",        NULL,             "钱包头",     WDPagePay,      WDGroupPay,    WDKindView,   16, 12, 1},
    {"WCPayWalletDecorationView",         NULL,             "钱包装饰",   WDPagePay,      WDGroupPay,    WDKindView,   14, 12, 0},
    {"WCPayWalletBusinessSectionHeader",  NULL,             "钱包分区",   WDPagePay,      WDGroupPay,    WDKindView,   10, 12, 0},
    {"WCPayWalletBusinessCell",           NULL,             "钱包行",     WDPagePay,      WDGroupList,   WDKindCell,   14, 12, 0},
    {"WCPayDecimalKeyboardView",          NULL,             "金额键盘",   WDPagePay,      WDGroupPay,    WDKindView,   16,  8, 1},
    {"WCPayFaceHBPayView",                NULL,             "面对面红包", WDPagePay,      WDGroupPay,    WDKindView,   16, 12, 1},

    // ===== 通用·浮层 =====
    {"MMUINavigationBar",                 NULL,             "顶栏",       WDPageCommon,   WDGroupNav,    WDKindChrome, 16, 10, 1},
    {"MMTabBar",                          NULL,             "底栏",       WDPageCommon,   WDGroupTab,    WDKindChrome, 18, 12, 1},
    {"MMSnackBarView",                    NULL,             "横幅条",     WDPageCommon,   WDGroupBanner, WDKindBanner, 14, 12, 1},
    {"StrongNotificationContentView",     NULL,             "强通知条",   WDPageCommon,   WDGroupBanner, WDKindBanner, 14, 12, 1},
    {"TipsView",                          NULL,             "提示条",     WDPageCommon,   WDGroupBanner, WDKindBanner, 12, 12, 1},
    {"MMTableViewCell",                   NULL,             "通用行",     WDPageCommon,   WDGroupList,   WDKindCell,   14, 12, 1},
    {"MMMultiMenuTableViewCell",          NULL,             "滑动行",     WDPageCommon,   WDGroupList,   WDKindCell,   14, 12, 1},
    {"MMTableSectionHeaderView",          NULL,             "区头",       WDPageCommon,   WDGroupHeader, WDKindView,    0,  0, 1},
    {"MMToastView",                       NULL,             "轻提示",     WDPageCommon,   WDGroupToast,  WDKindView,   12,  0, 1},
    {"MMMenuContentView",                 NULL,             "长按菜单",   WDPageCommon,   WDGroupToast,  WDKindView,   14,  0, 1},
    {"MMActionSheetQRCodeRowView",        NULL,             "二维码行",   WDPageCommon,   WDGroupToast,  WDKindView,   12, 10, 1},
    {"MiniTaskCollectionBaseCell",        NULL,             "浮窗卡",     WDPageCommon,   WDGroupSheet,  WDKindView,   14, 10, 1},
    {"WeappToolItemView",                 NULL,             "小程序工具", WDPageCommon,   WDGroupSheet,  WDKindView,   12,  8, 1},
    {"CardImageView",                     NULL,             "卡片图",     WDPageCommon,   WDGroupSheet,  WDKindView,   12,  0, 1},
};

const WDItem *WDCatalogItems(void) { return kItems; }
int WDCatalogCount(void) { return (int)(sizeof(kItems) / sizeof(kItems[0])); }

int WDCatalogIndexOf(NSString *className) {
    if (!className.length) return -1;
    const char *c = className.UTF8String;
    int n = WDCatalogCount();
    for (int i = 0; i < n; i++) {
        if (strcmp(kItems[i].cls, c) == 0) return i;
        if (kItems[i].alias && strcmp(kItems[i].alias, c) == 0) return i;
    }
    return -1;
}

const WDItem *WDCatalogFind(NSString *className) {
    int i = WDCatalogIndexOf(className);
    return i >= 0 ? &kItems[i] : NULL;
}

NSString *WDGroupTitle(int group) {
    switch (group) {
        case WDGroupNav:    return @"顶栏";
        case WDGroupTab:    return @"底栏";
        case WDGroupBanner: return @"横幅";
        case WDGroupSearch: return @"搜索";
        case WDGroupList:   return @"列表";
        case WDGroupHeader: return @"区头";
        case WDGroupInput:  return @"输入";
        case WDGroupToast:  return @"提示";
        case WDGroupSheet:  return @"弹层";
        case WDGroupFinder: return @"视频号/朋友圈";
        case WDGroupPay:    return @"钱包";
        default:            return @"其他";
    }
}

NSString *WDPageTitle(int page) {
    switch (page) {
        case WDPageHome:     return @"首页 · 微信";
        case WDPageContacts: return @"通讯录";
        case WDPageDiscover: return @"发现 · 朋友圈 · 视频号";
        case WDPageMe:       return @"我";
        case WDPageChat:     return @"聊天";
        case WDPageSearch:   return @"搜索";
        case WDPagePay:      return @"钱包 · 支付";
        case WDPageCommon:   return @"通用 · 浮层";
        default:             return @"其他";
    }
}

NSArray<NSNumber *> *WDCatalogIndexesForPage(int page) {
    NSMutableArray *a = [NSMutableArray array];
    int n = WDCatalogCount();
    for (int i = 0; i < n; i++) {
        if (kItems[i].page == page) [a addObject:@(i)];
    }
    return a;
}

