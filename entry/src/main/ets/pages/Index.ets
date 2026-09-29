// NavPathStack 在新版 SDK（API 21+）中为 ArkUI 全局类型，无需也不能从 @kit.ArkUI 导入
import { promptAction } from '@kit.ArkUI';
import { Area, Track } from '../data/Entities';
import { Store, UNASSIGNED_AREA_ID } from '../data/Store';
import { AreaDetailPage } from './AreaDetail';
import { GalleryParam, TrackGalleryPage } from './TrackGallery';
import { TrackListPage } from './TrackList';
import { TrackDetailPage } from './TrackDetail';
import { LiveSensorsPage } from './LiveSensors';
import { RoomDetailPage } from './RoomDetail';
import { CampusBuilding, cityuBuildings, planBuildingAreas } from '../common/Campus';
import { fmtDateTime } from '../common/Utils';
import { Theme } from '../common/Theme';
import { PillButton, ThickButton } from '../common/Widgets';

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
          },
          onOpenGallery: (id: number, startIndex: number) => {
            const gp: GalleryParam = { trackId: id, startIndex: startIndex };
            this.navStack.pushPath({ name: 'gallery', param: gp });
          }
        })
      }
      .hideTitleBar(true)
    } else if (name === 'gallery') {
      NavDestination() {
        TrackGalleryPage({
          trackId: (param as GalleryParam).trackId,
          startIndex: (param as GalleryParam).startIndex,
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
    Column({ space: 14 }) {
      Text('新建区域').fontSize(19).fontWeight(FontWeight.Bold).width('100%').fontColor(Theme.INK)
      Text('按楼栋 / 楼层划分区域，房间与轨迹都归属某个区域')
        .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
      TextInput({ placeholder: '区域名称（如：AC1 三楼 / 图书馆二层）' })
        .fontSize(13.5)
        .backgroundColor(Theme.CARD_SOFT)
        .borderRadius(14)
        .border({ width: 2, color: Theme.LINE })
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onChange((v: string) => {
          this.name = v;
        })
      TextInput({ placeholder: '备注（选填，如：含 301-320 教室）' })
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
            label: '创建',
            kind: 'primary',
            compact: true,
            disabled: this.name.trim().length === 0,
            onTap: (): void => {
              this.controller?.close();
              if (this.onSave) {
                this.onSave(this.name.trim(), this.note.trim());
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

@Component
struct AreaListPage {
  @State areas: Area[] = [];
  @State unassignedRoomCount: number = 0;
  @State unassignedTrackCount: number = 0;
  /** 最近一次采集（用于首页「接着干」的入口），来自最近一条轨迹 */
  @State lastAreaId: number = -2;
  @State lastAreaName: string = '';
  @State lastTrackName: string = '';
  @State lastAt: number = 0;
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
    // 最近一条轨迹所在区域 = 上次采到哪
    Store.listTracks().then((ts: Track[]) => {
      if (ts.length === 0) {
        this.lastAreaId = -2;
        return;
      }
      const t = ts[0];
      this.lastAreaName = t.areaName !== undefined ? t.areaName : '未分区';
      this.lastTrackName = t.name;
      this.lastAt = t.startedAt;
      this.lastAreaId = t.areaId !== undefined ? t.areaId : UNASSIGNED_AREA_ID;
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

  private isEmpty(): boolean {
    return this.areas.length === 0 && this.unassignedRoomCount === 0 && this.unassignedTrackCount === 0;
  }

  /** 一键导入城大建筑区域：每栋楼一个区域，已存在的同名区域自动跳过 */
  private importBuildings(): void {
    Store.listAreas().then((list: Area[]) => {
      const names: string[] = [];
      for (const a of list) {
        names.push(a.name);
      }
      const drafts: CampusBuilding[] = planBuildingAreas(names);
      if (drafts.length === 0) {
        promptAction.showToast({ message: '城大建筑区域都已经建好了' });
        return;
      }
      const preview: string[] = [];
      const shown: number = drafts.length > 8 ? 8 : drafts.length;
      for (let i = 0; i < shown; i++) {
        preview.push(`· ${drafts[i].name}`);
      }
      if (drafts.length > shown) {
        preview.push(`… 还有 ${drafts.length - shown} 栋`);
      }
      promptAction.showDialog({
        title: `导入 ${drafts.length} 个建筑区域`,
        message: `${preview.join('\n')}\n\n每栋楼建一个区域（同名自动跳过）；`
          + `楼层在记录节点时点选（LG/F、G/F、1/F…）。`,
        buttons: [
          { text: '取消', color: Theme.INK2 },
          { text: `导入 ${drafts.length} 个`, color: Theme.RED }
        ]
      }).then((res: promptAction.ShowDialogSuccessResponse) => {
        if (res.index === 1) {
          this.createAreas(drafts);
        }
      }).catch(() => {
      });
    });
  }

  private createAreas(drafts: CampusBuilding[]): void {
    let pending: Promise<void> = Promise.resolve();
    for (const b of drafts) {
      pending = pending.then((): Promise<void> => {
        return Store.insertArea(b.name, b.note).then(() => {
        });
      });
    }
    pending.then(() => {
      promptAction.showToast({ message: `已导入 ${drafts.length} 个建筑区域` });
    }).catch((e: Error) => {
      promptAction.showToast({ message: `导入失败：${e.message}` });
    });
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        // 顶栏
        Row({ space: 8 }) {
          Column({ space: 1 }) {
            Text('校园采集').fontSize(Theme.F_TITLE).fontWeight(FontWeight.Bold).fontColor(Theme.INK)
            Text(`香港城市大学 · 已建 ${this.areas.length} 个区域`)
              .fontSize(Theme.F_META).fontColor(Theme.INK2)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          PillButton({
            label: '全部轨迹',
            onTap: (): void => {
              this.onTracks();
            }
          })
          PillButton({
            label: '实时',
            onTap: (): void => {
              this.onLive();
            }
          })
        }.width('100%').padding({ left: Theme.PAD, right: 14, top: 14, bottom: 12 })

        if (this.isEmpty()) {
          Column({ space: 8 }) {
            Blank()
            Text('还没有区域').fontSize(16).fontWeight(FontWeight.Bold).fontColor(Theme.INK2)
            Text('可以先一键导入城大的建筑区域，也可以点右下角自己新建').fontSize(12).fontColor(Theme.INK3)
            Column() {
              ThickButton({
                label: '一键导入城大建筑区域',
                kind: 'primary',
                compact: true,
                onTap: (): void => {
                  this.importBuildings();
                }
              })
            }.width('72%').margin({ top: 8 })
            Blank()
          }.width('100%').layoutWeight(1)
        } else {
          Scroll() {
            Column({ space: Theme.GAP }) {
              // 英雄卡：接着上次的地方干
              if (this.lastAreaId !== -2) {
                Column({ space: 6 }) {
                  Text('上次采集到').fontSize(Theme.F_META).fontColor(Theme.ON_RED_SOFT)
                  Text(this.lastAreaName)
                    .fontSize(21).fontWeight(FontWeight.Bold).fontColor(Theme.ON_RED)
                    .width('100%')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${this.lastTrackName} · ${fmtDateTime(this.lastAt)}`)
                    .fontSize(Theme.F_META).fontColor(Theme.ON_RED_SOFT).width('100%')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row().height(6)
                  Column() {
                    ThickButton({
                      label: '继续记录',
                      kind: 'onred',
                      compact: true,
                      onTap: (): void => {
                        this.onOpenArea(this.lastAreaId);
                      }
                    })
                  }.width('100%')
                }
                .width('100%')
                .padding(18)
                .backgroundColor(Theme.RED)
                .borderRadius(Theme.R_HERO)
                .border({ width: { bottom: 5 }, color: { bottom: Theme.RED_DEEP } })
              }

              // 区域列表
              ForEach(this.areas, (a: Area) => {
                Row({ space: 12 }) {
                  Column() {
                    Image($r('app.media.ic_layers')).width(22).height(22).objectFit(ImageFit.Contain)
                  }
                  .width(44).height(44)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor(Theme.RED_SOFT)
                  .borderRadius(Theme.R_THUMB)

                  Column({ space: 3 }) {
                    Text(a.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Theme.INK)
                      .width('100%')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${a.note.length > 0 ? a.note + ' · ' : ''}房间 ${a.roomCount} · 轨迹 ${a.trackCount}`)
                      .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Text('›').fontSize(18).fontColor(Theme.INK3)
                }
                .width('100%')
                .padding(14)
                .backgroundColor(Theme.CARD)
                .borderRadius(18)
                .border({ width: 2, color: Theme.LINE })
                .onClick(() => {
                  this.onOpenArea(a.id);
                })
              }, (a: Area) => a.id + '')

              if (this.unassignedRoomCount + this.unassignedTrackCount > 0) {
                Row({ space: 12 }) {
                  Column() {
                    Text('旧')
                      .fontSize(13)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Theme.INK2)
                  }
                  .width(44).height(44)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor(Theme.PLACEHOLDER)
                  .borderRadius(Theme.R_THUMB)

                  Column({ space: 3 }) {
                    Text('未分区（旧数据）').fontSize(15).fontWeight(FontWeight.Bold)
                      .fontColor(Theme.INK2).width('100%')
                    Text(`房间 ${this.unassignedRoomCount} · 轨迹 ${this.unassignedTrackCount}`)
                      .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Text('›').fontSize(18).fontColor(Theme.INK3)
                }
                .width('100%')
                .padding(14)
                .backgroundColor(Theme.CARD)
                .borderRadius(18)
                .border({ width: 2, color: Theme.LINE, style: BorderStyle.Dashed })
                .onClick(() => {
                  this.onOpenArea(UNASSIGNED_AREA_ID);
                })
              }

              // 城大建筑区域：一键导入（已存在的同名区域跳过，所以点几次都不会重复）
              Row({ space: 12 }) {
                Column() {
                  Text('建')
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Theme.RED)
                }
                .width(44).height(44)
                .justifyContent(FlexAlign.Center)
                .backgroundColor(Theme.RED_SOFT)
                .borderRadius(Theme.R_THUMB)

                Column({ space: 3 }) {
                  Text('从城大建筑清单导入区域')
                    .fontSize(15).fontWeight(FontWeight.Bold).fontColor(Theme.INK)
                    .width('100%')
                  Text(`一键建好 ${cityuBuildings().length} 栋楼的区域；楼层在记录节点时点选`)
                    .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text('›').fontSize(18).fontColor(Theme.INK3)
              }
              .width('100%')
              .padding(14)
              .backgroundColor(Theme.CARD)
              .borderRadius(18)
              .border({ width: 2, color: Theme.LINE, style: BorderStyle.Dashed })
              .onClick(() => {
                this.importBuildings();
              })
            }.padding({ left: Theme.PAD, right: Theme.PAD, bottom: 90 }).width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
        }
      }.width('100%').height('100%')

      Button('＋ 新建区域')
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
}
