# RoomMarker iOS JSON v3 导出契约

v3 用于无损导出应用已有的跨楼轨迹、节点照片、拐点、室内外分段和原始 IMU。它保留历史记录，不通过猜测关系或删除字段降级为 v2。此处固定的是 iOS 导出契约；尚未用 HarmonyOS 消费端验收，不代表双方已经确认可直接互读。实现定义见 [v3 DTO](RoomMarker/DTOs/ExportV3DTOs.swift)与[一致性校验](RoomMarker/Export/ExportV3Validator.swift)。

## 归档结构

```text
manifest.json
index.html
tracks/<track UUID>.json
photos/<track UUID>/<owned filename>.jpg
```

ZIP 根目录直接包含清单、tracks、photos 和新增静态照片索引，没有暂存会话父目录、数据库或绝对沙箱路径。旧 v3 没有 index.html，空范围只有 manifest.json；第四批生产出口的空范围增加 index.html，不生成 Track 占位文件。每条轨迹一个 JSON，每张照片一个原始 JPEG；照片路径相对 ZIP 根目录，而不是相对 Track JSON。manifest.tracks[].file 指向 Track JSON。

使用既有 ZIP32 stored 格式，不重新压缩 JPEG，也不改变图像方向或 EXIF。ZIP32 的单文件、偏移和条目数限制继续生效，超限明确失败，不截断数据。分享载荷只有一个 ZIP URL，不分享暂存目录。

## 基础约定

- version 为整数 3，清单和每条 Track 都显式标注 sourcePlatform 为 ios、capabilities.nearbyWifiFingerprint 为 unsupported。
- 所有记录 ID 使用源模型的稳定、小写 UUID 字符串，不随导出重新生成。不同导出范围内同一轨迹保持同一 ID，消费端按来源平台及 ID 去重，不按名称合并。
- UTC 时间使用 Int64 毫秒。sensorTimeSeconds 单独使用开机时基秒，不转成 Unix 秒。实际到达时间 receivedAtMs 可以受系统时钟改变影响。
- 可空字段在 iOS JSON 中缺省时省略；读取端应把缺省和显式 null 都视为未知。零不代表缺失，是否有效依字段定义（例如水平精度允许 0，节点气压必须大于 0）。floor 空字符串保留明确空楼层，不自动填入区域或上一节点楼层。
- points、tags、photos、segments、corners、imu.batches 和批次 samples 均显式存在，空数据用空数组；不存在的历史结构不补造记录。
- 用户名称、备注和楼层原样保留，不把它们当作文件路径。消费者不可把显示名称直接用于文件读写。

## 清单与导出范围

| 字段 | 含义 |
| --- | --- |
| version、app、sourcePlatform、capabilities | 3、RoomMarker、ios，以及平台能力声明 |
| exportedAt | 冻结快照时的 UTC 毫秒 |
| scope.kind、scope.areaId、scope.name | area、unassigned、all 或新增 selected；areaId 仅 area 范围存在；name 用于显示 |
| scope.trackIds | 仅 selected 使用，非空、唯一的小写 UUID 集合，必须精确对应导出的 Track ID；其他范围缺省 |
| photoIndex | 增量可选，存在时固定 index.html；旧 v3 缺省 |
| areas | 区域目录；id、name、note、createdAt，增量可选 category、catalogKey |
| rooms | 增量可选房间目录；旧 v3 缺省，新版本显式数组，详见下文 |
| trackCount | Track JSON 文件数，不是某楼采样点数 |
| tracks | 与文件一一对应的 id、file、name、startedAt、可空 endedAt、counts |

area 范围选择历史旧归属在该区域的轨迹，以及至少一个标签明确属于该区域的轨迹；两者合并并去重。选中后导出完整轨迹及所有子记录，不截掉其他区域节点、分段、IMU 或照片。areas 同时包含所选区域、轨迹历史区域和标签引用的其他区域。同名区域按 UUID 区分。

unassigned 范围合并历史未分区轨迹与含明确未分区标签的轨迹；不把新无标签或历史未知区域标签猜成未分区。all 范围包含全部传入轨迹，覆盖无标签、未知区域和仅有 IMU 的记录。生产入口传入全量查询；持久化区域未传轨迹数组时从同一上下文查询，不能只依赖旧 Area.tracks 关系。

清单 counts 与 Track.counts 必须相同，且逐项等于实际数组数量：pointCount、tagCount、nodeCount、photoCount、segmentCount、cornerCount、imuSampleCount。nodeCount 是 tags 中 recordKind 为 node 的数量，不另复制一份节点数组；imuSampleCount 是两路 IMU 合计，不计入 pointCount。

selected 根据冻结的 UUID 集合选择完整 Track，同名不合并。空选择或缺失 ID 明确失败，不静默导出部分集合；活动 Track 拒绝导出，历史中断 Track 的 endedAt 保持缺省。区域目录只包括所选轨迹引用的区域；房间目录包括显式绑定的现存 Room 及这些 Room 当前所属区域，不混入无关目录。包含跨楼轨迹时不裁剪另一栋楼的节点、照片或任何样本。

第三批增加房间目录：rooms 每项包含 id、可空 areaId、name、code、floor、note、可空 catalogKey、createdAt，以及可空 latitude、longitude、altitude、pressureHpa 房间参考值。area 导出本区域的全部房间和选中完整 Track 引用的其他房间；unassigned 导出未分区房间和选中 Track 引用的房间；all 导出全部目录，即使某建筑或房间尚无 Track。areas 同时包括这些房间当前引用的区域。纯目录归档 trackCount 为 0，不生成 Track 占位文件；第四批新增静态索引不改变目录内容。

category 为空表示尚未分类；catalogKey 是本地目录导入身份，不替代 UUID，不代表官方场所编码。code 和 floor 为空表示未记录；候选房号的待核实说明保留在 note。目录不包含 Room.markers 明细，因此不是全库备份。

## 静态照片索引与接收检查

index.html 只提供离线浏览原 JPEG 的辅助视图，不替代 JSON。备注、名称、房间快照按文本转义；照片路径逐组件 URL 编码后才放入 href／src，仍只指向归档内相对照片路径。无脚本、外部资源或接收人信息，设置限制性 CSP。用户在电脑保留目录结构解压后打开，浏览器方向显示按原 JPEG 信息，不重编码图片。

第四批生产出口在主 actor 冻结值，后台逐批验证并写出 IMU、按块复制和校验照片、创建 ZIP。照片哈希填入导出 DTO 而不写回模型；字段、原值、样本数量及真实时间缺口不因流式输出改变。旧同步参考路径继续用于兼容与等价测试。细节见[第四批说明](IOS_OFFLINE_BATCH4_NOTES.md)。

[接收工具](tools/RECEIVER_README.md)只读检查 iOS v3 归档，不执行 HTML、不解压或上传。它检查结构、关系和照片字节，但不证明现场数据真实性，也不替代完整 JPEG 像素解码和真人方向确认；不自动转换 HarmonyOS v2。

## Track 主体

每条 Track 保留 id、name、startedAt、可空 endedAt、isGlobalRecording、可空 legacyAreaId、可空 legacyAreaName、isSegmentedRecording、counts，以及所有子数组和 imu。

isGlobalRecording 表示全局采集身份。legacyAreaId 和 legacyAreaName 仅是历史来源信息，不把跨楼轨迹重新归属于导出区域。结束时间未知的中断轨迹保持 endedAt 缺省；不因导出自动结束、自动恢复录制或补采。

points 保留每个采样点的 id、timeMs、可空 segmentId，以及原字段 latitude、longitude、altitude、accuracy、pressureHpa、magneticX、magneticY、magneticZ、headingDeg。单位仍为度、度、米、米、hPa、µT、µT、µT、度。没有 wifiCount、wifiTop、SSID、BSSID 或 RSSI 字段，也不以 0 或空观测列表冒充附近 Wi-Fi 扫描。

## 节点和照片

tags 保留全部历史独立标签和新节点，不按时间接近程度合并。

| tags 字段 | 语义 |
| --- | --- |
| id、timeMs、createdAt、tagType、note | 源身份、冻结采集时间、创建时间、中文类别原值和备注 |
| latitude、longitude、altitude、headingDeg | 冻结的可空位置和朝向，不重新读取当前传感器 |
| accuracy、pressureHpa | 增量可选字段：水平精度，单位 m、有限且非负；气压，单位 hPa、有限且大于 0。旧数据缺省，不补零 |
| recordKind | legacy 是历史独立标签；node 是新节点 |
| areaState、areaId、floor | assigned 必须引用 areas 中有效区域；unassigned 和 unknown 都无 areaId，但语义不同 |
| photoId | node 唯一绑定照片 ID；legacy 不绑定照片 |
| roomBinding | 增量可选显式房间关系；历史／未绑定缺省，不从备注或照片猜配 |

11 类 tagType 原值为厕所、楼梯、门、门禁、电梯、教室、大门、扶梯、食堂、商店、其他室内。历史四类值不重命名。编辑区域和楼层后的当前标签值会导出，但不刷新原传感器时间或照片证据。

roomBinding 保留 roomId、nameSnapshot、codeSnapshot、可空 doorRole、status。只允许 node 的“教室／门／门禁”类型：门和门禁 doorRole 为“前门”或“后门”，教室缺省。nameSnapshot 与 codeSnapshot 是绑定时名称和代码，与 manifest.rooms 的当前值分开；不是传感器测量。status 为 linked 时，roomId 必须在 rooms 中且属于节点当前 assigned 区域；missing 表示原房间已不存在，只保留 UUID 和快照；relocated 表示房间仍在，但节点与房间的区域归属已不一致（包括原区域删除）。导出只解析状态，不修改数据库或重绑定。

照片关系仍为 photo.tagId→tag.id→tag.roomBinding.roomId，不在照片中复制房间字段或生成新 JPEG。删除 Room 不删除节点及照片，删除节点／Track 不删除 Room。iOS 不生成鸿蒙 markerId，也不把房间绑定当成已采集的 Marker；接收端需按显式结构适配。

photos 每项保留 id、timeMs、file、note、latitude、longitude、altitude、headingDeg、createdAt、kind、可空 tagId，并增加 byteCount 与小写十六进制 sha256。accuracy、pressureHpa 与节点采用相同的可空语义和单位；独立风景照片也可有自己的冻结质量字段，但仍不绑定节点。

kind 为 node 时，tagId 与 tags[].photoId 必须双向指向同一 Track 的唯一节点和照片，冻结采集时间、位置、朝向、accuracy 和 pressureHpa 均相同，包括双方同时缺失的情况。kind 为 scenery 或 legacyUnlinked 时无 tagId，历史独立照片即使与标签时间相同也保持独立。缺失、不可读、损坏或关系断裂的照片使整个导出失败，不生成假 JPEG、不输出忽略照片的成功 ZIP。

节点及照片的质量字段在相机返回时与其他元数据一同冻结，使用当时传感器服务标记为 available 的值，不声称与快门瞬间硬件同步，也不从 JPEG EXIF 或最近 TrackPoint 反推。拒绝、过期、无效或不支持的读数保持空；定位不可用不妨碍独立可用气压。重拍只在成功返回后替换冻结证据，取消重拍不改原值；编辑区域、楼层不更新这些字段。

JPEG 按字节复制，大小、SHA-256、像素尺寸、方向和原始 EXIF 不因导出改变。归档不是匿名化或加密备份；位置、备注和 JPEG 的原始元数据可能敏感，分享前由用户选择可信目的地。

## 室内外分段与拐点

segments 每项保留 id、ordinal、startedAt、可空 endedAt、environment。environment 为 unknown、indoor 或 outdoor，是用户标注，不由 GPS、区域、节点或 IMU 猜测。

分段从 ordinal 0 连续编号，第一段从 Track.startedAt 开始；中间段结束等于下一段开始，采用左闭右开区间。恰在切换边界的证据属于新段；完成轨迹的末段允许等于 Track.endedAt 的最终证据。中断轨迹的末段继续开放。空完成轨迹可以零时长，不补造一毫秒。

corners 保留 id、timeMs、segmentId、note 和与 points 同名的全部传感器字段。拐点独立于定时采样及照片节点，不计入 pointCount，不自动生成照片。新 points、corners 和 IMU 样本的 segmentId 必须在同一 Track 中可解析且测量时间落在对应区间。历史未分段点保持 segmentId 缺省；不存在的旧段和拐点保持空数组。

## 原始 IMU

imu 保留 requested、可空 requestedIntervalSeconds、accelerometerState、gyroscopeState、rejectedCount、sampleCount、accelerationCount、gyroscopeCount 和 batches。请求 0.02 秒间隔不等于实际稳定 50 Hz。不可用、权限拒绝或暂停时允许零条样本，但不能伪造值。

固定语义字段为 accelerometerUnit 等于 g、gyroscopeUnit 等于 rad/s、accelerometerIncludesGravity 为 true、coordinateFrame 等于 device-right-top-out、sensorTimeBase 等于 secondsSinceBoot、measurementTimeMapping 等于 utcMillisecondsFixedSessionAnchor、backgroundPolicy 等于 foregroundOnlyNoCatchUp。这些说明数据含义，不表示旧轨迹曾采集该数据。若其他平台使用 m/s² 或去重力数据，必须显式换算或标注不同语义，不能只复用字段名称。

每个 batch 保留源 id、sampleCount、accelerationCount、gyroscopeCount、firstTimeMs、lastTimeMs、可空 lastAccelerationTime、可空 lastGyroscopeTime 和全部 samples。每个 sample 保留 kind、sensorTimeSeconds、timeMs、receivedAtMs、segmentId、x、y、z。kind 为 accelerometer 或 gyroscope。内部 segmentID 仅改为 JSON 的 segmentId，UUID 和数值不变。

批次按最小测量时间和 ID 稳定排序，批次内保持真实回调接收顺序，不拆批、重采样或构造同步帧。两路可能不同步，迟到通道可使批次时间范围重叠，不能把批次顺序当作全局通道时间顺序。分析时按同 Track、同 kind 的 sensorTimeSeconds 排序；同通道重复时间拒绝。后台和锁屏的真实间隔不插值、不补零、不补追赶点。

## 历史兼容与版本分派

当前数据库 V7 与 JSON version 3 是不同版本轴。第二批冻结 V5、增加 V5→V6，给 TrackTag 和 TrackPhoto 增加可空 accuracy、pressureHpa。第三批冻结 V6、增加 V6→V7，给 Area 增加 category／catalogKey，Room 增加 code／floor／catalogKey，TrackTag 增加 roomID／roomNameSnapshot／roomCodeSnapshot／roomDoorRole。旧库新增字符串为空、可空字段为 nil，不推断类别、房号、绑定或质量值；V1 起的历史迁移顺序和原 ID 保持。

JSON version 仍为 3：质量、目录、房间关系及 photoIndex、scope.trackIds 都是增量可选字段，没有重命名旧字段或改变原单位。本版本可读取缺少这些键的旧 v3 JSON。消费端应接受扩展字段并识别新增 selected 范围；旧程序若忽略它们，只能称读取原有子集，不能称无损保留。旧 ZIP 不被重写，兼容不等于提供外部轨迹 JSON 导入；本地教室文本导入不属于轨迹导入。

| 历史内容 | v3 导出规则 |
| --- | --- |
| 原 V1 单区域 Track | 保留源 UUID 和旧区域来源，不重标为全局采集 |
| 未知区域标签 | areaState 为 unknown、areaId 缺省；不从旧 Track.area 猜填 |
| 独立标签与照片 | legacy 和 legacyUnlinked，关联字段缺省；不按时间匹配 |
| 未分段或无拐点数据 | isSegmentedRecording 为 false，segments 和 corners 为空，点 segmentId 缺省 |
| 未开启原始 IMU | requested 为 false，间隔缺省、状态 notRequested、计数 0、批次为空 |
| 中断轨迹 | 保留空结束时间与已落库数据，不冒充完整结束 |
| 旧节点或照片未采集质量 | accuracy、pressureHpa 缺省；不因其他模型有值而补填 |
| 旧区域／房间／节点 | 新目录字段空或缺省，roomBinding 缺省；不从名称、备注或 Marker 猜绑定 |

既有 v1/v2 DTO、兼容夹具及 v2 导出接口保留。v2 门禁拒绝无法完整表达的新结构、非空质量或房间绑定字段；区域 v2 出口也拒绝非空目录分类、代码、楼层或导入键。不改 version 或删字段绕过门禁。App 的区域、未分区、全部和所选轨迹出口明确调用 v3；旧接口仅供旧格式兼容和回归。

消费者必须先读取 version 再选对应契约；不能用宽松 v1/v2 解码器忽略 v3 的未知字段后宣称无损读取。本阶段不提供外部 JSON 导入、写库、数字 ID 到 UUID 的猜测映射或 HarmonyOS 数据自动合并。外部旧文件仅保留既有解析能力；应用旧库升级后的数据可完整导出为 v3。

## 样例与验收

固定合成样例为[历史 Track v3](RoomMarkerTests/Fixtures/stage5_legacy_track_v3.json)及[对应清单](RoomMarkerTests/Fixtures/stage5_legacy_manifest_v3.json)，用于验证未知值和历史来源不被改写。它们没有照片或 IMU 观测，不引用真实人员、位置或设备信息。

完整跨楼样例由 [Stage5Fixture](RoomMarkerTests/Stage5ExportTests.swift) 自动生成：两个同名不同 ID 区域、一条跨楼 Track、两个节点及其照片、一张风景照片、一张历史独立照片、一个历史独立标签、两个定时点、一个拐点、两个环境段及四条原始 IMU。两次定时点为 2000 和 61000 毫秒，明确保留 59 秒缺口。测试只使用合成数据，不作为真实后台执行证据。

验收必须核对：清单与文件计数、全部源 ID 和原值、双向节点照片引用、区域与分段引用、IMU 原时基和单位、JPEG 大小与哈希、ZIP CRC 和中央目录、相对路径和无暂存泄漏、源数据库无修改、源照片无移动删除，以及历史 v1/v2 回归。真机清单见[第 5 阶段说明](IOS_CROSS_BUILDING_STAGE5_NOTES.md)。
