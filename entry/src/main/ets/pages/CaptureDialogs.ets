import { Area, NodeDraft, Room, Track, TrackTag, roomBoundTagTypes, trackTagNames, TrackTagType } from '../data/Entities';
import { Store, UNASSIGNED_AREA_ID } from '../data/Store';
import { cityuFloors } from '../common/Campus';
import { effectiveAreaId } from '../common/RoomPlan';
import { FloorGuess, FloorProbe, guessLabel } from '../common/FloorMatch';
import { floorKey } from '../common/Track3D';
import { fmtTime } from '../common/Utils';
import { Theme } from '../common/Theme';
import { PillButton, ThickButton } from '../common/Widgets';

/**
 * 节点对话框「正文滚动区」的最大高度（vp）。
 * 用死值而不是百分比：CustomDialog 里用百分比做 maxHeight 的参考系不明确，
 * 有可能算成 0 把内容整个压没。460 在常见手机上都留得下底部的按钮行；
 * 内容没这么高时 Scroll 会自然收缩到内容高度，不会留白。
 */
const DIALOG_BODY_MAX: number = 460;

/**
 * 「记录节点」对话框：先选区域 + 类型 + 写备注 + 选楼层（可点选也可手填），点「拍照并保存」才调相机
 * —— 照片是节点信息的必填部分（相机取消则节点不落库）。
 *
 * 流程方向：先填后拍，对话框只往外抛回调，不需要把外部数据传进来。
 *
 * 区域（2026-09-29 新增，用户实测后提出）：一条轨迹可以从校外一路穿过好几栋楼，
 * 轨迹只挂一个区域不够用。所以每个节点自己带区域：默认沿用这条轨迹的区域，
 * 途中换楼就在这儿点一下切过去——节点各归各楼，「生成房间」也按这个分楼建。
 *
 * 楼层：给一排城大常用楼层（LG/F、G/F、1/F…）点一下即可，也可以直接在输入框手填。
 * 另外（2026-09-29 用户新增要求）：**如果这一栋楼里已经记过某个楼层的高度，就按当前实测高度
 * 自动带出那个楼层**（"检测到在案的楼层高度就默认那个楼层，当然也支持手动修改"）。
 * 只在这栋楼的楼层高度索引里查得到、且用户还没自己填过时才带 —— 查不到就一个字都不猜。
 * 判定逻辑全在 common/FloorMatch（纯函数），这里只负责拿实测快照、显示提示。
 * 房间（2026-09-29 放宽）：标记「门 / 门禁」时**可选**绑一个房间；绑了就照旧往该房间插一条
 * 「前门 / 后门」标记，不绑就是一个归属该区域的建筑大门 / 出入口（原来强制必绑，
 * 结果被逼着在每栋楼里建一个假的「大门房间」，跟「区域＝一栋楼」的模型打架）。
 * 类型（2026-09-29 扩充）：新增「大门 / 食堂 / 商店 / 其他室内」，共 11 种；
 * 「大门」是建筑级出入口，**不绑房间**，所以标它时不会出现「所属房间」那一栏。
 * 布局（2026-09-29）：正文放进带最大高度的 Scroll、底部按钮固定在滚动区外 ——
 * 类型变多之后（标门/门禁还要多一栏房间），矮屏上内容会顶出屏幕，按钮就点不到了。
 */
@CustomDialog
export struct TrackTagDialog {
  controller?: CustomDialogController;
  onSave?: (draft: NodeDraft) => void;
  /** 当前正在记录的轨迹 id（用它查出所属区域，进而列出可选区域与房间） */
  trackIdProvider: () => number = () => -1;
  /** 当前实测高度（气压/海拔）的提供者：楼层自动带出要用，取的是「点开对话框这一刻」的快照 */
  floorProbeProvider: () => FloorProbe = (): FloorProbe => {
    const p: FloorProbe = { pressureHpa: undefined, altitude: undefined };
    return p;
  };
  @State note: string = '';
  @State floor: string = '';
  /** 按高度推测出来的提示文案（空串 = 没推测出来，或用户已经自己填了）；只是提示，随时可改 */
  @State floorGuess: string = '';
  /** 当前填的楼层是不是「自动带出来的」（用户一改就不再算自动带出的） */
  private floorAuto: boolean = false;
  /** 默认选中类型 = 类型网格的第一项（与改版顺序保持一致） */
  @State tagType: string = TrackTagType.MAIN_GATE;
  /** 区域下拉的文案，与 areaIds 一一对应；文案为「（未分区）」时 id 是 -1 */
  @State areaNames: string[] = [];
  @State areaIds: number[] = [];
  @State selAreaIdx: number = 0;
  @State rooms: Room[] = [];
  /** 房间下选框的选中下标：0 = 不绑定房间（建筑大门），i>0 对应 rooms[i-1] */
  @State selRoom: number = 0;

  aboutToAppear(): void {
    // 这个对话框的控制器是被复用的（见 RecordingBanner.ensureDialogs），
    // 所以进来先把「每个节点各不相同」的几栏显式复位，免得沿用上一个节点填过的值。
    this.note = '';
    this.floor = '';
    this.floorGuess = '';
    this.floorAuto = false;
    this.tagType = TrackTagType.MAIN_GATE;
    this.selRoom = 0;
    const tid: number = this.trackIdProvider();
    if (tid < 0) {
      return;
    }
    Store.getTrack(tid).then((t: Track | undefined) => {
      const trackArea: number = (t !== undefined && t.areaId !== undefined) ? t.areaId : -1;
      return Store.listAreas().then((list: Area[]) => {
        const names: string[] = [];
        const ids: number[] = [];
        if (trackArea <= 0) {
          // 这条轨迹还没分区（旧数据）：给一个「未分区」选项，默认选它，不偷偷改归属
          names.push('（未分区）');
          ids.push(-1);
        }
        for (const a of list) {
          names.push(a.name);
          ids.push(a.id);
        }
        this.areaNames = names;
        this.areaIds = ids;
        let idx = 0;
        for (let i = 0; i < ids.length; i++) {
          if (ids[i] === trackArea) {
            idx = i;
            break;
          }
        }
        this.selAreaIdx = idx;
        this.reloadRooms();
        this.suggestFloor();
      });
    });
  }

  /**
   * 按「这栋楼已经记过的楼层高度」推测当前节点在哪一层，并带出来。
   * 只在用户还没自己填过（或之前那次是自动带出来的）时才动这一栏 —— 绝不覆盖手填的值。
   * 查不到就什么都不做（FloorMatch 的口径是「宁可不说，也不猜」）。
   */
  private suggestFloor(): void {
    if (this.floor.length > 0 && !this.floorAuto) {
      return;
    }
    const aId: number = this.currentAreaId();
    if (aId <= 0) {
      this.floorGuess = '';
      return;
    }
    const probe: FloorProbe = this.floorProbeProvider();
    Store.matchFloorHeight(aId, probe).then((g: FloorGuess) => {
      if (g.floor.length === 0) {
        this.floorGuess = '';
        return;
      }
      this.floor = g.floor;
      this.floorAuto = true;
      this.floorGuess = guessLabel(g);
    });
  }

  /** 用户自己动了楼层这一栏：以后就不再自动带出（他的填写优先） */
  private setFloorManually(v: string): void {
    this.floor = v;
    this.floorAuto = false;
    this.floorGuess = '';
  }

  /** 当前选中的区域 id；-1 = 未分区 */
  private currentAreaId(): number {
    if (this.selAreaIdx < 0 || this.selAreaIdx >= this.areaIds.length) {
      return -1;
    }
    return this.areaIds[this.selAreaIdx];
  }

  private currentAreaName(): string {
    const id: number = this.currentAreaId();
    if (id <= 0 || this.selAreaIdx < 0 || this.selAreaIdx >= this.areaNames.length) {
      return '';
    }
    return this.areaNames[this.selAreaIdx];
  }

  /** 换区域后重新拉这个区域的房间（门/门禁的候选房间要跟着换楼） */
  private reloadRooms(): void {
    const aId: number = this.currentAreaId();
    this.selRoom = 0;
    Store.listRooms(aId <= 0 ? UNASSIGNED_AREA_ID : aId).then((rs: Room[]) => {
      this.rooms = rs;
    });
  }

  /** 区域下选框选项。用「先声明数组再 push 字面量」的写法（ArkUI 里已验证过），别用 map + as */
  private areaOptions(): Array<SelectOption> {
    const out: SelectOption[] = [];
    for (const n of this.areaNames) {
      out.push({ value: n });
    }
    return out;
  }

  /** 这个类型能不能绑房间（门 / 门禁可以，但不再必须） */
  private canBindRoom(): boolean {
    return roomBoundTagTypes().indexOf(this.tagType) >= 0;
  }

  private roomOptions(): Array<SelectOption> {
    const out: SelectOption[] = [{ value: '不绑定房间（建筑大门 / 出入口）' }];
    for (const r of this.rooms) {
      out.push({ value: r.name });
    }
    return out;
  }

  private roomLabel(): string {
    if (this.selRoom <= 0 || this.selRoom > this.rooms.length) {
      return '不绑定房间（建筑大门 / 出入口）';
    }
    return this.rooms[this.selRoom - 1].name;
  }

  private pickedRoomId(): number {
    if (this.selRoom <= 0 || this.selRoom > this.rooms.length) {
      return -1;
    }
    return this.rooms[this.selRoom - 1].id;
  }

  private submit(): void {
    const tagType: string = this.tagType;
    const note: string = this.note.trim();
    const floor: string = this.floor.trim();
    const areaId: number = this.currentAreaId();
    const areaName: string = this.currentAreaName();
    // 只有门/门禁会带房间；其它类型一律 -1（不写标记）
    const roomId: number = this.canBindRoom() ? this.pickedRoomId() : -1;
    const roomName: string = roomId > 0 ? this.roomLabel() : '';
    // 用局部变量拼这个字面量（而不是直接写 this.xxx）：离线的类型检查能把 UI 文件里的
    // 「带类型字面量」抠出来单独编译，引用 this 的那些抠不出来，写成局部变量就能被覆盖到了
    const draft: NodeDraft = {
      tagType: tagType,
      note: note,
      floor: floor,
      areaId: areaId,
      areaName: areaName,
      roomId: roomId,
      roomName: roomName
    };
    this.controller?.close();
    if (this.onSave) {
      this.onSave(draft);
    }
  }

  build() {
    // 正文放进 Scroll、底部按钮固定在滚动区外。
    // 原因：节点类型加到 11 种、标「门 / 门禁」时还会多出一整栏「所属房间」，
    // 小屏上内容会顶出屏幕，原来那种一整块 Column 会把「拍照并保存」挤到看不见的地方。
    Column() {
      Scroll() {
        Column({ space: 12 }) {
          Text('记录节点').fontSize(19).fontWeight(FontWeight.Bold).width('100%').fontColor(Theme.INK)
          Text('选好类型并写清备注，点下面按钮就调相机拍下这个节点。照片是节点信息的一部分，相机取消则不记录。')
            .fontSize(Theme.F_META)
            .fontColor(Theme.INK2)
            .width('100%')

          // 类型选择：3 列网格，选中态用深红实心（图标在此处不用，白色描边在深红底上不可见）
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(trackTagNames(), (name: string) => {
              Text(name)
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .textAlign(TextAlign.Center)
                .width('31.5%')
                .padding({ top: 10, bottom: 10 })
                .fontColor(this.tagType === name ? Theme.ON_RED : Theme.INK)
                .backgroundColor(this.tagType === name ? Theme.RED : Theme.CARD_SOFT)
                .borderRadius(14)
                .border({
                  width: 2,
                  color: this.tagType === name ? Theme.RED_DEEP : Theme.LINE
                })
                .margin({ bottom: 8 })
                .onClick(() => {
                  this.tagType = name;
                })
            }, (name: string) => name)
          }.width('100%')

          // 区域：默认沿用这条轨迹的区域，跨楼时在这里切（节点各归各楼）
          Text('所在建筑 / 区域（跨楼时在这儿切换）').fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
          if (this.areaNames.length === 0) {
            Text('还没有区域：先在首页导入城大建筑或新建区域，这个节点会先记成未分区。')
              .fontSize(Theme.F_META).fontColor(Theme.DANGER).width('100%')
          } else {
            Select(this.areaOptions())
              .selected(this.selAreaIdx)
              .value(this.areaNames[this.selAreaIdx])
              .font({ size: 13.5 })
              .width('100%')
              .onSelect((index: number) => {
                this.selAreaIdx = index;
                this.reloadRooms();
                // 换了楼就按那栋楼已记过的楼层高度重新带一次（手填过的不会被覆盖）
                this.suggestFloor();
              })
          }

          TextInput({ placeholder: '备注（如：西侧楼梯口，上去是四楼平台）' })
            .fontSize(13.5)
            .backgroundColor(Theme.CARD_SOFT)
            .borderRadius(14)
            .border({ width: 2, color: Theme.LINE })
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .onChange((v: string) => {
              this.note = v;
            })

          // 楼层：点选城大常用楼层，也可以直接手填（各楼实际层数不同，不做限制）
          Text('楼层（点一下即选，也可以手填）').fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(cityuFloors(), (f: string) => {
              Text(f)
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.floor === f ? Theme.ON_RED : Theme.BLUE_DEEP)
                .backgroundColor(this.floor === f ? Theme.RED : Theme.BLUE_SOFT)
                .borderRadius(Theme.R_CHIP)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .margin({ right: 6, bottom: 6 })
                .onClick(() => {
                  this.setFloorManually(this.floor === f ? '' : f);
                })
            }, (f: string) => f)
          }.width('100%')
          TextInput({ text: this.floor, placeholder: '楼层（选填，如 3 或 3/F）' })
            .fontSize(13.5)
            .backgroundColor(Theme.CARD_SOFT)
            .borderRadius(14)
            .border({ width: 2, color: Theme.LINE })
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .onChange((v: string) => {
              this.setFloorManually(v);
            })
          // 自动带出来的楼层：明说这是推测、可以改（空串则整行不显示）
          if (this.floorGuess.length > 0) {
            Text(`${this.floorGuess}　—　它来自这栋楼里已经记过的楼层高度`)
              .fontSize(Theme.F_META)
              .fontColor(Theme.BLUE_DEEP)
              .width('100%')
          }

          // 房间：门 / 门禁可选绑定；默认「不绑定」＝建筑大门/出入口。
          // 「大门」类型不在这个分支里，所以标大门时这一栏根本不出现。
          if (this.canBindRoom()) {
            Text('所属房间（选填：建筑大门就不用绑）').fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
            if (this.rooms.length === 0) {
              Text(this.currentAreaId() <= 0
                ? '还没选到具体区域：建筑大门可以直接保存；房间门请先选区域并添加房间。'
                : '该区域还没有房间：建筑大门可以直接保存；房间门请先到区域页添加房间。')
                .fontSize(Theme.F_META)
                .fontColor(Theme.INK2)
                .width('100%')
            } else {
              Select(this.roomOptions())
                .selected(this.selRoom)
                .value(this.roomLabel())
                .font({ size: 13.5 })
                .width('100%')
                .onSelect((index: number) => {
                  this.selRoom = index;
                })
              Text('绑了房间就记成这个房间的门（备注里带「后」字算后门）；选「不绑定」就只当作建筑大门。')
                .fontSize(Theme.F_META)
                .fontColor(Theme.INK3)
                .width('100%')
            }
          }
        }
        .padding({ left: 18, right: 18, top: 18, bottom: 6 })
        .width('100%')
      }
      .width('100%')
      .scrollBar(BarState.Auto)
      // 上限用死值 vp：CustomDialog 里用百分比做 maxHeight 参考系不明确（可能算成 0 把内容压没）。
      // 内容没这么高时 Scroll 会自然收缩到内容高度，不会留白。
      .constraintSize({ maxHeight: DIALOG_BODY_MAX })

      // 操作按钮固定在底部：正文再长也点得到
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
            label: '拍照并保存',
            kind: 'accent',
            compact: true,
            onTap: (): void => {
              this.submit();
            }
          })
        }.layoutWeight(1.5)
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 6, bottom: 18 })
    }
    .width('100%')
    .backgroundColor(Theme.CARD)
  }
}

/**
 * 「修改节点」对话框（2026-09-29 用户要求：实地采集后发现有些标点记错了，要能在 APP 里改）。
 *
 * 能改的：类型 / 备注 / 楼层 / 所在区域 / 所属房间（门、门禁）；还能整个删掉这个节点
 * （连同它的节点照片一起删，不留孤儿照片）。
 * **不能改的：位置**（经纬度、海拔、气压）。那是实测值，本轮口径就是「先不做改位置」——
 * 手改坐标会让「实测」二字失去意义，位置错了应该重新去那里采一个点。
 *
 * 为什么用「提供者」而不是直接把节点传进来：对话框控制器是被复用的一个实例，
 * 直接传值只会在第一次创建时取到，之后点别的节点还是老数据。提供者在每次 aboutToAppear
 * 时重新取当前节点，这也是 RecordingBanner 那边 trackIdProvider 的同一套做法。
 *
 * 楼层也一样支持「按高度推测」（与记录节点时同一条口径）：这里**不覆盖**已填的值，
 * 只在推测结果和现有值不同时显示一行可点的提示，点了才填进去。
 */
@CustomDialog
export struct EditNodeDialog {
  controller?: CustomDialogController;
  onSave?: (tagId: number, draft: NodeDraft) => void;
  onDelete?: (tagId: number) => void;
  tagProvider: () => TrackTag | undefined = (): TrackTag | undefined => undefined;
  /** 这个节点当前绑定的房间 id（页面查出来传进来，用于把下拉预选到那个房间）；-1 = 没绑 */
  boundRoomProvider: () => number = () => -1;
  /** 节点所属轨迹的区域 id（节点自己没写区域时沿用）；0 = 未分区 */
  trackAreaIdProvider: () => number = () => 0;

  @State tagId: number = -1;
  @State tagType: string = TrackTagType.MAIN_GATE;
  @State note: string = '';
  @State floor: string = '';
  @State summary: string = '';
  @State areaNames: string[] = [];
  @State areaIds: number[] = [];
  @State selAreaIdx: number = 0;
  @State rooms: Room[] = [];
  @State selRoom: number = 0;
  /** 推测出来的楼层值（点那行提示才填进「楼层」栏），以及提示文案 */
  @State guessFloor: string = '';
  @State guessText: string = '';
  /** 老数据：这个门 / 门禁节点没记下「绑的是哪条房间标记」，改绑时清不掉旧房间里的标记 */
  @State legacyBinding: boolean = false;
  private boundRoom: number = -1;

  aboutToAppear(): void {
    this.tagId = -1;
    this.tagType = TrackTagType.MAIN_GATE;
    this.note = '';
    this.floor = '';
    this.summary = '';
    this.areaNames = [];
    this.areaIds = [];
    this.selAreaIdx = 0;
    this.rooms = [];
    this.selRoom = 0;
    this.guessFloor = '';
    this.guessText = '';
    this.legacyBinding = false;
    this.boundRoom = this.boundRoomProvider();

    const g: TrackTag | undefined = this.tagProvider();
    if (g === undefined) {
      return;
    }
    this.tagId = g.id;
    this.tagType = g.tagType;
    this.note = g.note;
    this.floor = g.floor;
    this.summary = fmtTime(g.timeMs);
    this.legacyBinding = roomBoundTagTypes().indexOf(g.tagType) >= 0 && g.markerId === undefined;

    Store.listAreas().then((list: Area[]) => {
      // 这里**总是**把「（未分区）」放在第一项：编辑时得有个地方能把区域清掉
      // （记录时的下拉没有这一项，因为那时默认沿用轨迹的区域）
      const names: string[] = ['（未分区）'];
      const ids: number[] = [-1];
      for (const a of list) {
        names.push(a.name);
        ids.push(a.id);
      }
      this.areaNames = names;
      this.areaIds = ids;
      const cur: number = effectiveAreaId(g, this.trackAreaIdProvider());
      let idx = 0;
      for (let i = 0; i < ids.length; i++) {
        if (ids[i] === cur) {
          idx = i;
          break;
        }
      }
      this.selAreaIdx = idx;
      this.reloadRooms();
      this.suggestFloor(g);
    });
  }

  private currentAreaId(): number {
    if (this.selAreaIdx < 0 || this.selAreaIdx >= this.areaIds.length) {
      return -1;
    }
    return this.areaIds[this.selAreaIdx];
  }

  private currentAreaName(): string {
    const id: number = this.currentAreaId();
    if (id <= 0 || this.selAreaIdx < 0 || this.selAreaIdx >= this.areaNames.length) {
      return '';
    }
    return this.areaNames[this.selAreaIdx];
  }

  /** 换区域后重新拉房间，并预选回这个节点当前绑定的那个房间 */
  private reloadRooms(): void {
    const aId: number = this.currentAreaId();
    this.selRoom = 0;
    Store.listRooms(aId <= 0 ? UNASSIGNED_AREA_ID : aId).then((rs: Room[]) => {
      this.rooms = rs;
      for (let i = 0; i < rs.length; i++) {
        if (rs[i].id === this.boundRoom) {
          this.selRoom = i + 1;
          break;
        }
      }
    });
  }

  /** 按这栋楼已记过的楼层高度推测楼层；只出提示，不覆盖已填的值 */
  private suggestFloor(g: TrackTag): void {
    this.guessFloor = '';
    this.guessText = '';
    const aId: number = this.currentAreaId();
    if (aId <= 0) {
      return;
    }
    const probe: FloorProbe = { pressureHpa: g.pressureHpa, altitude: g.altitude };
    Store.matchFloorHeight(aId, probe).then((r: FloorGuess) => {
      if (r.floor.length === 0) {
        return;
      }
      if (floorKey(r.floor) === floorKey(this.floor)) {
        return; // 推测结果和已填的一样，没必要提示
      }
      this.guessFloor = r.floor;
      this.guessText = guessLabel(r);
    });
  }

  private areaOptions(): Array<SelectOption> {
    const out: SelectOption[] = [];
    for (const n of this.areaNames) {
      out.push({ value: n });
    }
    return out;
  }

  private canBindRoom(): boolean {
    return roomBoundTagTypes().indexOf(this.tagType) >= 0;
  }

  private roomOptions(): Array<SelectOption> {
    const out: SelectOption[] = [{ value: '不绑定房间（建筑大门 / 出入口）' }];
    for (const r of this.rooms) {
      out.push({ value: r.name });
    }
    return out;
  }

  private roomLabel(): string {
    if (this.selRoom <= 0 || this.selRoom > this.rooms.length) {
      return '不绑定房间（建筑大门 / 出入口）';
    }
    return this.rooms[this.selRoom - 1].name;
  }

  private pickedRoomId(): number {
    if (this.selRoom <= 0 || this.selRoom > this.rooms.length) {
      return -1;
    }
    return this.rooms[this.selRoom - 1].id;
  }

  private submit(): void {
    const tagType: string = this.tagType;
    const note: string = this.note.trim();
    const floor: string = this.floor.trim();
    const areaId: number = this.currentAreaId();
    const areaName: string = this.currentAreaName();
    const roomId: number = this.canBindRoom() ? this.pickedRoomId() : -1;
    const roomName: string = roomId > 0 ? this.roomLabel() : '';
    const draft: NodeDraft = {
      tagType: tagType,
      note: note,
      floor: floor,
      areaId: areaId,
      areaName: areaName,
      roomId: roomId,
      roomName: roomName
    };
    const id: number = this.tagId;
    this.controller?.close();
    if (this.onSave) {
      this.onSave(id, draft);
    }
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 12 }) {
          Text('修改节点').fontSize(19).fontWeight(FontWeight.Bold).width('100%').fontColor(Theme.INK)
          Text(`采集时间 ${this.summary}。填错的类型 / 备注 / 楼层 / 区域 / 所属房间都能在这儿改；`
            + `位置是实测值，不能在这里改。`)
            .fontSize(Theme.F_META)
            .fontColor(Theme.INK2)
            .width('100%')

          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(trackTagNames(), (name: string) => {
              Text(name)
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .textAlign(TextAlign.Center)
                .width('31.5%')
                .padding({ top: 10, bottom: 10 })
                .fontColor(this.tagType === name ? Theme.ON_RED : Theme.INK)
                .backgroundColor(this.tagType === name ? Theme.RED : Theme.CARD_SOFT)
                .borderRadius(14)
                .border({ width: 2, color: this.tagType === name ? Theme.RED_DEEP : Theme.LINE })
                .margin({ bottom: 8 })
                .onClick(() => {
                  this.tagType = name;
                })
            }, (name: string) => name)
          }.width('100%')

          Text('所在建筑 / 区域').fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
          if (this.areaNames.length === 0) {
            Text('还没有区域：先在首页导入城大建筑或新建区域。')
              .fontSize(Theme.F_META).fontColor(Theme.DANGER).width('100%')
          } else {
            Select(this.areaOptions())
              .selected(this.selAreaIdx)
              .value(this.areaNames[this.selAreaIdx])
              .font({ size: 13.5 })
              .width('100%')
              .onSelect((index: number) => {
                this.selAreaIdx = index;
                this.reloadRooms();
              })
          }

          Text('备注').fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
          TextInput({ text: this.note, placeholder: '备注（如：西侧楼梯口，上去是四楼平台）' })
            .fontSize(13.5)
            .backgroundColor(Theme.CARD_SOFT)
            .borderRadius(14)
            .border({ width: 2, color: Theme.LINE })
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .onChange((v: string) => {
              this.note = v;
            })

          Text('楼层（点一下即选，也可以手填）').fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(cityuFloors(), (f: string) => {
              Text(f)
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.floor === f ? Theme.ON_RED : Theme.BLUE_DEEP)
                .backgroundColor(this.floor === f ? Theme.RED : Theme.BLUE_SOFT)
                .borderRadius(Theme.R_CHIP)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .margin({ right: 6, bottom: 6 })
                .onClick(() => {
                  this.floor = this.floor === f ? '' : f;
                  this.guessFloor = '';
                  this.guessText = '';
                })
            }, (f: string) => f)
          }.width('100%')
          TextInput({ text: this.floor, placeholder: '楼层（选填，如 3 或 3/F）' })
            .fontSize(13.5)
            .backgroundColor(Theme.CARD_SOFT)
            .borderRadius(14)
            .border({ width: 2, color: Theme.LINE })
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .onChange((v: string) => {
              this.floor = v;
              this.guessFloor = '';
              this.guessText = '';
            })
          // 推测结果只作提示，点一下才用（编辑时不覆盖你填的值）
          if (this.guessText.length > 0) {
            Text(`${this.guessText}　—　点这里改用 ${this.guessFloor}`)
              .fontSize(Theme.F_META)
              .fontColor(Theme.BLUE_DEEP)
              .width('100%')
              .onClick(() => {
                this.floor = this.guessFloor;
                this.guessFloor = '';
                this.guessText = '';
              })
          }

          if (this.canBindRoom()) {
            Text('所属房间（选填：建筑大门就不用绑）').fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
            if (this.rooms.length === 0) {
              Text(this.currentAreaId() <= 0
                ? '还没选到具体区域：建筑大门可以直接保存；房间门请先选区域并添加房间。'
                : '该区域还没有房间：建筑大门可以直接保存；房间门请先到区域页添加房间。')
                .fontSize(Theme.F_META)
                .fontColor(Theme.INK2)
                .width('100%')
            } else {
              Select(this.roomOptions())
                .selected(this.selRoom)
                .value(this.roomLabel())
                .font({ size: 13.5 })
                .width('100%')
                .onSelect((index: number) => {
                  this.selRoom = index;
                })
              Text('换了房间会把这个节点在这个房间里的「前门 / 后门」标记一起搬过去；'
                + '选「不绑定」就把标记删掉。')
                .fontSize(Theme.F_META)
                .fontColor(Theme.INK3)
                .width('100%')
            }
            if (this.legacyBinding) {
              Text('这条节点是 2026-09-29 之前采的，没记下它绑的是哪条房间标记：'
                + '改房间能建新的，但旧房间里的那条标记删不掉 —— 之后到那个房间手动删一下。')
                .fontSize(Theme.F_META)
                .fontColor(Theme.DANGER)
                .width('100%')
            }
          }
        }
        .padding({ left: 18, right: 18, top: 18, bottom: 6 })
        .width('100%')
      }
      .width('100%')
      .scrollBar(BarState.Auto)
      .constraintSize({ maxHeight: DIALOG_BODY_MAX })

      // 删除单独一行放在按钮上方：破坏性操作离「保存」远一点，免得点错
      Row() {
        PillButton({
          label: '删除这个节点（含它的照片）',
          kind: 'danger',
          onTap: (): void => {
            const id: number = this.tagId;
            this.controller?.close();
            if (this.onDelete) {
              this.onDelete(id);
            }
          }
        })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 6 })

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
            label: '保存修改',
            kind: 'accent',
            compact: true,
            onTap: (): void => {
              this.submit();
            }
          })
        }.layoutWeight(1.4)
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 10, bottom: 18 })
    }
    .width('100%')
    .backgroundColor(Theme.CARD)
  }
}

/** 「拍风景照」对话框：只作宣传美化用，不参与节点体系，备注可留空 */
@CustomDialog
export struct SceneryDialog {
  controller?: CustomDialogController;
  onSave?: (note: string) => void;
  @State note: string = '';

  build() {
    Column({ space: 14 }) {
      Text('拍风景照').fontSize(19).fontWeight(FontWeight.Bold).width('100%').fontColor(Theme.INK)
      Text('用于宣传美化，不计入节点，也不出现在路引的节点信息里。备注可留空。')
        .fontSize(Theme.F_META)
        .fontColor(Theme.INK2)
        .width('100%')

      TextInput({ placeholder: '备注（选填，如：中庭采光井）' })
        .fontSize(13.5)
        .backgroundColor(Theme.CARD_SOFT)
        .borderRadius(14)
        .border({ width: 2, color: Theme.LINE })
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onChange((v: string) => {
          this.note = v;
        })

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
            label: '拍照',
            kind: 'primary',
            compact: true,
            onTap: (): void => {
              this.controller?.close();
              if (this.onSave) {
                this.onSave(this.note.trim());
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
