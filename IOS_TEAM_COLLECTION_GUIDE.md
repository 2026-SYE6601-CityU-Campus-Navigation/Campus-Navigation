# RoomMarker 组员安装与轨迹采集说明

本说明统一 iOS 组员的安装、采集和交付方式。[完整产品对齐](IOS_FULL_PRODUCT_PARITY.md)与自动回归已经完成；旧数据覆盖升级、旧 Track／IMU／照片和目录导入已有真机证据。为了节省时间，不再逐功能重复验收，但第一名组员仍应先做一条 3–5 分钟短路线并回收原始 ZIP，通过后再扩大人员和路线。功能目标与 HarmonyOS 对齐，代码无需一致，但单位、节点关系和数据缺失含义必须明确。

## 安装方式

| 条件 | 可用方式 | 限制 |
| --- | --- | --- |
| 只有免费 Apple ID | Xcode 给注册的测试设备安装 | 不是公开下载链接；Personal Team 最多 3 台设备，App ID／设备／描述文件 7 天到期，需要用相同身份重新构建安装 |
| 学校或个人已有 Apple Developer Program | 优先 TestFlight 邀请组员安装 | 需签名、应用记录和上传；外部测试可能需审核，单个构建最多测试 90 天 |
| 有开发者会员且少量固定设备需要直接安装 | Ad Hoc | 必须预先注册设备并签名；不是任意 iPhone 都能安装的裸 IPA |

以上规则按 [Apple Personal Team 说明](https://developer.apple.com/help/account/basics/about-your-developer-account/)、[项目会员与教育机构减免费用说明](https://developer.apple.com/help/account/membership/program-enrollment/)、[TestFlight 说明](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)和[注册设备说明](https://developer.apple.com/help/account/devices/devices-overview/)核对。没有付费会员时，不存在将当前原生 App 简单上传网盘就能让任意组员在 iPhone 安装的常规官方路径。网页/PWA 不等价于当前原生采集器，不能作为保留其传感器、后台和本地持久化能力的直接替代。

最省事的持续分发路径是先询问学院或项目导师是否有开发者团队可用；Apple 说明认可的教育机构可以申请会员费用减免。付费／学校团队可使用 TestFlight 邀请链接，构建最长测试 90 天，第一份外部测试构建可能需要 Beta App Review。账号持有人在 Apple 官方界面配置权限；不共享 Apple ID 密码、私钥或验证码。组员安装完成后，先确认版本、权限和一条试采结果。当前最低系统版本为 iOS 17，不能以一台 iPhone 的结果代表所有机型已通过。

## 只有免费 Apple ID 时的实际安装步骤

推荐每位有 Mac 的组员使用自己的 Apple ID 安装；没有 Mac 的组员可把 iPhone 交给负责人连接 Xcode，但负责人同一个 Personal Team 同期最多注册 3 台设备。

1. 在 Mac 安装项目要求的 Xcode，登录 GitHub 后克隆仓库，切换到 `iOS-Application`，并向负责人核对指定提交哈希。不要从不明来源下载 IPA。
2. 双击 `RoomMarker.xcodeproj`。在 Xcode **Settings → Accounts** 添加组员自己的 Apple ID；不要把密码或验证码发给负责人。
3. 选择 RoomMarker target 的 **Signing & Capabilities**，打开自动签名并选择自己的 `Personal Team`。若 Apple 提示 Bundle Identifier 已被占用，在本机给末尾添加只属于该采集员的短后缀；以后续装必须保持同一 Team 和同一标识。不要把个人 Team、标识或签名文件提交回仓库。
4. 用数据线连接并解锁 iPhone，点击“信任此电脑”；按系统提示开启 Developer Mode。Xcode 顶部选择这台 iPhone，点击 Run。
5. 若手机要求验证开发者，在 **设置 → 通用 → VPN 与设备管理** 中只信任自己的开发者身份，然后打开 RoomMarker。
6. 首次先建立一个测试区域、录制约一分钟、拍一张不含个人信息的物体、停止并导出。确认通过后再开始正式路线。
7. Personal Team 签名 7 天后需回到 Xcode 用相同身份重新 Run。覆盖安装通常保留容器数据；仍应先导出所有未交付轨迹，绝不为了续签先卸载 App。

没有 Mac/Xcode、没有付费或学校开发者团队时，负责人无法制作一个“点链接即可永久安装”的正规 iPhone 版本。若采集要持续数周或人数超过 3，优先申请学校团队或 Apple Developer Program，再转 TestFlight，而不是反复共享一个免费 Apple ID。

## 配置轨迹包接收

临时同一 Wi-Fi 交付可在负责人的 Mac 从仓库根目录运行：

```sh
python3 -B tools/upload_server.py --token "项目单独生成的长令牌" --dir "指定的私有接收目录"
```

服务启动后会显示 `http://电脑名.local:8000/upload`。在 iPhone 的 **区域列表 → 传感器 → 上传设置** 填入该地址、同一令牌和字段名 `file`。Mac 防火墙若询问，只允许可信本地网络。生成 ZIP 后选择“上传 ZIP”；服务器返回文件名、大小和 SHA-256。接收后仍要运行离线检查器，不能只以 HTTP 200 作为数据合格。

长期异地交付应使用 HTTPS 私有服务。仓库的 `tools/r2_worker.js` 是 Cloudflare Worker/R2 示例：桶保持私有，`UPLOAD_TOKEN` 设为 Secret，可另设只读 `READ_TOKEN`；不要把 R2 密钥、Apple 密钥或真实令牌写进 App、Git 或聊天。当前 App 只保存接收 URL、字段名和 Keychain 令牌，不包含项目云账号。

正式 TestFlight 准备需核对唯一应用身份、构建号、[AppIcon](https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon/)、测试说明、隐私和上传验证结果。现阶段没有替用户购费、创建公开邀请或向 Apple 上传 App。免费开发安装到期前先导出数据；更新采用同身份覆盖安装，不卸载清空原容器。升级后不要在未备份的情况下覆盖回旧数据库结构版本。

## 正式采集标准

1. 使用项目统一的楼栋名称和楼层写法；名称不负责跨设备去重，保留原 UUID 和 ZIP。轨迹名建议“采集员代号_日期_路线_轮次”，不使用姓名、手机号或设备序列号。
2. 每条连续路线只开始一次 Track。进入下一栋楼时继续录制，在新节点上选择对应区域及楼层，不为每栋楼重开轨迹。
3. 若本轮需要惯性数据，开始前打开“采集原始 IMU”。保持 App 前台和屏幕解锁；正常步行并稳定持机，避免收入口袋后仍假定设备姿态相同。前台采集应在安全地点操作，不边拍照边过马路。
4. 节点使用明确类别和一张现场证据照片。当前 11 类为厕所、楼梯、门、门禁、电梯、教室、大门、扶梯、食堂、商店、其他室内。拍摄应清楚展示节点，不拍人脸、学生证或无关个人信息。
5. 独立环境照片使用“拍摄风景”，不冒充节点照片。每个新节点一对一绑定照片；历史独立标签与照片继续独立，不按时间猜配。
6. 在真实转向处点“采集拐点”。进入或离开建筑时手动切换“环境”，保持室内、室外、未知的真实含义；区域名称不自动决定环境。
7. 请求位置、运动与相机权限时由采集员确认。不可用字段允许为空，不输入零值或编造观测。采集前查看实时读数；定位弱不等于室内位置精确，保留准确度和缺口供分析。
8. 正式惯性采集若意外后台、锁屏、来电或遇到保存错误，记录事件及大致时间并在交付说明标注。iOS 后台定位可能继续，但原始 IMU 暂停，不承诺后台连续惯性数据；回前台后不补点。
9. 结束时点“停止”，等待保存完成和横幅消失。核对 Track 详情中的节点、照片、拐点、分段、两路 IMU 数量；照片大图必须可读。若提示待保存，先重试，不卸载或删除轨迹。
10. 在轨迹列表进入“选择轨迹导出”，按名称、时间和 ID 勾选本轮轨迹；也可导出区域或全部轨迹。等待后台处理，再选择“分享 ZIP”或“上传 ZIP”；可取消重试，不删除原数据。跨楼 Track 从任一涉及区域或选择范围导出都完整保留其他楼的节点及全部数据，不手工裁剪 JSON。

## 交付与质量门槛

将系统保存的原始 ZIP 交给项目约定的私有目的地，不解压重打包，不手改版本或 ID。另附采集员代号、App 版本与构建号、机型和系统版本、路线、前后台/锁屏事件、异常说明；无需提供 UDID、Apple ID 或签名信息。当前 ZIP 不包含完整 App 构建追踪字段，因此交付说明不能省略版本。

接收方至少核对以下项目，合格后再让组员继续批量采集：

先运行[接收端离线检查](tools/RECEIVER_README.md)：`python3 -B tools/validate_roommarker_zip.py "RoomMarker-example.zip"`。工具只读原包，支持 iOS v3，不自动转换鸿蒙扩展 v2。通过后在工作副本中解压并打开 index.html，看节点照片、独立风景和原图；旧 v3 无索引仍可检查 JSON。工具只验证 JPEG 标记、尺寸与哈希，不能替代实际打开原图或证明手机源照片仍在。

- 清单 version 为 3、sourcePlatform 为 ios，文件数及各数组计数一致；每条 Track 使用稳定 UUID，重复导出按平台与 ID 去重，不按文件名或名称合并。
- A、B 区域节点属于同一完整 Track；节点与照片双向唯一引用，所有相对照片路径都存在，JPEG 能解码，SHA-256 与声明相同。
- 拐点、普通点及 IMU 的分段引用可解析，环境边界连续；不得把缺省环境改成室内。
- 原始加速度单位是 g 且含重力，角速度是 rad/s，设备坐标轴为右、顶、屏幕外；不能与 m/s²、去重力或世界坐标数据直接混用。
- 时间分别保留 UTC 毫秒和开机时基秒。分析两路 IMU 的实际间隔与缺口，不要求严格 50 Hz，不把跨通道回调排列误认为同步帧；恒定假值、复制样本或人为补点不合格。
- nearbyWifiFingerprint 明确为 unsupported，没有 BSSID、RSSI 或虚构附近 Wi-Fi；这是平台能力差异，不是补填字段的任务。
- 无绝对路径、遍历、暂存目录或数据库泄漏；原库、原照片在导出后仍在。已交付 ZIP 本身含位置与照片，不能因应用沙箱隔离就认为导出已匿名化。

缺失数据保留原状并附原因，不为了通过检查改写观测。正式数据只在负责人确认接收、完成备份后再清理。完整字段与旧格式规则见 [JSON v3 契约](IOS_JSON_V3_CONTRACT.md)，当前放行状态见[第 6 阶段验收](IOS_CROSS_BUILDING_STAGE6_ACCEPTANCE.md)。
