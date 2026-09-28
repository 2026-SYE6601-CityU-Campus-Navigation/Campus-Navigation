// NavPathStack 在新版 SDK（API 21+）中为 ArkUI 全局类型，无需也不能从 @kit.ArkUI 导入
import { Area } from '../data/Entities';
import { Store, UNASSIGNED_AREA_ID } from '../data/Store';
import { AreaDetailPage } from './AreaDetail';
import { TrackListPage } from './TrackList';
import { TrackDetailPage } from './TrackDetail';
import { LiveSensorsPage } from './LiveSensors';
import { RoomDetailPage } from './RoomDetail';

@Entry
@Component
struct Index {
  @Provide('navStack') navStack: NavPathStack = new NavPathStack();

  build() {
    Navigation(this.navStack) {
      AreaListPage({
        onOpenArea: (id: number) => {
          this.navStack.pushPath({ name: 'area', param: id });
        },
        onTracks: () => {
          this.navStack.pushPath({ name: 'tracks' });
        },
        onLive: () => {
          this.navStack.pushPath({ name: 'live' });
        }
      })
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMapBuilder)
  }

  @Builder
  pageMapBuilder(name: string, param?: Object) {
    if (name === 'tracks') {
      NavDestination() {
        TrackListPage({
          onBack: () => {
            this.navStack.pop();
          },
          onOpenTrack: (id: number) => {
            this.navStack.pushPath({ name: 'track', param: id });
          }
        })
      }
      .hideTitleBar(true)
    } else if (name === 'live') {
      NavDestination() {
        LiveSensorsPage({
          onBack: () => {
            this.navStack.pop();
          }
        })
      }
      .hideTitleBar(true)
    } else if (name === 'room') {
      NavDestination() {
        RoomDetailPage({
          roomId: param as number,
          onBack: () => {
            this.navStack.pop();
          }
        })
      }
      .hideTitleBar(true)
    } else if (name === 'track') {
      NavDestination() {
        TrackDetailPage({
          trackId: param as number,
          onBack: () => {
            this.navStack.pop();
          }
        })
      }
      .hideTitleBar(true)
    } else if (name === 'area') {
      NavDestination() {
        AreaDetailPage({
          areaId: param as number,
          onBack: () => {
            this.navStack.pop();
          },
          onOpenRoom: (id: number) => {
            this.navStack.pushPath({ name: 'room', param: id });
          },
          onOpenTrack: (id: number) => {
            this.navStack.pushPath({ name: 'track', param: id });
          }
        })
      }
      .hideTitleBar(true)
    }
  }
}

@CustomDialog
struct AddAreaDialog {
  controller?: CustomDialogController;
  onSave?: (name: string, note: string) => void;
  @State name: string = '';
  @State note: string = '';

  build() {
    Column({ space: 12 }) {
      Text('新建区域').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
      TextInput({ placeholder: '区域名称（如：AC1 三楼 / 图书馆二层）' })
        .onChange((v: string) => {
          this.name = v;
        })
      TextInput({ placeholder: '备注（可选，如：含 301-320 教室）' })
        .onChange((v: string) => {
          this.note = v;
        })
      Row({ space: 12 }) {
        Button('取消').onClick(() => {
          this.controller?.close();
        })
        Button('创建')
          .enabled(this.name.trim().length > 0)
          .onClick(() => {
            this.controller?.close();
            if (this.onSave) {
              this.onSave(this.name.trim(), this.note.trim());
            }
          })
      }.width('100%').justifyContent(FlexAlign.End)
    }.padding(16).width('100%')
  }
}

@Component
struct AreaListPage {
  @State areas: Area[] = [];
  @State unassignedRoomCount: number = 0;
  @State unassignedTrackCount: number = 0;
  onOpenArea: (id: number) => void = (id: number) => {
  };
  onTracks: () => void = () => {
  };
  onLive: () => void = () => {
  };

  private reload = (): void => {
    Store.listAreas().then((list: Area[]) => {
      this.areas = list;
    });
    Store.listRooms(UNASSIGNED_AREA_ID).then((r) => {
      this.unassignedRoomCount = r.length;
    });
    Store.listTracksInArea(UNASSIGNED_AREA_ID).then((t) => {
      this.unassignedTrackCount = t.length;
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
    builder: AddAreaDialog({
      onSave: (name: string, note: string): void => {
        const n = name.trim();
        if (n.length === 0) {
          return;
        }
        Store.insertArea(n, note.trim()).then((id: number) => {
          this.onOpenArea(id);
        });
      }
    }),
    customStyle: false
  });

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Row() {
          Text('RoomMarker 数据采集').fontSize(20).fontWeight(FontWeight.Bold)
          Blank()
          Button('全部轨迹').fontSize(13).onClick(() => {
            this.onTracks();
          })
          Button('实时').fontSize(13).margin({ left: 8 }).onClick(() => {
            this.onLive();
          })
        }.width('100%').padding({ left: 16, right: 12, top: 14, bottom: 12 })
        Divider()

        if (this.areas.length === 0 && this.unassignedRoomCount === 0 && this.unassignedTrackCount === 0) {
          Column() {
            Blank()
            Text('还没有区域，点击右下角新建').fontColor('#99000000')
            Text('按楼栋/楼层划区域后开始收集数据').fontSize(12).fontColor('#66000000')
            Blank()
          }.width('100%').layoutWeight(1)
        } else {
          List() {
            if (this.unassignedRoomCount + this.unassignedTrackCount > 0) {
              ListItem() {
                Column({ space: 4 }) {
                  Text('未分区数据').fontSize(16).width('100%')
                  Text(`旧数据 · 房间 ${this.unassignedRoomCount} · 轨迹 ${this.unassignedTrackCount}`)
                    .fontSize(13)
                    .fontColor('#99000000')
                    .width('100%')
                }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
              }.onClick(() => {
                this.onOpenArea(UNASSIGNED_AREA_ID);
              })
            }
            ForEach(this.areas, (a: Area) => {
              ListItem() {
                Column({ space: 4 }) {
                  Text(a.name).fontSize(16).width('100%')
                  Text(a.note.length > 0
                    ? `${a.note} · 房间 ${a.roomCount} · 轨迹 ${a.trackCount}`
                    : `房间 ${a.roomCount} · 轨迹 ${a.trackCount}`)
                    .fontSize(13)
                    .fontColor('#99000000')
                    .width('100%')
                }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
              }.onClick(() => {
                this.onOpenArea(a.id);
              })
            }, (a: Area) => a.id + '')
          }
          .width('100%')
          .layoutWeight(1)
          .divider({ strokeWidth: 0.5, color: '#1A000000' })
        }
      }.width('100%').height('100%')

      Button('新建区域').margin(16).onClick(() => {
        this.addDialog.open();
      })
    }.width('100%').height('100%')
  }
}
