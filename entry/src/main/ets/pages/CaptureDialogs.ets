import { promptAction } from '@kit.ArkUI';
import { NodeDraft, roomBoundTagTypes, trackTagNames, TrackTagType } from '../data/Entities';
import { Room, Track } from '../data/Entities';
import { Store, UNASSIGNED_AREA_ID } from '../data/Store';
import { cityuFloors } from '../common/Campus';
import { Theme } from '../common/Theme';
import { ThickButton } from '../common/Widgets';

/**
 * 「记录节点」对话框：先选类型 + 写备注 + 选楼层（可点选也可手填），点「拍照并保存」才调相机
 * —— 照片是节点信息的必填部分（相机取消则节点不落库）。
 *
 * 流程方向：先填后拍，对话框只往外抛回调，不需要把外部数据传进来。
 *
 * 楼层：给一排城大常用楼层（LG/F、G/F、1/F…）点一下即可，也可以直接在输入框手填。
 * 房间：标记「门 / 门禁」时**必须**选一个房间（用户 2026-09-28 要求把门和房间绑到一起），
 *      列表从这条轨迹所属区域里取；保存后会往该房间插一条「前门 / 后门」标记。
 */
@CustomDialog
export struct TrackTagDialog {
  controller?: CustomDialogController;
  onSave?: (draft: NodeDraft) => void;
  /** 当前正在记录的轨迹 id（用它查出所属区域，进而列出可选房间） */
  trackIdProvider: () => number = () => -1;
  @State note: string = '';
  @State floor: string = '';
  @State tagType: string = TrackTagType.TOILET;
  @State rooms: Room[] = [];
  /** 房间下选框的选中下标：0 = 还没选（占位项），i>0 对应 rooms[i-1] */
  @State selRoom: number = 0;

  aboutToAppear(): void {
    const tid: number = this.trackIdProvider();
    if (tid < 0) {
      return;
    }
    Store.getTrack(tid).then((t: Track | undefined) => {
      if (t === undefined) {
        return;
      }
      const aId: number = t.areaId === undefined ? UNASSIGNED_AREA_ID : t.areaId;
      return Store.listRooms(aId).then((rs: Room[]) => {
        this.rooms = rs;
      });
    });
  }

  /** 这个类型要不要绑定房间（门 / 门禁要，其它不要） */
  private needsRoom(): boolean {
    return roomBoundTagTypes().indexOf(this.tagType) >= 0;
  }

  private roomOptions(): Array<SelectOption> {
    const out: SelectOption[] = [{ value: '请选择房间…' }];
    for (const r of this.rooms) {
      out.push({ value: r.name });
    }
    return out;
  }

  private roomLabel(): string {
    if (this.selRoom <= 0 || this.selRoom > this.rooms.length) {
      return '请选择房间…';
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
    if (this.needsRoom()) {
      if (this.rooms.length === 0) {
        promptAction.showToast({ message: '该区域还没有房间，请先在区域页添加房间' });
        return;
      }
      if (this.pickedRoomId() < 0) {
        promptAction.showToast({ message: '请选择这个门所属的房间' });
        return;
      }
    }
    const roomId: number = this.pickedRoomId();
    const roomName: string = this.roomLabel();
    // 用局部变量拼这个字面量（而不是直接写 this.xxx）：离线的类型检查能把 UI 文件里的
    // 「带类型字面量」抠出来单独编译，引用 this 的那些抠不出来，写成局部变量就能被覆盖到了
    const draft: NodeDraft = {
      tagType: tagType,
      note: note,
      floor: floor,
      roomId: roomId,
      roomName: roomName
    };
    this.controller?.close();
    if (this.onSave) {
      this.onSave(draft);
    }
  }

  build() {
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
              this.floor = this.floor === f ? '' : f;
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
        })

      // 房间：门 / 门禁必须归属一个房间，保存后会往该房间写一条「前门 / 后门」标记
      if (this.needsRoom()) {
        Text('所属房间（门 / 门禁必须选）').fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
        if (this.rooms.length === 0) {
          Text('该区域还没有房间：请先回区域页添加房间，再记录门。')
            .fontSize(Theme.F_META)
            .fontColor(Theme.DANGER)
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
          Text('备注里带「后」字就记成后门，否则记成前门。')
            .fontSize(Theme.F_META)
            .fontColor(Theme.INK3)
            .width('100%')
        }
      }

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
      }.width('100%')
    }
    .padding(18)
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
