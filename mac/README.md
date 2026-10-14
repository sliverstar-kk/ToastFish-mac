# ToastFish macOS

原生 macOS 菜单栏版本，使用 Swift 6、SwiftPM 和 AppKit，最低支持 macOS 13。只需要安装 Command Line Tools，无需 Xcode，也没有第三方依赖。

## 构建与运行

在仓库根目录执行：

```sh
mac/scripts/build_app.sh
open mac/build/ToastFish.app
```

打包脚本也可以从任意目录使用绝对路径运行。脚本按本机架构进行 release 构建，生成图标、复制资源，并对 `mac/build/ToastFish.app` 进行 ad-hoc 签名。重复执行会替换之前的应用包。

单独编译和测试：

```sh
cd mac
swift build
swift test
```

测试使用 Swift Testing。Package.swift 为仅安装 CLT 的环境补充测试框架与运行库路径；当前 CLT 的 Testing.framework 要求 macOS 14 或更高版本来运行测试，应用本身仍以 macOS 13 为部署目标。

验证应用签名：

```sh
codesign -v mac/build/ToastFish.app
```

## 通知与当前功能

首次运行时请允许通知，并在 **系统设置 → 通知 → ToastFish** 中将通知样式设为 **提醒**，方便保留学习内容。点击任意词库可测试通知；点击“开始！”等尚未完成的功能，会显示“功能开发中：…”通知。

请通过打包后的 `.app` 运行，启动需要包内数据库资源。通知服务在没有 bundle identifier 时只向 stderr 输出信息，不访问系统通知中心。

应用仅显示菜单栏图标，没有 Dock 图标。英语和日语词库共同使用单选状态，首次默认“四级核心词汇”。词库选择、“自动播放”和“自动日志”写入数据库，重启后恢复；选择词库会通知当前词库和学习进度。“重置进度”需确认后执行。“开机启动”目前仅切换内存中的勾选状态，不会修改系统登录项。

“使用说明(必读)”和“Star!!”打开打包的原始文件；原始说明针对 Windows，其中快捷键、通知按钮和学习流程将在后续版本实现。本阶段的“快捷方式”仅展示计划使用的快捷键；“单词个数”和“英标类型”的设置界面仍为占位，数据层已支持保存这些设置。

## 数据层与 SM2

用户数据库保存在 `~/Library/Application Support/ToastFish/inami.db`。首次启动时自动创建，后续启动和应用更新都不会覆盖已有的用户数据库。

“重置进度”会清除当前词库的学习状态，将词条恢复为未学习，并将进度计数归零；保留词库内容、难度、复习间隔、上次评分和复习时间，不影响其他词库。
