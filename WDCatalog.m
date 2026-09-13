#import "WDCatalog.h"
#import <string.h>

// 每条都有中文简称。defRadius/defInset = 0 表示跟随全局。
// 气泡默认不缩进；顶栏/底栏/横幅默认半径略大于列表。
static const WDItem kItems[] = {
    // ===== 顶栏 =====
    {"MMUINavigationBar",                 "顶栏",         WDGroupNav,    WDKindChrome, 16, 10, 1},
    {"MMNewMsgContentNavBar",             "聊天顶栏",     WDGroupNav,    WDKindChrome, 16, 10, 1},
    {"MMMsgContentNavBar",                "会话顶栏",     WDGroupNav,    WDKindChrome, 16, 10, 1},
    {"WCSearchViewController",            "搜索顶栏",     WDGroupNav,    WDKindView,   14, 10, 1},

    // ===== 底栏 =====
    {"MMTabBar",                          "底栏",         WDGroupTab,    WDKindChrome, 18, 12, 1},
    {"MMInputToolView",                   "输入工具栏",   WDGroupTab,    WDKindChrome, 16, 10, 1},
    {"InputToolContainerView",            "输入容器",     WDGroupTab,    WDKindChrome, 16, 10, 1},
    {"SelectAttachmentView",              "附件面板",     WDGroupTab,    WDKindView,   16, 10, 1},

    // ===== 横幅 =====
    {"MainFrameSectionFoldView",          "折叠横幅",     WDGroupBanner, WDKindBanner, 14, 12, 1},
    {"MMSnackBarView",                    "横幅条",       WDGroupBanner, WDKindBanner, 14, 12, 1},
    {"QuickReplyMsgNotifyView",           "快捷回复条",   WDGroupBanner, WDKindBanner, 14, 12, 1},
    {"StrongNotificationContentView",     "强通知条",     WDGroupBanner, WDKindBanner, 14, 12, 1},
    {"VoIPInvitationBreadthInviteView",    "通话邀请条",   WDGroupBanner, WDKindBanner, 14, 12, 1},
    {"VoIPInvitationBreadthQuickReplyView","通话快捷条",   WDGroupBanner, WDKindBanner, 14, 12, 1},
    {"TipsView",                          "提示条",       WDGroupBanner, WDKindBanner, 12, 12, 1},
    {"MultiDeviceCardView",               "多设备卡",     WDGroupBanner, WDKindBanner, 14, 12, 1},

    // ===== 搜索 =====
    {"WCSearchBar",                       "首页搜索",     WDGroupSearch, WDKindView,   14, 12, 1},
    {"UISearchBar",                       "系统搜索",     WDGroupSearch, WDKindView,   14, 12, 1},
    {"MMUISearchBar",                     "微信搜索",     WDGroupSearch, WDKindView,   14, 12, 1},
    {"FavSearchBar",                      "收藏搜索",     WDGroupSearch, WDKindView,   14, 12, 1},
    {"WAMainFrameTaskBarSearchBar",       "小程序搜索",   WDGroupSearch, WDKindView,   14, 12, 1},
    {"NewContactsSearchPanelView",        "联系人搜索",   WDGroupSearch, WDKindView,   14, 12, 1},
    {"UISearchBarTextField",              "搜索输入",     WDGroupSearch, WDKindView,   12,  0, 1},

    // ===== 列表 / 单元格 =====
    {"NewMainFrameCell",                  "会话行",       WDGroupList,   WDKindCell,   16, 12, 1},
    {"ChatTableViewCell",                 "聊天行",       WDGroupList,   WDKindCell,   16, 12, 1},
    {"MMTableViewCell",                   "通用行",       WDGroupList,   WDKindCell,   14, 12, 1},
    {"MMMultiMenuTableViewCell",          "滑动行",       WDGroupList,   WDKindCell,   14, 12, 1},
    {"UITableViewCell",                   "系统行",       WDGroupList,   WDKindCell,   14, 12, 1},
    {"ChatRoomInvitationMultiMenuTableViewCell","群邀请行", WDGroupList, WDKindCell,   14, 12, 1},
    {"ThirdPartyServiceListCell",         "服务行",       WDGroupList,   WDKindCell,   14, 12, 1},
    {"BrandProfileItemBaseCell",          "公众号行",     WDGroupList,   WDKindCell,   14, 12, 1},
    {"WCPayWalletBusinessCell",           "钱包行",       WDGroupList,   WDKindCell,   14, 12, 1},
    {"StorageDeleteInfoCell",             "存储行",       WDGroupList,   WDKindCell,   14, 12, 1},
    {"WCFinderCommentAdTableViewCell",    "视频号评论行", WDGroupList,   WDKindCell,   14, 12, 1},
    {"MMTableView",                       "微信表",       WDGroupList,   WDKindView,    0,  0, 0},
    {"WCTableView",                       "设置表",       WDGroupList,   WDKindView,    0,  0, 0},
    {"UITableView",                       "系统表",       WDGroupList,   WDKindView,    0,  0, 0},

    // ===== 区头 =====
    {"MMTableSectionHeaderView",          "区头",         WDGroupHeader, WDKindView,   10, 12, 1},
    {"UITableViewHeaderFooterView",       "系统区头",     WDGroupHeader, WDKindView,   10, 12, 1},

    // ===== 输入 =====
    {"MMGrowTextView",                    "输入框",       WDGroupInput,  WDKindView,   14, 10, 1},
    {"MMGrowTextViewWithExtras",          "扩展输入框",   WDGroupInput,  WDKindView,   14, 10, 1},
    {"MMInputMsgReferView",               "引用条",       WDGroupInput,  WDKindView,   12, 10, 1},
    {"WCCommentInputView",                "评论输入",     WDGroupInput,  WDKindView,   14, 10, 1},
    {"WCFinderCommentInputBackView",      "视频号输入",   WDGroupInput,  WDKindView,   14, 10, 1},

    // ===== 气泡 =====
    {"TextMessageCellView",               "文字气泡",     WDGroupBubble, WDKindBubble, 16,  0, 1},
    {"CommonMessageCellView",             "通用气泡",     WDGroupBubble, WDKindBubble, 16,  0, 1},
    {"VoiceMessageCellView",              "语音气泡",     WDGroupBubble, WDKindBubble, 16,  0, 1},
    {"ImageMessageCellView",              "图片气泡",     WDGroupBubble, WDKindBubble, 12,  0, 1},
    {"VideoMessageCellView",              "视频气泡",     WDGroupBubble, WDKindBubble, 12,  0, 1},
    {"AppFileMessageCellView",            "文件气泡",     WDGroupBubble, WDKindBubble, 14,  0, 1},
    {"AppFileMessageCellViewV2",          "文件气泡2",    WDGroupBubble, WDKindBubble, 14,  0, 1},
    {"AppRecordMessageCellView",          "记录气泡",     WDGroupBubble, WDKindBubble, 14,  0, 1},
    {"AppRecordMessageCellViewClassic",   "记录气泡经",   WDGroupBubble, WDKindBubble, 14,  0, 1},
    {"AppNoteMessageCellView",            "笔记气泡",     WDGroupBubble, WDKindBubble, 14,  0, 1},
    {"AppNoteMessageCellViewClassic",     "笔记气泡经",   WDGroupBubble, WDKindBubble, 14,  0, 1},
    {"AppUrlMessageCellViewClassic",      "链接气泡",     WDGroupBubble, WDKindBubble, 14,  0, 1},
    {"AppUrlMessageImageView",            "链接图",       WDGroupBubble, WDKindBubble, 10,  0, 1},
    {"AppPatMessageCellView",             "拍一拍",       WDGroupBubble, WDKindBubble, 12,  0, 1},
    {"AppMMScheduleMessageCellView",      "日程气泡",     WDGroupBubble, WDKindBubble, 14,  0, 1},
    {"AppWxGameCardMessageCellView",      "游戏卡",       WDGroupBubble, WDKindBubble, 14,  0, 1},
    {"ReaderMessageCellView",             "图文气泡",     WDGroupBubble, WDKindBubble, 14,  0, 1},
    {"MultiReaderMessageCellView",        "多图文",       WDGroupBubble, WDKindBubble, 14,  0, 1},
    {"MultiColumnReaderMessageCellView",  "多列图文",     WDGroupBubble, WDKindBubble, 14,  0, 1},
    {"TextReaderMessageCellView",         "文字图文",     WDGroupBubble, WDKindBubble, 14,  0, 1},
    {"ReaderItemView",                    "图文项",       WDGroupBubble, WDKindBubble, 12,  0, 1},
    {"BizAppBaseMessageCellView",         "公众号气泡",   WDGroupBubble, WDKindBubble, 14,  0, 1},
    {"BizAppReaderMessageBigPicView",     "公众号大图",   WDGroupBubble, WDKindBubble, 12,  0, 1},
    {"MailMessageCellView",               "邮件气泡",     WDGroupBubble, WDKindBubble, 14,  0, 1},
    {"ChatTimeCellView",                  "时间条",       WDGroupBubble, WDKindView,   10, 40, 1},
    {"MsgMediaGroupCard",                 "媒体组卡",     WDGroupBubble, WDKindView,   14, 10, 1},
    {"WAAppPageCellView",                 "小程序卡",     WDGroupBubble, WDKindView,   14, 10, 1},
    {"WCFinderShareFeedCellView",         "视频号分享",   WDGroupBubble, WDKindView,   14, 10, 1},
    {"WCFinderShareLiveCellView",         "直播分享",     WDGroupBubble, WDKindView,   14, 10, 1},
    {"NotifyLiveImageMessageCellView",    "直播通知",     WDGroupBubble, WDKindView,   14, 10, 1},
    {"AppHardWareRankMessageCellView",    "硬件排行",     WDGroupBubble, WDKindView,   14, 10, 1},
    {"WCPayRecepictReaderMessageCellView","支付回执",     WDGroupBubble, WDKindView,   14, 10, 1},

    // ===== 提示 / 菜单 =====
    {"MMToastView",                       "轻提示",       WDGroupToast,  WDKindView,   12,  0, 1},
    {"MMMenuContentView",                 "长按菜单",     WDGroupToast,  WDKindView,   14,  0, 1},
    {"MMActionSheetQRCodeRowView",        "二维码行",     WDGroupToast,  WDKindView,   12, 10, 1},

    // ===== 弹层 =====
    {"SharePreConfirmSheetView",          "转发确认",     WDGroupSheet,  WDKindView,   16, 12, 1},
    {"SharePreConfirmHeadView",           "转发头",       WDGroupSheet,  WDKindView,   14, 12, 1},
    {"SharePreConfirmSuccessView",        "转发成功",     WDGroupSheet,  WDKindView,   16, 12, 1},
    {"WCRedEnvelopesReceiveHomeView",     "红包封面",     WDGroupSheet,  WDKindView,   18, 16, 1},
    {"MiniTaskCollectionBaseCell",        "浮窗卡",       WDGroupSheet,  WDKindView,   14, 10, 1},
    {"WeappToolItemView",                 "小程序工具",   WDGroupSheet,  WDKindView,   12,  8, 1},
    {"FavRecordReferView",                "收藏引用",     WDGroupSheet,  WDKindView,   12, 10, 1},
    {"MsgFileBrowseItemView",             "文件浏览项",   WDGroupSheet,  WDKindView,   12, 10, 1},
    {"CardImageView",                     "卡片图",       WDGroupSheet,  WDKindView,   12,  0, 1},

    // ===== 视频号 / 朋友圈 =====
    {"WCFinderFeedStaticCoverView",       "视频号封面",   WDGroupFinder, WDKindView,   12,  0, 1},
    {"WCFinderFeedImageCDNView",          "视频号图",     WDGroupFinder, WDKindView,   12,  0, 1},
    {"WCFinderFeedStaticCoverCollectionViewCell","视频号格", WDGroupFinder, WDKindView, 12, 0, 1},
    {"WCFinderCommentImageView",          "评论图",       WDGroupFinder, WDKindView,   10,  0, 1},
    {"WCFinderHeadImageView",             "视频号头像",   WDGroupFinder, WDKindView,    0,  0, 1},
    {"WCFinderWXContactEntranceView",     "视频号入口",   WDGroupFinder, WDKindView,   14, 10, 1},
    {"WCFinderMyTabFinderCardView",       "我的视频号",   WDGroupFinder, WDKindView,   16, 12, 1},
    {"BrandMyTabEntranceCardView",        "我的公众号",   WDGroupFinder, WDKindView,   16, 12, 1},
    {"WCListFeedCellView",                "朋友圈动态",   WDGroupFinder, WDKindView,   12, 10, 1},
    {"WCListTextCellView",                "朋友圈文字",   WDGroupFinder, WDKindView,   12, 10, 1},
    {"WCListMusicCellViewNew",            "朋友圈音乐",   WDGroupFinder, WDKindView,   12, 10, 1},
    {"WCContentItemViewTemplateNote",     "朋友圈笔记",   WDGroupFinder, WDKindView,   12, 10, 1},
    {"WCImageView",                       "朋友圈图",     WDGroupFinder, WDKindView,   10,  0, 1},
    {"WCSightView",                       "小视频",       WDGroupFinder, WDKindView,   10,  0, 1},
    {"TingSharedAudioView",               "听一听",       WDGroupFinder, WDKindView,   12, 10, 1},

    // ===== 钱包 =====
    {"WCPayWalletEntryHeaderView",        "钱包头",       WDGroupPay,    WDKindView,   16, 12, 1},
    {"WCPayWalletDecorationView",         "钱包装饰",     WDGroupPay,    WDKindView,   14, 12, 1},
    {"WCPayWalletBusinessSectionHeader",  "钱包分区",     WDGroupPay,    WDKindView,   10, 12, 1},
    {"WCPayDecimalKeyboardView",          "金额键盘",     WDGroupPay,    WDKindView,   16,  8, 1},
    {"WCPayFaceHBPayView",                "面对面红包",   WDGroupPay,    WDKindView,   16, 12, 1},
};

const WDItem *WDCatalogItems(void) { return kItems; }
int WDCatalogCount(void) { return (int)(sizeof(kItems) / sizeof(kItems[0])); }

const WDItem *WDCatalogFind(NSString *className) {
    if (!className.length) return NULL;
    const char *c = className.UTF8String;
    int n = WDCatalogCount();
    for (int i = 0; i < n; i++) {
        if (strcmp(kItems[i].cls, c) == 0) return &kItems[i];
    }
    return NULL;
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
        case WDGroupBubble: return @"气泡";
        case WDGroupToast:  return @"提示";
        case WDGroupSheet:  return @"弹层";
        case WDGroupFinder: return @"视频号/朋友圈";
        case WDGroupPay:    return @"钱包";
        default:            return @"其他";
    }
}

NSArray<NSNumber *> *WDCatalogIndexesForGroup(int group) {
    NSMutableArray *a = [NSMutableArray array];
    int n = WDCatalogCount();
    for (int i = 0; i < n; i++) {
        if (kItems[i].group == group) [a addObject:@(i)];
    }
    return a;
}
