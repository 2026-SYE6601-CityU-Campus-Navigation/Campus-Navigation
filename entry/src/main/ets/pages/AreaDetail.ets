import { promptAction } from '@kit.ArkUI';
import { Area, AREA_CATEGORY_CITYU, Room, Track, areaCategoryOptions } from '../data/Entities';
import { Store, UNASSIGNED_AREA_ID } from '../data/Store';
import { TrackRecorder } from '../sensors/TrackRecorder';
import { RecordingBanner } from './RecordingBanner';
import { StartTrackDialog } from './TrackList';
import { Exporter, PackProgress, StagedUpload } from '../common/Exporter';
import { UploadProgress, UploadResult, UploadTarget, Uploader } from '../common/Uploader';
import { fmtDuration, fmtTime } from '../common/Utils';
import { Theme } from '../common/Theme';
import { PillButton, ThickButton } from '../common/Widgets';

/** 上传设置存在 settings 表里的键名（换后端只改地址，App 代码不动） */
const UPLOAD_URL_KEY = 'upload_url';
const UPLOAD_TOKEN_KEY = 'upload_token';

@CustomDialog
struct AddRoomDialog {
  controller?: CustomDialogController;
  onSave?: (name: string, code: string, note: string) => void;
  @State name: string = '';
  @State code: string = '';
  @State note: string = '';

  build() {
    Column({ space: 14 }) {
      Text('添加房间').fontSize(19).fontWeight(FontWeight.Bold).width('100%').fontColor(Theme.INK)
      TextInput({ placeholder: '房间名称（如：301 会议室 / 讲堂 1）' })
        .fontSize(13.5)
        .backgroundColor(Theme.CARD_SOFT)
        .borderRadius(14)
        .border({ width: 2, color: Theme.LINE })
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onChange((v: string) => {
          this.name = v;
        })
      TextInput({ placeholder: '教室代码（选填，如 LT-1 / P4702 / 6-213）' })
        .fontSize(13.5)
        .backgroundColor(Theme.CARD_SOFT)
        .borderRadius(14)
        .border({ width: 2, color: Theme.LINE })
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onChange((v: string) => {
          this.code = v;
        })
      TextInput({ placeholder: '备注（选填）' })
        .fontSize(13.5)
        .backgroundColor(Theme.CARD_SOFT)
        .borderRadius(14)
        .border({ width: 2, color: Theme.LINE })
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onChange((v: string) => {
          this.note = v;
        })
      Text('加完就留在这个区域页，不再自动跳进房间；想进去点列表里那一行。')
        .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
      Row({ space: 10 }) {
        Column() {
          ThickButton({
            label: '取消',
            kind: 'ghost',
            compact: true,
            onTap: (): void => {
              this.controller?.close();
            }
          })
        }.layoutWeight(1)

        Column() {
          ThickButton({
            label: '保存',
            kind: 'primary',
            compact: true,
            disabled: this.name.trim().length === 0,
            onTap: (): void => {
              this.controller?.close();
              if (this.onSave) {
                this.onSave(this.name.trim(), this.code.trim(), this.note.trim());
              }
            }
          })
        }.layoutWeight(1.4)
      }.width('100%')
    }
    .padding(18)
    .width('100%')
    .backgroundColor(Theme.CARD)
  }
}

/** 改区域分类：固定两类，点一下选中。分类是自动归类出来的，这个对话框是给用户反悔用的 */
@CustomDialog
struct AreaCategoryDialog {
  controller?: CustomDialogController;
  onSave?: (category: string) => void;
  /** 当前分类（空串按「城市大学」显示） */
  current: string = '';
  @State picked: string = AREA_CATEGORY_CITYU;

  aboutToAppear(): void {
    this.picked = this.current.length > 0 ? this.current : AREA_CATEGORY_CITYU;
  }

  build() {
    Column({ space: 14 }) {
      Text('改分类').fontSize(19).fontWeight(FontWeight.Bold).width('100%').fontColor(Theme.INK)
      Text('「城市大学」放正式的校园建筑数据；「测试集」放试采集、试标签、试拍照的区域。首页按这两类分区显示。')
        .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
      Row({ space: 10 }) {
        ForEach(areaCategoryOptions(), (c: string) => {
          Text(c)
            .fontSize(13.5)
            .fontWeight(FontWeight.Bold)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 10, bottom: 10 })
            .fontColor(this.picked === c ? Theme.ON_RED : Theme.INK)
            .backgroundColor(this.picked === c ? Theme.RED : Theme.CARD_SOFT)
            .borderRadius(14)
            .border({ width: 2, color: this.picked === c ? Theme.RED_DEEP : Theme.LINE })
            .onClick(() => {
              this.picked = c;
            })
        }, (c: string) => c)
      }.width('100%')
      Row({ space: 10 }) {
        Column() {
          ThickButton({
            label: '取消',
            kind: 'ghost',
            compact: true,
            onTap: (): void => {
              this.controller?.close();
            }
          })
        }.layoutWeight(1)

        Column() {
          ThickButton({
            label: '保存',
            kind: 'primary',
            compact: true,
            onTap: (): void => {
              this.controller?.close();
              if (this.onSave) {
                this.onSave(this.picked);
              }
            }
          })
        }.layoutWeight(1.2)
      }.width('100%')
    }
    .padding(18)
    .width('100%')
    .backgroundColor(Theme.CARD)
  }
}

/** 区域详情：该区域的房间 + 轨迹，支持开始记录 / 勾选导出 / 删除区域 */
/**
 * 云端上传设置：只填「地址」和（选填的）令牌。
 * 刻意不绑定任何云厂商 —— 地址换成局域网自建服务 / Cloudflare Worker / 对象存储签名接口都能用，
 * 后端返回什么就原样显示给用户（自建服务会返回保存路径与下载链接）。
 */
@CustomDialog
struct UploadSettingsDialog {
  controller?: CustomDialogController;
  onSave?: (url: string, token: string) => void;
  @State url: string = '';
  @State token: string = '';
  @State hint: string = '';

  build() {
    Column({ space: 12 }) {
      Text('云端上传设置').fontSize(19).fontWeight(FontWeight.Bold).width('100%').fontColor(Theme.INK)
      Text('填一个接收 POST 上传的地址。局域网自建服务、Cloudflare Worker、对象存储签名接口都可以，换后端不用改 App。')
        .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
      TextInput({ placeholder: 'http://192.168.1.5:8000/upload', text: this.url })
        .fontSize(13.5)
        .backgroundColor(Theme.CARD_SOFT)
        .borderRadius(14)
        .border({ width: 2, color: Theme.LINE })
        .onChange((v: string) => {
          this.url = v;
        })
      TextInput({ placeholder: '令牌（选填，会作为表单字段 token 一起发过去）', text: this.token })
        .fontSize(13.5)
        .backgroundColor(Theme.CARD_SOFT)
        .borderRadius(14)
        .border({ width: 2, color: Theme.LINE })
        .onChange((v: string) => {
          this.token = v;
        })
      if (this.hint.length > 0) {
        Text(this.hint).fontSize(Theme.F_META).fontColor(Theme.DANGER).width('100%')
      }
      Row({ space: 10 }) {
        PillButton({
          label: '取消',
          onTap: (): void => {
            this.controller?.close();
          }
        })
        PillButton({
          label: '保存',
          kind: 'solid',
          onTap: (): void => {
            this.save();
          }
        })
      }.width('100%').justifyContent(FlexAlign.End)
    }.padding(20).width('100%')
  }

  private save(): void {
    const u: string = this.url.trim();
    if (u.length > 0 && !u.startsWith('http://') && !u.startsWith('https://')) {
      this.hint = '地址要以 http:// 或 https:// 开头';
      return;
    }
    if (this.onSave) {
      this.onSave(u, this.token.trim());
    }
    this.controller?.close();
  }
}

@Component
export struct AreaDetailPage {
  areaId: number = UNASSIGNED_AREA_ID;
  onBack: () => void = () => {
  };
  onOpenRoom: (id: number) => void = (id: number) => {
  };
  onOpenTrack: (id: number) => void = (id: number) => {
  };
  @State area: Area | undefined = undefined;
  @State rooms: Room[] = [];
  @State tracks: Track[] = [];
  @State heartbeat: number = 0;
  /** 勾选导出模式：轨迹行显示复选框，可全选后只导出选中的几条 */
  @State selectMode: boolean = false;
  @State selectedIds: number[] = [];
  /** 上传设置（存在库里的 settings 表） */
  @State uploadUrl: string = '';
  @State uploadToken: string = '';
  @State uploading: boolean = false;
  /** 上传进度百分比；-1 表示还没有进度事件 */
  @State uploadPct: number = -1;
  /** 上一次上传的结果或失败原因：toast 两秒就没了，这里留痕（沿用录制横幅那条经验） */
  @State lastUploadMsg: string = '';
  /** 上面那条消息是不是成功（决定用中性色还是警示色） */
  @State lastUploadOk: boolean = true;
  private timer: number = -1;
  /** 上传设置对话框与「保存后是否接着上传」的暂存（控制器按点击时机创建，避免 @Prop 时序问题） */
  private settingsDialog: CustomDialogController | null = null;
  private pendingUpload: boolean = false;
  private pendingIds: number[] = [];

  private areaName(): string {
    if (this.areaId === UNASSIGNED_AREA_ID) {
      return '未分区';
    }
    return this.area ? this.area.name : '区域';
  }

  private isUnassigned(): boolean {
    return this.areaId === UNASSIGNED_AREA_ID;
  }

  /**
   * 轨迹区标题。
   *
   * 2026-10-08 起轨迹**不归属区域**，所以「本区域的轨迹」这种说法已经不成立了：
   * 这里列的是「**有节点落在这个区域**的轨迹」（`Store.listTracksTouchingArea`），
   * 一条跨楼轨迹会同时出现在它经过的每一栋楼里。标题照实写，免得用户以为
   * 「删了这栋楼里的轨迹 = 删掉了整条轨迹」。
   */
  private trackSectionTitle(): string {
    return this.isUnassigned()
      ? `涉及未分区节点的轨迹（${this.tracks.length}）`
      : `涉及本楼的轨迹（${this.tracks.length}）`;
  }

  /** 区域分类名（空串按「城市大学」显示，与首页分区的口径保持一致） */
  private areaCategoryLabel(): string {
    const c: string = this.area ? this.area.category : '';
    return c.length > 0 ? c : AREA_CATEGORY_CITYU;
  }

  private reload = (): void => {
    if (this.isUnassigned()) {
      this.area = {
        id: UNASSIGNED_AREA_ID,
        name: '未分区',
        note: '升级前的旧数据，尚未归属任何区域',
        category: '',
        roomCount: 0,
        trackCount: 0,
        createdAt: 0
      };
    } else {
      Store.getArea(this.areaId).then((a: Area | undefined) => {
        if (a) {
          this.area = a;
        }
      });
    }
    Store.listRooms(this.areaId).then((r: Room[]) => {
      this.rooms = r;
    });
    Store.listTracksTouchingArea(this.areaId).then((t: Track[]) => {
      this.tracks = t;
    });
  };

  aboutToAppear(): void {
    this.reload();
    this.loadUploadSettings();
    Store.subscribe(this.reload);
    this.timer = setInterval(() => {
      this.heartbeat++;
    }, 500);
  }

  aboutToDisappear(): void {
    Store.unsubscribe(this.reload);
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private addRoomDialog: CustomDialogController = new CustomDialogController({
    builder: AddRoomDialog({
      onSave: (name: string, code: string, note: string): void => {
        const n = name.trim();
        if (n.length === 0) {
          return;
        }
        // 加完不再自动跳进房间详情页（用户 2026-09-29 实测反馈：那个跳转是多余的），
        // 只提示一句；真想进去点列表里那一行即可。
        Store.insertRoom(n, note.trim(), this.areaId, code.trim()).then(() => {
          promptAction.showToast({ message: `已添加房间「${n}」` });
        });
      }
    }),
    customStyle: false
  });

  private startDialog: CustomDialogController | null = null;

  /** 打开时动态构造（成员初始化阶段 this.areaId 可能尚未赋值，须在点击时读取） */
  private openStartDialog(): void {
    this.startDialog = new CustomDialogController({
      builder: StartTrackDialog({
        onStart: (name: string): void => {
          TrackRecorder.get().start(name).catch(() => {
            promptAction.showToast({ message: '启动记录失败' });
          });
        }
      }),
      customStyle: false
    });
    this.startDialog.open();
  }

  // ---------- 改分类 ----------

  private categoryDialog: CustomDialogController | null = null;

  /** 同样按点击时机动态构造：this.area 是异步加载的，成员初始化阶段拿不到 */
  private openCategoryDialog(): void {
    const cur: string = this.areaCategoryLabel();
    this.categoryDialog = new CustomDialogController({
      builder: AreaCategoryDialog({
        current: cur,
        onSave: (c: string): void => {
          Store.updateAreaCategory(this.areaId, c).then(() => {
            promptAction.showToast({ message: `分类已改为「${c}」` });
          });
        }
      }),
      customStyle: false
    });
    this.categoryDialog.open();
  }

  // ---------- 导出 ----------
  // 原来右上角还有一个「导出」按钮（整区一键打包），与「选择导出 → 全选」重复，
  // 已按用户要求删掉：导出统一走勾选模式，全选即等于整区导出。

  private enterSelect(): void {
    this.selectedIds = [];
    this.selectMode = true;
  }

  private exitSelect(): void {
    this.selectMode = false;
    this.selectedIds = [];
  }

  private isSelected(id: number): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  private toggleSelect(id: number): void {
    const next: number[] = this.selectedIds.slice();
    const i: number = next.indexOf(id);
    if (i >= 0) {
      next.splice(i, 1);
    } else {
      next.push(id);
    }
    // 数组重新赋值，@State 才会通知刷新
    this.selectedIds = next;
  }

  private allSelected(): boolean {
    return this.tracks.length > 0 && this.selectedIds.length >= this.tracks.length;
  }

  private toggleSelectAll(): void {
    if (this.allSelected()) {
      this.selectedIds = [];
      return;
    }
    const ids: number[] = [];
    for (const t of this.tracks) {
      ids.push(t.id);
    }
    this.selectedIds = ids;
  }

  private exportSelected(): void {
    const ids: number[] = this.selectedIds.slice();
    if (ids.length === 0) {
      promptAction.showToast({ message: '请先勾选要导出的轨迹' });
      return;
    }
    const name = this.areaName();
    promptAction.showToast({ message: `正在打包所选 ${ids.length} 条轨迹…` });
    Exporter.exportTracksZip(ids, this.areaId, name).then((zipName: string) => {
      promptAction.showToast({ message: `已导出 ${zipName}` });
      this.exitSelect();
    }).catch((e: Error) => {
      promptAction.showToast({ message: e.message });
    });
  }

  // ---------- 上传到云端 ----------

  private loadUploadSettings(): void {
    Store.getSetting(UPLOAD_URL_KEY, '').then((v: string) => {
      this.uploadUrl = v;
    });
    Store.getSetting(UPLOAD_TOKEN_KEY, '').then((v: string) => {
      this.uploadToken = v;
    });
  }

  /** 「上传设置」入口：把当前值填进对话框；保存后若原本就想上传，则接着传 */
  private openUploadSettings(thenUpload: boolean): void {
    this.pendingUpload = thenUpload;
    this.pendingIds = this.selectedIds.slice();
    const dlg: CustomDialogController = new CustomDialogController({
      builder: UploadSettingsDialog({
        url: this.uploadUrl,
        token: this.uploadToken,
        onSave: (url: string, token: string): void => {
          this.applyUploadSettings(url, token);
        }
      })
    });
    this.settingsDialog = dlg;
    dlg.open();
  }

  private applyUploadSettings(url: string, token: string): void {
    this.uploadUrl = url;
    this.uploadToken = token;
    Store.setSetting(UPLOAD_URL_KEY, url).catch(() => {
    });
    Store.setSetting(UPLOAD_TOKEN_KEY, token).catch(() => {
    });
    promptAction.showToast({ message: url.length > 0 ? '上传设置已保存' : '已清空上传地址' });
    if (this.pendingUpload && url.length > 0 && this.pendingIds.length > 0) {
      this.pendingUpload = false;
      this.runUpload(this.pendingIds);
    }
  }

  /** 上传所选的若干条轨迹（打包成与「导出」完全相同的 zip，只是不发到手机而是发到服务器） */
  private uploadSelected(): void {
    const ids: number[] = this.selectedIds.slice();
    if (ids.length === 0) {
      promptAction.showToast({ message: '请先勾选要上传的轨迹' });
      return;
    }
    if (this.uploading) {
      return;
    }
    if (this.uploadUrl.trim().length === 0) {
      // 不做一个点了没反应的按钮：直接引导去填地址，填完自动接着传
      this.openUploadSettings(true);
      return;
    }
    this.runUpload(ids);
  }

  private runUpload(ids: number[]): void {
    this.uploading = true;
    this.uploadPct = -1;
    this.lastUploadOk = true;
    this.lastUploadMsg = '正在打包…';
    const name: string = this.areaName();
    let staged: StagedUpload | undefined = undefined;
    Exporter.stageForUpload(ids, this.areaId, name, (p: PackProgress) => {
      // 打包进度：既是「数据在动」的反馈，也是**打包中途出问题时的唯一线索**
      // （闪退会把 toast 一起带走，界面上留下的最后一条消息就指着正在处理的那个文件和大致的包大小）
      this.lastUploadMsg = `正在打包 ${p.done}/${p.total}：${p.note}`
        + `（约 ${(p.bytesTotal / 1048576).toFixed(1)} MB）`;
    }).then((s: StagedUpload) => {
      staged = s;
      this.lastUploadMsg = `正在上传 ${s.name}（${(s.bytes / 1048576).toFixed(1)} MB）…`;
      const target: UploadTarget = {
        url: this.uploadUrl,
        token: this.uploadToken,
        fieldName: Uploader.DEFAULT_FIELD
      };
      return Uploader.upload(s.name, target, (p: UploadProgress) => {
        this.uploadPct = p.total > 0 ? Math.floor(p.uploaded * 100 / p.total) : -1;
      });
    }).then((r: UploadResult) => {
      this.uploading = false;
      this.uploadPct = -1;
      this.lastUploadOk = r.ok;
      const detail: string = r.body.length > 180 ? `${r.body.substring(0, 180)}…` : r.body;
      this.lastUploadMsg = detail.length > 0 ? `${r.message}｜${detail}` : r.message;
      promptAction.showToast({ message: this.lastUploadMsg });
      if (r.ok && staged !== undefined) {
        // 成功才清缓存；失败时留着，方便对着错误信息重试
        Exporter.discardStaged(staged);
      }
    }).catch((e: Error) => {
      this.uploading = false;
      this.uploadPct = -1;
      this.lastUploadOk = false;
      this.lastUploadMsg = `打包/上传失败：${e.message}`;
      promptAction.showToast({ message: this.lastUploadMsg });
    });
  }

  private deleteArea(): void {
    promptAction.showDialog({
      title: `删除区域「${this.areaName()}」`,
      message: `房间 ${this.rooms.length} 个 · 有节点在这一区域的轨迹 ${this.tracks.length} 条。\n`
        // 2026-10-08：这段说明必须跟着模型改 —— 轨迹不再归属区域之后，「彻底删除」也
        // **不会**再删轨迹/采样点/照片了（只删这栋楼的房间与标记、把节点上的归属清掉）。
        // 原来那句「数据与照片将全部丢失」现在会让用户以为整条跨楼轨迹要没了，是吓人的假消息。
        + '移入未分区：节点与房间都保留，只是不再属于任何建筑；\n'
        + '彻底删除：这栋楼的房间与标记一起删掉，节点上的归属改成「未分区」——'
        + '轨迹本身、采样点、节点照片都不会被删。',
      buttons: [
        { text: '取消', color: Theme.INK2 },
        { text: '移入未分区', color: Theme.INK },
        { text: '彻底删除', color: Theme.DANGER }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        Store.moveAreaToUnassigned(this.areaId).then(() => {
          promptAction.showToast({ message: '已移入未分区' });
          this.onBack();
        });
      } else if (res.index === 2) {
        // 若正在记录该区域的轨迹，先停止，避免写入已删除的轨迹
        const rec = TrackRecorder.get();
        if (rec.isRunning()) {
          rec.stop().catch(() => {
          });
        }
        Store.deleteAreaCascade(this.areaId).then(() => {
          promptAction.showToast({ message: '区域已删除' });
          this.onBack();
        });
      }
    }).catch(() => {
    });
  }

  private trackSub(t: Track): string {
    const end = t.endedAt !== undefined ? t.endedAt : t.startedAt;
    let s =
      `${fmtTime(t.startedAt)} · 时长 ${fmtDuration(Math.floor((end - t.startedAt) / 1000))} · ${t.pointCount} 点`;
    if (t.endedAt === undefined) {
      s += ' · 进行中';
    }
    return s;
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        // 顶栏
        Row({ space: 8 }) {
          PillButton({
            label: '‹ 返回',
            onTap: (): void => {
              this.onBack();
            }
          })
          Column({ space: 1 }) {
            Text(this.areaName())
              .fontSize(Theme.F_TITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.INK)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.isUnassigned()
              ? `房间 ${this.rooms.length} · 有未分区节点的轨迹 ${this.tracks.length}`
              : `${this.areaCategoryLabel()} · 房间 ${this.rooms.length} · 涉及本楼的轨迹 ${this.tracks.length}`)
              .fontSize(Theme.F_META)
              .fontColor(Theme.INK2)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (!this.isUnassigned()) {
            // 点它改分类（自动归类万一归错了，这里是反悔入口）
            PillButton({
              label: this.areaCategoryLabel(),
              onTap: (): void => {
                this.openCategoryDialog();
              }
            })
            PillButton({
              label: '删除',
              kind: 'danger',
              onTap: (): void => {
                this.deleteArea();
              }
            })
          }
        }.width('100%').padding({ left: 14, right: 14, top: 12, bottom: 10 })

        RecordingBanner()

        Scroll() {
          Column({ space: Theme.GAP }) {
            // 房间
            Column({ space: 10 }) {
              Row() {
                Text(`房间（${this.rooms.length}）`).fontSize(Theme.F_SECTION)
                  .fontWeight(FontWeight.Bold).fontColor(Theme.INK)
                Blank()
                PillButton({
                  label: '添加房间',
                  onTap: (): void => {
                    this.addRoomDialog.open();
                  }
                })
              }.width('100%')
              if (this.rooms.length === 0) {
                Text('该区域还没有房间').fontSize(13).fontColor(Theme.INK2).width('100%')
              }
              ForEach(this.rooms, (r: Room) => {
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    // 教室代码放在名称前面（课表上写的就是代码，学生按代码找）
                    Text(r.code.length > 0 ? `${r.code} · ${r.name}` : r.name)
                      .fontSize(15).fontWeight(FontWeight.Medium).fontColor(Theme.INK)
                      .width('100%')
                    Text(r.note.length > 0 ? r.note : '点击打开，可添加前门/后门等标记')
                      .fontSize(Theme.F_META)
                      .fontColor(Theme.INK2)
                      .width('100%')
                  }.layoutWeight(1)
                  Text('›').fontSize(18).fontColor(Theme.INK3)
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
                .onClick(() => {
                  this.onOpenRoom(r.id);
                })
              }, (r: Room) => r.id + '')
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Theme.CARD)
            .borderRadius(Theme.R_CARD)
            .border({ width: 2, color: Theme.LINE })

            // 轨迹
            Column({ space: 10 }) {
              Row({ space: 8 }) {
                Text(this.selectMode
                  ? `已选 ${this.selectedIds.length} / ${this.tracks.length}`
                  : this.trackSectionTitle())
                  .fontSize(Theme.F_SECTION)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.INK)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.selectMode) {
                  PillButton({
                    label: this.allSelected() ? '取消全选' : '全选',
                    onTap: (): void => {
                      this.toggleSelectAll();
                    }
                  })
                  PillButton({
                    label: '取消',
                    onTap: (): void => {
                      this.exitSelect();
                    }
                  })
                } else if (this.tracks.length > 0) {
                  // 「开始记录」只在右下角 FAB 上保留一处（这里原来重复了一个，已删）
                  PillButton({
                    label: '选择导出',
                    onTap: (): void => {
                      this.enterSelect();
                    }
                  })
                }
              }.width('100%')

              if (this.selectMode) {
                Text('勾选后导出或上传，只处理选中的轨迹（含照片与 gallery.html 索引）')
                  .fontSize(Theme.F_META)
                  .fontColor(Theme.INK2)
                  .width('100%')
                Row({ space: 8 }) {
                  Column() {
                    ThickButton({
                      label: `导出所选（${this.selectedIds.length}）`,
                      kind: 'accent',
                      compact: true,
                      disabled: this.selectedIds.length === 0 || this.uploading,
                      onTap: (): void => {
                        this.exportSelected();
                      }
                    })
                  }.layoutWeight(1)
                  Column() {
                    ThickButton({
                      label: this.uploading
                        ? (this.uploadPct >= 0 ? `上传中 ${this.uploadPct}%` : '上传中…')
                        : `上传到云端（${this.selectedIds.length}）`,
                      compact: true,
                      disabled: this.selectedIds.length === 0 || this.uploading,
                      onTap: (): void => {
                        this.uploadSelected();
                      }
                    })
                  }.layoutWeight(1)
                }.width('100%')

                Row({ space: 8 }) {
                  PillButton({
                    label: '上传设置',
                    onTap: (): void => {
                      this.openUploadSettings(false);
                    }
                  })
                  Text(this.uploadUrl.length > 0 ? `已配置：${this.uploadUrl}` : '还没配置上传地址（点左边填）')
                    .fontSize(Theme.F_META)
                    .fontColor(Theme.INK2)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }.width('100%').alignItems(VerticalAlign.Center)

                if (this.lastUploadMsg.length > 0) {
                  Text(this.lastUploadMsg)
                    .fontSize(Theme.F_META)
                    .fontColor(this.uploading || this.lastUploadOk ? Theme.INK2 : Theme.DANGER)
                    .width('100%')
                }
              }

              if (this.tracks.length === 0) {
                Text(this.isUnassigned()
                  ? '还没有「未分区」的节点：记录节点时选了「（未分区）」的会出现在这里'
                  : '这栋楼还没有节点：记录轨迹时在这里打一个节点（门 / 门禁 / 教室…），'
                    + '这条轨迹就会出现在这里。轨迹本身不归属任何一栋楼 —— 一条轨迹可以跨好几栋楼')
                  .fontSize(13)
                  .fontColor(Theme.INK2)
                  .width('100%')
              }
              ForEach(this.tracks, (t: Track) => {
                Row({ space: 10 }) {
                  if (this.selectMode) {
                    Stack() {
                      if (this.isSelected(t.id)) {
                        Text('✓')
                          .fontSize(14)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(Theme.ON_RED)
                      }
                    }
                    .width(22)
                    .height(22)
                    .borderRadius(7)
                    .backgroundColor(this.isSelected(t.id) ? Theme.RED : Theme.CARD)
                    .border({
                      width: 2,
                      color: this.isSelected(t.id) ? Theme.RED_DEEP : Theme.LINE
                    })
                  }
                  Column({ space: 3 }) {
                    Text(t.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(Theme.INK)
                      .width('100%')
                    Text(this.trackSub(t)).fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
                  }.layoutWeight(1)
                  if (!this.selectMode) {
                    Text('›').fontSize(18).fontColor(Theme.INK3)
                  }
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
                .onClick(() => {
                  if (this.selectMode) {
                    this.toggleSelect(t.id);
                  } else {
                    this.onOpenTrack(t.id);
                  }
                })
              }, (t: Track) => t.id + '')
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Theme.CARD)
            .borderRadius(Theme.R_CARD)
            .border({ width: 2, color: Theme.LINE })

            if (this.area && this.area.note.length > 0 && !this.isUnassigned()) {
              Text(this.area.note).fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
            }
          }.padding({ left: Theme.PAD, right: Theme.PAD, bottom: 90 }).width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }.width('100%').height('100%')

      // FAB：未分区不允许开始记录；勾选导出模式下隐藏；记录中横幅自带停止按钮（心跳重建驱动刷新）
      ForEach([this.heartbeat], (h: number) => {
        if (!AppStorage.get<boolean>('rm_recording') && !this.isUnassigned() && !this.selectMode) {
          Button('开始记录')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.ON_RED)
            .backgroundColor(Theme.RED)
            .borderRadius(20)
            .height(54)
            .margin(Theme.PAD)
            .onClick(() => {
              this.openStartDialog();
            })
        }
      }, (h: number) => h + '')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
