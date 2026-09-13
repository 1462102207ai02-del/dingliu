# WechatDuo

微信 8.0.70+ 全页面卡片化插件。TrollStore + TrollFools 注入用裸 dylib。

- Bundle ID：`com.tencent.xin` / `com.tencent.qy.xin` / `com.tencent.mm.xin` / `com.tencent.wx`
- iOS 14.0+
- 顶栏 / 底栏 / 横幅 / 列表 / 搜索 / 输入 / 气泡 / 弹层 / 视频号 / 钱包
- 每个类有中文简称，可单独开关、改圆角、改双侧缩进
- 接入「插件收纳」：`MinimizeViewController` → `WCPluginsMgr`

## 设置项结构（v1.1.3）

- **总开关**：单独一行「启用 WechatDuo」
- **全局**：连续曲率 / 全局圆角 / 全局缩进 / 页面背景色（开关；打开后展开浅色、深色两行，只显示色块预览）
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

v1.1.3：首页缩进生效（去掉 MultiMenu 早退；列表灰底露出缝）；全局复用设置页卡片；页面背景色改开关并展开浅色/深色预览；总开关单独一行。
v1.1.2：列表按分区整段卡片（中间行左右平直，只有整体四角）；总开关记忆/恢复子开关；四页背景色合并进全局；去掉右上角完成按钮。
v1.1.1：设置页 InsetGrouped；48pt 数字框；配置导入导出。
v1.1.0：设置项按页面分类；数值改输入框；修掉首页会话列表不缩进；开关真实可逆。
v1.0.3：每类独立 layout IMP，禁止按实例 class 找 orig；启动后再装饰。
v1.0.2：constructor 延迟安装；不 hook 系统类；layout 路径不写 frame。
