# dingliu —— 你啊爸支鼎溜

微信 8.0.70+ 全局圆角美化插件（iOS）。整合重写自「微信首页圆角」+「微信圆角」两个原始 dylib，纯 ObjC runtime swizzle，**不依赖 CydiaSubstrate**，rootless 越狱与 TrollFools 注入双环境通用。

## 构建产物

GitHub Actions 自动构建，产物在 Release / Artifacts：

| 文件 | 用途 |
|---|---|
| `com.dingliu.wechat_1.0.3_iphoneos-arm64.deb` | rootless 越狱（Dopamine / palera1n rootless）安装 |
| `dingliu.dylib`（zip 同） | TrollFools 注入微信使用 |

## 本地构建（可选）

需要 Theos：

```bash
export THEOS=~/theos
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

## 安装

### rootless（Dopamine / palera1n rootless）
Sileo 添加仓库或直接 `dpkg -i com.dingliu.wechat_1.0.0_iphoneos-arm64.deb`，重启微信。

### TrollFools
1. 打开 TrollFools → 选择微信
2. 注入 `dingliu.dylib`
3. 重启微信

## 使用

微信「我」页 / 设置页底部新增入口 **「你啊爸支鼎溜」**：

- 总开关
- 首页/聊天列表：圆角半径、单元格背景色（`light:#FFFFFF;dark:#1C1C1E` 格式，留空保留原色）、搜索框圆角
- 全局：启停、半径、气泡独立启停与半径
- 描边：开关、颜色、粗细
- 其他：连续曲率、系统控件圆角、单元格铺满屏幕宽、恢复默认

## 插件收纳接入

按《插件收纳接入声明》实现：hook `MinimizeViewController` 的 `viewDidLoad`，调用 `WCPluginsMgr.sharedInstance registerControllerWithTitle:version:controller:` 将本插件注册进「插件收纳」归类列表——

- 标题：`你啊爸支鼎溜`
- 版本：`1.0.0`
- 设置页 Controller 类名：`DLSettingsController`

仅当设备上装有插件收纳（存在 `WCPluginsMgr` 类）时生效，注册异常有 @try 保护，不会影响未安装收纳的环境。

## 设计要点

- 数据驱动 hook 表（约 170 条，全部带类名存在性守卫），微信升级改名只会静默跳过，不会崩溃
- 通用 IMP 一份逻辑处理 `layoutSubviews / setFrame: / getter / 背景色 setter / setXxxBackgroundView:` 五类签名
- 首页容器（UITableView/MMTableView）只在聊天列表上下文生效，避免全局误伤
- 保留原版 `UITableViewCell _roundedGroupCornerRadius` 私有 API 注入思路
- 偏好走 `NSUserDefaults`，App 沙盒内，rootless/TrollFools 均无需额外路径处理
