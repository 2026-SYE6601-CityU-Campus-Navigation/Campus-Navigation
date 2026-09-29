import { promptAction } from '@kit.ArkUI';
import { Marker, Room, markerTypeOptions } from '../data/Entities';
import { Store } from '../data/Store';
import { captureSnapshot } from '../sensors/SensorSnapshotter';
import { coordText } from '../common/Utils';
import { Theme } from '../common/Theme';
import { PillButton } from '../common/Widgets';

@CustomDialog
struct AddMarkerDialog {
  controller?: CustomDialogController;
  onSave?: (name: string, typeLabel: string) => void;
  @State name: string = '';
  @State typeLabel: string = '前门';

  build() {
    Column({ space: 12 }) {
      Text('添加标记').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
      TextInput({ placeholder: '名称（如：前门）' })
        .onChange((v: string) => {
          this.name = v;
        })
      Select(markerTypeOptions())
        .selected(0)
        .onSelect((index: number, value: string) => {
          this.typeLabel = value;
        })
        .width('100%')
      Text('保存时将自动采集：定位 + 气压 + 地磁快照')
        .fontSize(12)
        .fontColor(Theme.INK2)
        .width('100%')
      Row({ space: 12 }) {
        Button('取消').onClick(() => {
          this.controller?.close();
        })
        Button('采集并保存')
          .enabled(this.name.trim().length > 0)
          .onClick(() => {
            this.controller?.close();
            if (this.onSave) {
              this.onSave(this.name, this.typeLabel);
            }
          })
      }.width('100%').justifyContent(FlexAlign.End)
    }.padding(16).width('100%')
  }
}

@Component
export struct RoomDetailPage {
  roomId: number = -1;
  onBack: () => void = () => {
  };
  @State room: Room | undefined = undefined;
  @State markers: Marker[] = [];

  private reload = (): void => {
    Store.getRoom(this.roomId).then((r: Room | undefined) => {
      if (r) {
        this.room = r;
      }
    });
    Store.listMarkers(this.roomId).then((ms: Marker[]) => {
      this.markers = ms;
    });
  };

  aboutToAppear(): void {
    this.reload();
    Store.subscribe(this.reload);
  }

  aboutToDisappear(): void {
    Store.unsubscribe(this.reload);
  }

  private addDialog: CustomDialogController = new CustomDialogController({
    builder: AddMarkerDialog({
      onSave: (name: string, typeLabel: string): void => {
        this.addMarker(name, typeLabel);
      }
    }),
    customStyle: false
  });

  private addMarker(name: string, typeLabel: string): void {
    captureSnapshot().then((s) => {
      Store.insertMarker(this.roomId, name.trim(), typeLabel,
        s.latitude, s.longitude, s.altitude, s.accuracy,
        s.pressureHpa, s.magneticX, s.magneticY, s.magneticZ)
        .then(() => {
          promptAction.showToast({ message: `已采集并保存「${name}」的传感器快照` });
        });
    });
  }

  private setBasePoint(): void {
    captureSnapshot().then((s) => {
      Store.updateRoomBase(this.roomId, s.latitude, s.longitude, s.altitude, s.pressureHpa)
        .then(() => {
          promptAction.showToast({ message: '已记录房间基准点' });
        });
    });
  }

  private confirmDeleteRoom(): void {
    promptAction.showDialog({
      title: '删除房间',
      message: '将同时删除该房间的所有标记，确定删除？',
      buttons: [
        { text: '取消', color: Theme.RED },
        { text: '删除', color: Theme.DANGER }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        Store.deleteRoom(this.roomId).then(() => {
          this.onBack();
        });
      }
    }).catch(() => {
    });
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Row({ space: 8 }) {
          PillButton({
            label: '‹ 返回',
            onTap: (): void => {
              this.onBack();
            }
          })
          Text(this.room
            ? (this.room.code.length > 0 ? `${this.room.code} · ${this.room.name}` : this.room.name)
            : '房间')
            .fontSize(Theme.F_TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.INK)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          PillButton({
            label: '记基准点',
            onTap: (): void => {
              this.setBasePoint();
            }
          })
          PillButton({
            label: '删除',
            kind: 'danger',
            onTap: (): void => {
              this.confirmDeleteRoom();
            }
          })
        }.width('100%').padding({ left: 14, right: 14, top: 12, bottom: 10 })

        List() {
          ListItem() {
            this.BasePointCard()
          }
          ForEach(this.markers, (m: Marker) => {
            ListItem() {
              this.MarkerRow(m)
            }
          }, (m: Marker) => m.id + '')
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: Theme.LINE })
      }.width('100%').height('100%')
      Button('＋ 添加标记')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.ON_RED)
        .backgroundColor(Theme.RED)
        .borderRadius(20)
        .height(54)
        .margin(Theme.PAD)
        .onClick(() => {
          this.addDialog.open();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }

  @Builder
  BasePointCard() {
    Column({ space: 4 }) {
      Text('房间基准点').fontSize(14).fontWeight(FontWeight.Medium).width('100%')
      Text(this.room ? coordText(this.room.latitude, this.room.longitude) : '-')
        .fontSize(14)
        .width('100%')
      Text(this.room && this.room.pressureHpa !== undefined
        ? `气压 ${this.room.pressureHpa.toFixed(1)} hPa` : '气压：未采集')
        .fontSize(12)
        .fontColor(Theme.INK2)
        .width('100%')
    }.width('100%').padding(16)
  }

  @Builder
  MarkerRow(m: Marker) {
    Column({ space: 4 }) {
      Row() {
        Text(m.name).fontSize(16)
        Blank()
        Text(m.pressureHpa !== undefined ? `${m.pressureHpa.toFixed(1)} hPa` : '')
          .fontSize(12)
          .fontColor(Theme.INK2)
      }.width('100%')
      Text(`${m.markerType} · ${coordText(m.latitude, m.longitude)}`)
        .fontSize(13)
        .fontColor(Theme.INK2)
        .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .gesture(LongPressGesture().onAction(() => {
      Store.deleteMarker(m.id).then(() => {
        promptAction.showToast({ message: `已删除「${m.name}」` });
      });
    }))
  }
}
