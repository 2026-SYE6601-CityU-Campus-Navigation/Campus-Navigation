# RoomMarker · HarmonyOS NEXT 版

Android 版 RoomMarker（室内定位数据采集：区域管理 + 房间标记 + 传感器指纹 + 轨迹记录 + 途中记录节点/拍风景照）的
HarmonyOS NEXT 移植工程。

## 功能

- **区域（文件夹）管理**：首页按区域组织数据，新建/删除区域（删除时可选「移入未分区」或「彻底删除」）；
  升级前的旧数据自动归入「未分区」入口；首页还能**一键导入城大建筑区域**（每栋楼一个区域，同名自动跳过）
- **房间管理**：区域内的房间创建/备注，记录房间基准点（定位 + 气压快照）
- **子标记**：前门/后门/窗户/墙角/插座/自定义，保存时自动采集 定位+气压+地磁 快照（长按删除）；
  记录「门 / 门禁」节点时**必须选一个房间**，保存后会往该房间写一条前门/后门标记（备注含「后」即后门）
- **轨迹记录**：开始前必须选择所在区域；每秒采样 定位+气压+地磁+朝向+WiFi 指纹（Top5 BSSID:RSSI），
  每 5 秒批量落库；后台通过 LOCATION 型长时任务 + 常驻通知保活，切页面不中断
- **朝向采样**：加速度计+地磁融合方位角（GPS direction 兜底），随每个采样点入库，节点与照片同样关联朝向
- **记录节点（标记 + 照片）**：选类型（厕所/楼梯/扶梯/门/门禁/电梯/教室）写备注、点选楼层后调起系统相机
  （cameraPicker，免相机权限），拍成功才落库——照片是节点信息的必填部分，相机取消则不产生节点；
  自动关联 定位+朝向 快照。楼层可从城大常用楼层（LG/F、G/F、1/F…）里点选，也可以手填
- **拍风景照**：宣传美化用，只存照片不参与节点体系
- **批量导出**：区域数据打包 zip（每条轨迹一个 JSON：采样点+节点+照片元数据，照片原图，gallery.html 照片索引，
  manifest 索引），通过系统保存对话框导出；支持在区域页勾选部分轨迹导出
- **实时传感器**：定位 / 气压计（推算海拔）/ 地磁（含加速度融合方位角）/ WiFi 扫描列表
- **轨迹详情**：统计卡片 + 可旋转的三维轨迹立体图（经纬度+高度，节点名标注，支持双指缩放）+ 节点卡片（含照片）
  + 风景照分区 + 逐点采样数据
- **按轨迹生成房间**：轨迹里的「教室」节点可一键建成该区域下的房间（生成前列出房间名确认，
  同名自动跳过），房间继承节点的坐标与楼层信息
- **轨迹相册**：独立全屏页，按「节点照 / 风景照」分组，大图可左右滑动并显示所属节点、时间、经纬度、高度、朝向

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
│   ├── TrackDetail.ets             # 轨迹详情：统计 + 三维轨迹立体图 + 节点 + 风景照 + 采样点
│   ├── TrackGallery.ets            # 轨迹相册（全屏，独立页）：节点照/风景照分组 + 大图滑览 + 参数
│   ├── RecordingBanner.ets         # 记录中横幅：记录节点/风景照/停止（心跳重建刷新）
│   ├── CaptureDialogs.ets          # 记录节点（先填后拍）+ 风景照对话框
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
    ├── Track3D.ets                 # 三维轨迹投影与绘制（纯函数，可移植可测）
    ├── RoomPlan.ets                # 按轨迹节点规划房间（纯函数：只有教室节点建房、同名跳过）
    ├── Campus.ets                  # 城大建筑区域清单 + 常用楼层（纯数据，来源见文件注释）
    ├── ZipWriter.ets               # 手写 ZIP 打包器（STORED/CRC32/UTF-8）
    └── Exporter.ets                # 区域数据 → JSON + 照片 + gallery.html → zip → 保存对话框
```

## 关键实现说明

- **AppStorage 刷新方案（API 21 实测结论）**：AppStorage 通知 → @StorageLink 刷新的链路在
  NavDestination 场景下不生效；更隐蔽的是 `if (AppStorage.get(...))` 这类**条件不是响应式的**——
  ArkUI 只在节点首次创建时求值一次，之后不做依赖跟踪（表现为「开始录制横幅不出现、停止后不消失」）。
  现在的写法：用 setInterval 把状态同步进页面本地 @State，并把条件放进 `ForEach([heartbeat])`
  的 itemGenerator 内部（key 变化会重建子树、重新求值条件）。
- **轨迹导出 JSON 结构（version 2）**：每条轨迹 `track_{id}_{name}.json`，含 points（含 headingDeg/wifiTop）、
  tags（节点：类型/备注/定位/朝向）、photos（相对路径 `photos/{trackId}/{ts}.jpg` + 元数据 +
  `kind`（node/scenery）+ `tagIndex` 指向 tags[]）；另含 `gallery.html` 照片索引页与 manifest.json 区域索引。
  AI 可直接解析 JSON 并对照照片原图。
- **三维轨迹图**：不引入 3D 引擎，用 Canvas 2D 自己算正交投影（偏航/俯仰/自适应缩放/深度排序），
  无第三方依赖；高度优先用 GPS 海拔，纯室内无海拔时退化为气压相对高度（国际气压高度公式）。
  竖向按 **30% 预算**压缩：显示高度不超过平面尺度的 30%（`Track3D.VERTICAL_BUDGET`），
  x/y 始终真实比例，避免高差把平面形状压扁；**压的是观感不是数字**——高差读数与高度层标注
  仍写真实高度，界面会注明当前压缩比例。
  节点没有经纬度时（室内最常见）按**时间就近**取采样点位置画出来，用空心圆与文案标出这是推算值，
  与实测坐标区分；标签为「序号 + 类型 + 楼层 + 备注」，序号与下方节点列表一一对应。
- **途中拍照入库**：相机（cameraPicker）返回的是临时授权 URI，必须复制进沙箱才能长期保存。
  复制**优先用 `fs.copyFileSync`**；失败再走手写复制，且手写那条路**不依赖 `statSync(fd).size`**
  （相机/媒体库给的 fd 对 statSync 可能报 0 字节，靠这个 size 分配缓冲区会直接判失败），
  改成固定块顺序读满、读到 0 字节为止，写完再按落盘大小校验。失败原因会留在录制横幅上并进 hilog，
  不依赖一闪而过的 toast。
  x/y 始终真实比例，避免高差把平面形状压扁；**压的是观感不是数字**——高差读数与高度层标注
  仍写真实高度，界面会注明当前压缩比例。
  节点没有经纬度时（室内最常见）按**时间就近**取采样点位置画出来，用空心圆与文案标出这是推算值，
  与实测坐标区分；标签为「序号 + 类型 + 楼层 + 备注」，序号与下方节点列表一一对应。

## 已知差异 / 限制

- `BackgroundModeType.LOCATION` 在 API 12 标记为废弃但可用；如编译警告可按 IDE 提示改用
  `BackgroundTaskParam` 新重载，逻辑不变。
- WiFi 扫描结果在调用 `scan()` 1.5s 后读取，简化掉了系统广播订阅；系统节流（约 30s/次）行为一致。
- 图标为占位图（AppScope/resources/base/media/app_icon.png），上线前请替换为正式图标。
- ZIP 为 STORED 不压缩格式（兼容性优先）；数据量大时文件偏大，可后续接入压缩。
- 数据库文件与 Android 版同名同结构（旧表），新增表/列由本工程自动迁移。
