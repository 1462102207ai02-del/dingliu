# WechatDuo

微信 8.0.70+ 全页面卡片化插件。TrollStore + TrollFools 注入用裸 dylib。

- Bundle ID：`com.tencent.xin` / `com.tencent.qy.xin` / `com.tencent.mm.xin` / `com.tencent.wx`
- iOS 14.0+
- 顶栏 / 底栏 / 横幅 / 列表 / 搜索 / 输入 / 弹层 / 视频号 / 钱包
- 不调整会话气泡与聊天窗口背景
- 每个类有中文简称，可单独开关、改圆角、改双侧缩进
- 接入「插件收纳」：`MinimizeViewController` → `WCPluginsMgr`

## 设置项结构（v1.1.13）

- **总开关**：单独一行「启用 WechatDuo」
- **全局**：连续曲率 / 全局圆角 / 全局缩进 / 卡片内背景色 / 卡片外背景色（打开后各自展开浅色、深色预览）
- **按页面分类设置**：首页·微信 / 通讯录 / 发现·朋友圈·视频号 / 我 / 聊天 / 搜索 / 钱包·支付 / 通用·浮层
- **管理**：导出插件配置 / 恢复插件配置（外部 plist） / 全部恢复默认

总开关关闭时：所有子开关显示为关，插件整体不生效并立即还原已装饰界面；再打开总开关只恢复关闭前的子开关状态。开关和数值改完立刻生效。

## 注入

1. TrollFools 选中微信
2. 注入 `WechatDuo.dylib`
3. 重启微信
4. 「我」页底部，或插件收纳里打开 **WechatDuo**

安全模式：`defaults write com.tencent.xin WDSafeMode -bool YES`

日志：微信沙盒 `Documents/WechatDuo.log`，以及 `TMPDIR/WechatDuo.log`

v1.1.13：置顶横幅全透明不再留白角；会话行内容离卡片边更远；「我」页资料卡顶角圆；通讯录搜索只圆内层胶囊；「新的朋友」区头透明、列表底圆角；搜索/钱包/服务/区头开关按各自配置生效。
