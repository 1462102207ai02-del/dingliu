# WechatDuo

微信 8.0.70+ 全页面卡片化插件。TrollStore + TrollFools 注入用裸 dylib。

- Bundle ID：`com.tencent.xin` / `com.tencent.qy.xin` / `com.tencent.mm.xin` / `com.tencent.wx`
- iOS 14.0+
- 顶栏 / 底栏 / 横幅 / 列表 / 搜索 / 输入 / 气泡 / 弹层 / 视频号 / 钱包
- 每个类有中文简称，可单独开关、改圆角、改双侧缩进
- 接入「插件收纳」：`MinimizeViewController` → `WCPluginsMgr`

## 设置项结构（v1.1.0）

按微信页面顺序分类，不再一屏铺开上百项：

- **全局**：总开关 / 连续曲率 / 全局圆角 / 全局缩进（数值用输入框，留空 = 跟随默认）
- **页面背景色**：微信、通讯录、发现、我 四个板块，浅色与深色可分别设定（系统原生取色器）
- **按页面分类设置**：首页·微信 / 通讯录 / 发现·朋友圈·视频号 / 我 / 聊天 / 搜索 / 钱包·支付 / 通用·浮层
  → 点进去只看到该页的元素，再点进去是单项的开关、圆角、缩进
- **全部恢复默认**

总开关关闭时：所有独立开关置灰，插件整体不生效，并立即把已装饰的界面还原，不留残留。

## 注入

1. TrollFools 选中微信
2. 注入 `WechatDuo.dylib`
3. 重启微信
4. 「我」页底部，或插件收纳里打开 **WechatDuo**

安全模式：`defaults write com.tencent.xin WDSafeMode -bool YES`

日志：微信沙盒 `Documents/WechatDuo.log`，以及 `TMPDIR/WechatDuo.log`

v1.1.0：设置项按页面分类；四页背景色深浅自定义（原生取色器）；数值改输入框；
修掉首页会话列表不缩进（沿父类链找真正实现 `layoutSubviews` 的类再挂载）；
卡片一体化（底板与 contentView 一起缩进）；开关真实可逆，关闭即全量还原。
v1.0.3：每类独立 layout IMP，禁止按实例 class 找 orig；启动后再装饰。
v1.0.2：constructor 延迟安装；不 hook 系统类；layout 路径不写 frame。
