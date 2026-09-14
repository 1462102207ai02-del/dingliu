# WechatDuo

微信 8.0.70+ 全页面卡片化插件。TrollStore + TrollFools 注入用裸 dylib。

- Bundle ID：`com.tencent.xin` / `com.tencent.qy.xin` / `com.tencent.mm.xin` / `com.tencent.wx`
- iOS 14.0+
- 顶栏 / 底栏 / 横幅 / 列表 / 搜索 / 输入 / 弹层 / 视频号 / 钱包
- 不调整会话气泡与聊天窗口背景
- 每个类有中文简称，可单独开关、改圆角、改双侧缩进
- 接入「插件收纳」：`MinimizeViewController` → `WCPluginsMgr`

## 设置项结构（v1.1.11）

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

v1.1.11：通讯录「标签」复用清 transform，不再偶发错位；首页会话走 m_itemView 把头像/时间跟卡片缩进；搜索栏改 rootStackView.layoutMargins + arrangeBaseUIElements，不写 frame/bar.margins。
v1.1.10：深色多设备卡跟卡片内色；切页只刷当前 Tab；通讯录分割线/统计页尾（含二级）透明；行内容随卡片缩进；置顶横幅缩进且全透明；我页资料卡圆角缩进；搜索栏用 spacer+打孔，不写 frame/margins。
v1.1.9：搜索栏只打孔不写 margins（占位不再贴放大镜）；聊天输入保持原生；服务号/通讯录统计页尾全透明；通讯录五大类行对齐；点击高亮限卡片内；设置页改数值不再把文字挤到右边。
v1.1.8：光学内边距；通讯录统计透明；分割线居中；我/设置恢复打孔；钱包/服务整片卡；首页顶栏不再多一条；全页搜索栏跟卡片缩进。
v1.1.7：行内容随卡片缩进；搜索栏跟全局缩进；首页顶栏一体不重复；隐藏引导箭头；通讯录五大类一张卡；「我」页去掉顶部灰条。
v1.1.6：卡片内/外背景色；头像与时间 transform 内边距；搜索只圆内层；加号不卡片化；标签页不打孔。
v1.1.5：打孔 overlay 不改内容坐标；置顶横幅可点；聊天背景/气泡不动；插件收纳不吃页面背景。
v1.1.4：非置顶会话中间行收内部 MainFrameItemView；置顶横幅走 FoldView/浮动视图；通讯录 NewContactsItemCell；「我」页挂 WCTableViewManager。
v1.1.3：首页缩进生效（去掉 MultiMenu 早退；列表灰底露出缝）；全局复用设置页卡片；页面背景色改开关并展开浅色/深色预览；总开关单独一行。
v1.1.2：列表按分区整段卡片（中间行左右平直，只有整体四角）；总开关记忆/恢复子开关；四页背景色合并进全局；去掉右上角完成按钮。
v1.1.1：设置页 InsetGrouped；48pt 数字框；配置导入导出。
v1.1.0：设置项按页面分类；数值改输入框；修掉首页会话列表不缩进；开关真实可逆。
v1.0.3：每类独立 layout IMP，禁止按实例 class 找 orig；启动后再装饰。
v1.0.2：constructor 延迟安装；不 hook 系统类；layout 路径不写 frame。
