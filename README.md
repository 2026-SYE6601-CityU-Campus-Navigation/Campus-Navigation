# RoomMarker · HarmonyOS NEXT 版

Android 版 RoomMarker（室内定位数据采集：区域管理 + 房间标记 + 传感器指纹 + 轨迹记录 + 途中拍照/标签）的
HarmonyOS NEXT 移植工程。

## 功能

- **区域（文件夹）管理**：首页按区域组织数据，新建/删除区域（删除时可选「移入未分区」或「彻底删除」）；
  升级前的旧数据自动归入「未分区」入口
- **房间管理**：区域内的房间创建/备注，记录房间基准点（定位 + 气压快照）
- **子标记**：前门/后门/窗户/墙角/插座/自定义，保存时自动采集 定位+气压+地磁 快照（长按删除）
- **轨迹记录**：开始前必须选择所在区域；每秒采样 定位+气压+地磁+朝向+WiFi 指纹（Top5 BSSID:RSSI），
  每 5 秒批量落库；后台通过 LOCATION 型长时任务 + 常驻通知保活，切页面不中断
- **朝向采样**：加速度计+地磁融合方位角（GPS direction 兜底），随每个采样点入库，标签/照片同样关联朝向
- **途中拍照**：记录中一键调起系统相机（cameraPicker，无需相机权限），照片复制进沙箱并与轨迹关联
  （时间/定位/朝向），供 AI 读取现场关键信息
- **途中打标签**：厕所/楼梯/门/门禁/电梯/教室 + 备注，自动关联 定位+朝向 快照
- **批量导出**：区域数据打包 zip（每条轨迹一个 JSON：采样点+标签+照片元数据，照片原图，manifest 索引），
  通过系统保存对话框导出到手机
- **实时传感器**：定位 / 气压计（推算海拔）/ 地磁（含加速度融合方位角）/ WiFi 扫描列表
- **轨迹详情**：统计卡片 + 标签/照片展示（缩略图可点开大图）+ Canvas 轨迹形状（绿起点/红终点）+ 逐点采样数据

## 环境要求

- DevEco Studio 6.0.1（HarmonyOS 6.0.1 / compileSdkVersion 21；代码兼容 API 12 写法）
- 目标设备：HarmonyOS NEXT 真机（传感器/相机/轨迹类功能需真机；测试机华为 Mate 80）

## 运行步骤

1. DevEco Studio → Open 选择本工程目录，等待 hvigor 同步完成。
2. 配置签名：Run → Edit Configurations → Signing Configs → 勾选 Automatic debug signature
   （或 Build → Generate Key and CSR 手动配置）。
3. 真机连接（开启开发者模式 + USB 调试）或直接运行到模拟器，点击 Run。

首次进入会申请位置权限；拒绝后 GPS 字段为空，气压/地磁/朝向仍可用。

## 技术映射（Android → HarmonyOS）

| Android | HarmonyOS |
|---|---|
| Room (SQLite) | `@kit.ArkData` relationalStore（同库名 `room_marker.db`；新增 areas/track_tags/track_photos 表，旧库自动 ALTER 迁移） |
| FusedLocationProvider | `@kit.LocationKit` geoLocationManager |
| SensorManager | `@kit.SensorServiceKit` sensor |
| WifiManager.startScan | `@kit.ConnectivityKit` wifiManager.scan（同样受系统节流，需开启系统定位开关） |
| 系统相机拍照 | `@kit.CameraKit` cameraPicker.pick（免相机权限） |
| 文件保存对话框 | `@kit.CoreFileKit` picker.DocumentViewPicker.save |
| ZIP 打包 | 手写 ZipWriter（STORED + CRC32，无官方多文件 zip API） |
| 前台服务 + WakeLock | LOCATION 长时任务（backgroundTaskManager.startBackgroundRunning）+ 通知（无 WakeLock 等价 API） |
| Compose Navigation | Navigation + NavPathStack |
| StateFlow / LiveData | AppStorage + 心跳重建（见下）；Store 监听器 |

## 代码结构

```
entry/src/main/ets/
├── entryability/EntryAbility.ets   # 初始化 DB、请求运行时权限、AppStorage 默认值
├── pages/
│   ├── Index.ets                   # Navigation 路由 + 区域列表（首页）
│   ├── AreaDetail.ets              # 区域详情：房间 + 轨迹 + 批量导出 + 删除区域
│   ├── RoomDetail.ets              # 房间详情：基准点 + 标记列表
│   ├── TrackList.ets               # 全部轨迹 + StartTrackDialog（强制选区域）
│   ├── TrackDetail.ets             # 轨迹详情：统计 + 标签/照片 + Canvas 轨迹 + 采样点
│   ├── RecordingBanner.ets         # 记录中横幅：拍照/打标签/停止（心跳重建刷新）
│   ├── CaptureDialogs.ets          # 标签选择 + 照片备注对话框
│   └── LiveSensors.ets             # 实时传感器
├── data/
│   ├── Entities.ets                # Area/Room/Marker/Track/TrackPoint/TrackTag/TrackPhoto 实体
│   └── Store.ets                   # relationalStore 封装（CRUD + 迁移 + 变更订阅）
├── sensors/
│   ├── SensorSnapshotter.ets       # 一次性 定位+气压+地磁 快照
│   ├── LiveStream.ets              # 实时传感器流（→ AppStorage）
│   ├── TrackRecorder.ets           # 轨迹记录器单例（1Hz 采样含朝向、5s 落库、长时任务）
│   └── TrackMedia.ets              # cameraPicker 拍照 + 复制进沙箱
└── common/
    ├── Utils.ets                   # 时间/坐标格式化 + 方位角融合 + 全局 Context
    ├── ZipWriter.ets               # 手写 ZIP 打包器（STORED/CRC32/UTF-8）
    └── Exporter.ets                # 区域数据 → JSON + 照片 → zip → 保存对话框
```

## 关键实现说明

- **AppStorage 刷新方案（API 21 实测结论）**：AppStorage 通知 → @StorageLink 刷新的链路在
  NavDestination 场景下不生效。记录横幅与页面按钮统一用「@State heartbeat + setInterval(500ms) +
  ForEach([heartbeat]) 重建」方案读取最新状态（与 LiveSensors 页同款已验证方案）。
- **轨迹导出 JSON 结构**：每条轨迹 `track_{id}_{name}.json`，含 points（含 headingDeg/wifiTop）、
  tags（标签类型/备注/定位/朝向）、photos（相对路径 `photos/{trackId}/{ts}.jpg` + 元数据），
  manifest.json 为区域索引。AI 可直接解析 JSON 并对照照片原图。

## 已知差异 / 限制

- `BackgroundModeType.LOCATION` 在 API 12 标记为废弃但可用；如编译警告可按 IDE 提示改用
  `BackgroundTaskParam` 新重载，逻辑不变。
- WiFi 扫描结果在调用 `scan()` 1.5s 后读取，简化掉了系统广播订阅；系统节流（约 30s/次）行为一致。
- 图标为占位图（AppScope/resources/base/media/app_icon.png），上线前请替换为正式图标。
- ZIP 为 STORED 不压缩格式（兼容性优先）；数据量大时文件偏大，可后续接入压缩。
- 数据库文件与 Android 版同名同结构（旧表），新增表/列由本工程自动迁移。
