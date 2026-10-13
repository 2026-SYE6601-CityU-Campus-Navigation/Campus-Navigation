# iOS 第三批离线目录与房间绑定

本批实现建筑／教室目录、预览确认式幂等导入，以及节点与房间的显式关联。前五阶段和前两批改动保留，仅在 iOS-Application 工作区修改；不连接或安装真机，不提交、不推送，不进入第四批。系统 Picker、真实相机与长时采集留到最后集中验收。

## 目录与使用入口

主区域列表新增“建筑／教室目录导入”，区域可按建筑或分类搜索，房间可按代码、名称、楼层搜索。区域支持“未分类／城市大学／测试集”；房间编辑增加代码和楼层，既有参考点与 Marker 保留。

目录参考鸿蒙固定版本的 [Campus.ets](https://github.com/2026-SYE6601-CityU-Campus-Navigation/Campus-Navigation/blob/a54f5cba762427c7bb9a8fb94c8ac7f0cb015c46/entry/src/main/ets/common/Campus.ets) 与 [Classrooms.ets](https://github.com/2026-SYE6601-CityU-Campus-Navigation/Campus-Navigation/blob/a54f5cba762427c7bb9a8fb94c8ac7f0cb015c46/entry/src/main/ets/common/Classrooms.ets)。11 栋建筑可选导入，19 个候选讲堂默认关闭。AC1 LT-1…LT-18 编号来自鸿蒙清单的推导，并非官方逐条确认的全量教室表。界面及导入备注要求现场核对；目录不会生成坐标、传感器值、照片或已采集证据。

粘贴格式为“建筑,代码,名称,备注,楼层”，前三项必填，后两列可空。支持逗号、制表符、竖线、顿号，保留空列；不支持引号 CSV 或空格分隔，避免错列后静默创建房间。错误显示行号，修正后才能确认；最多 500 KB、2000 行教室。# 和 // 开头为注释。合成操作样例：

```text
合成建筑A,X101,合成教室,离线样例,1F
合成建筑B,X101,合成教室,离线样例,2/F
```

楼层仅保守规范化，如 1F→1/F、gf→G/F、lg/f→LG/F；B1、夹层、自定义文本不猜测。不从代码或备注推断楼层，迁移不改旧楼层。

## 幂等与冲突规则

[导入服务](RoomMarker/Persistence/CatalogImportStore.swift)先生成只读预览，再一次性保存新增条目。取消不写库；保存失败回滚新模型和内存反向关系，可重试。有其他未保存修改时拒绝导入，不顺带提交其他编辑。

- 建筑使用稳定导入键。首次可复用唯一的完整名称或明确简称匹配，不作前缀猜测。多个匹配区域报冲突，不合并 UUID，不自动补旧区域分类或导入键。
- 房间在区域 UUID 内按导入键、代码或名称判重；不同建筑同码有效。同码不同信息、同名不同代码、多个旧房间匹配或批内矛盾行阻止整批导入，不覆盖旧数据。
- 已导入房间保留原代码键，后来改名、改代码或备注后重导仍跳过，不覆盖编辑。键按所在区域使用；房间移出原区域后重导，会在预览显示原区域缺少的条目，不自动移回旧房间。
- 旧房间没有导入键时，内容完全一致才跳过，冲突须人工核对。参考点、Marker、轨迹、照片不被导入更新。
- 预览后目录身份或元数据变化，确认拒绝并要求重新预览。重复预览和导入不重复新增。

## 节点与房间关系

采集与位置编辑页只列出所选区域的房间。教室、门、门禁可绑定；门／门禁另选前门或后门；大门等其他类型不能绑定。所有节点仍允许不绑定。先手工或通过目录创建 Room，不按备注、照片时间或上一房间猜配。

直接的非拥有型 roomID 替代鸿蒙 tag.markerId→Marker.roomId 的间接链。门类型存于节点，不凭照片伪造一次房间 Marker 采样；原 Marker 管理与房间删除级联继续保留。鸿蒙 [RoomPlan.ets](https://github.com/2026-SYE6601-CityU-Campus-Navigation/Campus-Navigation/blob/a54f5cba762427c7bb9a8fb94c8ac7f0cb015c46/entry/src/main/ets/common/RoomPlan.ets)的一键由教室节点生成房间未实现，不能宣称全部目录操作完全等同。

[表单状态](RoomMarker/Recording/NodeCaptureForm.swift)保留房间 UUID 与门类型，相机返回、取消和重拍不重置。切区域或类型后保留原选择并要求用户核对，不偷偷换房间。保存冻结选择，持久化再查房间存在、区域一致和类型合法；失败时节点、照片和绑定一并回滚，自有 JPEG 沿用补偿清理；重复保存门禁不变。

绑定存 roomID、roomNameSnapshot、roomCodeSnapshot、roomDoorRole。名称、代码为绑定时快照，不随目录改名变化；仅编辑楼层不刷新快照或采样证据。显式改绑更新快照，取消绑定清空四字段。历史独立标签不转换节点，独立照片仍无 tagId。

删除房间只删除房间及其 Marker；节点、照片、Track、分段、拐点和 IMU 保留，节点显示“房间已删除”。移动房间或删除区域不会重写旧节点证据，显示区域已变化；删除节点或 Track 不删除目录或旧 Marker。

## 迁移与导出

数据库为 V7，[冻结 V6 十模型](RoomMarker/Persistence/RoomMarkerSchemaV6.swift)并顺序追加 V6→V7。Area 新增 category 默认空、catalogKey 默认 nil；Room 新增 code／floor 默认空、catalogKey 默认 nil；TrackTag 四个房间字段默认 nil。V1 至 V6 旧库不猜分类、代码或绑定，不重生成 ID，不更新照片、质量字段或 IMU payload。

现有 v3 增量保存区域分类／导入键、manifest.rooms 和 tags.roomBinding。旧文件缺少可选字段仍可解码；新关系不得静默降级到 v2。状态为 linked、missing、relocated，历史快照和当前目录名称分别保留。照片仍只引用节点，从节点到 Room，不复制 JPEG 或更改 tagId/photoId。

区域导出包括本区域目录及完整跨楼 Track 引用的房间；全部导出包括全部目录；未分区包括未分区房间和选中 Track 引用的房间。房间后来移到其他区域时也保留当前目录及对应区域。没有 Track 的纯目录可导出，仅有 manifest.json。目录不含房间 Marker 明细，因此不是整库备份。详见 [JSON v3 契约](IOS_JSON_V3_CONTRACT.md)。

## 回归与统一真机清单

新增[目录测试](RoomMarkerTests/OfflineBatch3CatalogTests.swift)、[绑定测试](RoomMarkerTests/OfflineBatch3BindingTests.swift)、[迁移测试](RoomMarkerTests/OfflineBatch3MigrationTests.swift)、[导出及重开测试](RoomMarkerTests/OfflineBatch3ExportTests.swift)。覆盖解析空列、楼层、重复导入、跨楼同码、旧数据冲突、预览过期、回滚、11 类节点、相机选择、失效房间、照片补偿、删除边界、旧 JSON、V6 十模型升级和 V7 两次重开。

完整回归 424 项通过，0 失败、0 跳过，参数化合计 519 次执行，无测试运行时警告；较第二批新增 27 项／61 次执行。通用 iPhone Release 无签名构建通过。复现命令见[阶段验收](IOS_CROSS_BUILDING_STAGE6_ACCEPTANCE.md)。旧安全、历史迁移、400,004 条合成 IMU 与源照片哈希检查继续运行；没有新增 UI 自动测试目标，逻辑测试不代表真实 Picker／相机已验收。

集中真机验收补：覆盖升级保留原数据；目录预览／取消／重复导入；A、B 同码教室选择；相机返回、取消重拍、保存时区域与房间不串绑；独立节点不绑定；详情与真实 ZIP；核验备份后清理指定临时房间、节点和 Track，检查保留与清理范围。

第四批的选择轨迹导出、HTML 照片索引、大数据导出响应优化、接收端检查和分发均未开始。免费账号分发限制、长时 IMU 与真机区域选择的待验事项仍保留。
