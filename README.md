# WechatDuo

微信 8.0.70+ 全页面卡片化插件。TrollStore + TrollFools 注入用裸 dylib。

- Bundle ID：`com.tencent.xin` / `com.tencent.qy.xin` / `com.tencent.mm.xin` / `com.tencent.wx`
- iOS 14.0+
- 顶栏 / 底栏 / 横幅 / 列表 / 搜索 / 输入 / 气泡 / 弹层 / 视频号 / 钱包
- 每个类有中文简称，可单独开关、改圆角、改双侧缩进
- 接入「插件收纳」：`MinimizeViewController` → `WCPluginsMgr`

## 注入

1. TrollFools 选中微信
2. 注入 `WechatDuo.dylib`
3. 重启微信
4. 「我」页底部，或插件收纳里打开 **WechatDuo**

安全模式：`defaults write com.tencent.xin WDSafeMode -bool YES`

日志：微信沙盒 `Documents/WechatDuo.log`
