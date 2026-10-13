# RoomMarker ZIP 接收端离线检查

在电脑检查 iOS 原始 ZIP，先确认结构和关系，再看照片与采集说明。脚本只读，不解压、不上传、不改写文件；不要求安装第三方 Python 包。当前支持 RoomMarker iOS JSON v3 和应用生成的 stored ZIP32，含旧 v3；不支持 HarmonyOS v2、ZIP64 或手工重打包格式。

## 最短操作

使用 Python 3.9 或更新版本，在仓库根目录运行，把示例文件名替换为收到的 ZIP 路径。路径含空格时保留引号。

```sh
python3 -B tools/validate_roommarker_zip.py "RoomMarker-example.zip"
```

退出码 0 且 status 为 passed 表示本工具的检查通过；退出码 1 的 category 指出失败类别。不要通过改写 JSON、补零或删照片来消除错误，保留原包和报告，请采集方检查后重新导出。错误报告不输出原内容、绝对路径或异常堆栈。

通过后，在另一个工作副本中保持目录结构解压，用浏览器离线打开根目录 index.html，点击图片查看原 JPEG。不要把 HTML 单独挪走；旧 v3 可能没有索引，仍可按 JSON 中的相对 file 查看原照片。检查人脸等隐私、清晰度和方向；不要把原 ZIP 解压重打包后冒称原始交付物。

## 从 iPhone 接收 ZIP

同一可信 Wi-Fi 下可启动零依赖本地接收服务：

```sh
python3 -B tools/upload_server.py --token "单独生成的长令牌" --dir "私有接收目录"
```

将输出的 `http://电脑名.local:8000/upload` 填入 RoomMarker“上传设置”，令牌相同、字段名保持 `file`。服务限制单次请求大小，multipart 按 64 KiB 流式写入随机临时文件，验证 ZIP 文件名与标志后原子发布；错误、断线、令牌不符或非法输入不会留下可见半成品。启用令牌后，上传、文件列表和下载都需同一令牌；浏览器列表地址写作 `http://电脑名.local:8000/?k=令牌`。令牌采用恒定时间比较，日志不输出令牌值，健康检查和文件页不公开本机保存路径。局域网 HTTP 仅用于受信网络，不经互联网暴露。

异地长期收集应使用 HTTPS。`tools/r2_worker.js` 提供私有 Cloudflare R2 示例：绑定名为 `TRACKS` 的私有桶，将 `UPLOAD_TOKEN` 和可选 `READ_TOKEN` 配为 Worker Secret。不要在 App 或 Git 中保存 R2 访问密钥；公开前还需按项目账号、费用、保留期和隐私要求单独验收。

## 检查范围

- ZIP 的本地头、中央目录、末尾记录、CRC 和精确条目集合；拒绝绝对／遍历路径、空组件、控制字符、盘符、反斜线、重复或大小写别名、符号链接、额外暂存内容及附加尾部数据。
- manifest 与 Track JSON 的版本、平台、unsupported Wi-Fi、UUID、数量和引用；拒绝重复 JSON 键、非有限数及 SSID／BSSID／RSSI／wifiCount／wifiTop 观测字段，不按用户备注中的词误判。
- 所选 Track 集合、节点与照片双向唯一关系、独立历史媒体、房间 linked／missing／relocated 状态、室内外／未知分段和样本时间归属。
- IMU 单位、时基、批次计数、有限值、同通道重复和批内顺序；跨批迟到允许存在，时间间隔按每路传感器时间排序分析，不假定同步帧。
- JPEG 大小、SHA-256、首尾标记、头部尺寸和可用 EXIF 方向；静态 HTML 的结构、CSP、图片集合及相对链接。

报告不包含原坐标、照片内容、姓名或备注；仍有轨迹／照片 UUID 与文件哈希，不应当作完全匿名数据。原 ZIP 含传感器位置、备注及原 JPEG EXIF，只交给项目指定的可信接收人。

## 限制与后续判定

本工具不提供完整 JPEG 像素解码。pixelDecode 为 notPerformed 不表示坏图；请实际打开照片，结合导出端 ImageIO 校验。EXIF 方向缺省表示未声明，不能据此证明画面方向正确。JPEG 头部读取上限为 1 MiB，超过时明确失败。

最大单文件 512 MiB、总内容 2 GiB、10,000 条目。超限失败不是数据已损坏，应保留原包并调整后续接收方案，不截断样本。每次解码一条 Track JSON，超长轨迹仍可能占用较多桌面内存。

最大时间间隔、接收延迟和采样数量是结构报告，不是真机验收结论。与操作者记录的前后台、锁屏、来电、时钟变化和异常时间一起分析；工具不证明真实现场来源，不补造追赶点，不以名义 50 Hz 推算“应有”数量。

若还保有源 JPEG，可用系统 SHA-256 工具对照报告中的 sha256 和字节数。导出端测试已检查合成源文件不变；接收工具没有手机容器权限，不能自行证明手机源文件仍存在。

## 自动验证

```sh
python3 -B -m unittest discover -s tools/tests -v
```

单元测试仅使用临时合成数据和本机回环端口，不修改正式归档或访问外网。Swift 回归另外生成合成 ZIP，独立接收检查验证实际应用输出。字段约定见[JSON v3 契约](../IOS_JSON_V3_CONTRACT.md)，产品边界见[完整功能对齐](../IOS_FULL_PRODUCT_PARITY.md)。
