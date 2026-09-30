// NavPathStack 在新版 SDK（API 21+）中为 ArkUI 全局类型，无需也不能从 @kit.ArkUI 导入
import { promptAction } from '@kit.ArkUI';
import { Area, AREA_CATEGORY_CITYU, AREA_CATEGORY_TEST, Room, Track, areaCategoryOptions } from '../data/Entities';
import { Store, UNASSIGNED_AREA_ID } from '../data/Store';
import { AreaDetailPage } from './AreaDetail';
import { GalleryParam, TrackGalleryPage } from './TrackGallery';
import { TrackListPage } from './TrackList';
import { TrackDetailPage } from './TrackDetail';
import { LiveSensorsPage } from './LiveSensors';
import { RoomDetailPage } from './RoomDetail';
import { CampusBuilding, cityuBuildings, planBuildingAreas } from '../common/Campus';
import { ClassroomParseResult, ClassroomPlan, ClassroomRow, buildingNoteOf, mergeRows, parseClassroomLines, planClassrooms, roomKeysOf, seedClassrooms } from '../common/Classrooms';
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
  onSave?: (name: string, note: string, category: string) => void;
  /** 预选分类：从哪个分区的「＋」进来，就默认建到哪一类（用户 2026-09-29：区域固定分两大类） */
  defaultCategory: string = AREA_CATEGORY_CITYU;
  @State name: string = '';
  @State note: string = '';
  @State category: string = AREA_CATEGORY_CITYU;

  aboutToAppear(): void {
    this.category = this.defaultCategory;
  }

  build() {
    Column({ space: 14 }) {
      Text('新建区域').fontSize(19).fontWeight(FontWeight.Bold).width('100%').fontColor(Theme.INK)
      Text('按楼栋 / 楼层划分区域，房间与轨迹都归属某个区域')
        .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')

      // 分类：固定「城市大学 / 测试集」两类，点一下切换
      Text('分类').fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
      Row({ space: 10 }) {
        ForEach(areaCategoryOptions(), (c: string) => {
          Text(c)
            .fontSize(13.5)
            .fontWeight(FontWeight.Bold)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 10, bottom: 10 })
            .fontColor(this.category === c ? Theme.ON_RED : Theme.INK)
            .backgroundColor(this.category === c ? Theme.RED : Theme.CARD_SOFT)
            .borderRadius(14)
            .border({ width: 2, color: this.category === c ? Theme.RED_DEEP : Theme.LINE })
            .onClick(() => {
              this.category = c;
            })
        }, (c: string) => c)
      }.width('100%')

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
                this.onSave(this.name.trim(), this.note.trim(), this.category);
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

@CustomDialog
struct ClassroomImportDialog {
  controller?: CustomDialogController;
  onSave?: (pasted: string) => void;
  @State text: string = '';

  build() {
    Column({ space: 12 }) {
      Text('导入教室名单').fontSize(19).fontWeight(FontWeight.Bold).width('100%').fontColor(Theme.INK)
      Text('在每栋楼的区域里批量建房间（教室代码 + 教室名称）。'
        + '内置清单只有 AC1 的 18 间讲堂（LT-1…LT-18，都在 4 樓）和 BOC LT401 —— '
        + '这是公开资料里能逐条查证的部分：城大官网与 AIMS 的教室总表要登录、又对程序访问有反爬，抓不到全量清单。'
        + '所以编号是照「共 18 间、不分颜色不标楼层」推出来的连号，导入后请按现场核对。')
        .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
      Text('想补更多，就从 AIMS 课表 / 考试时间表复制过来粘在下面，每行：建筑, 教室代码, 教室名称, 备注(选填)。'
        + '建筑写简称即可（AC1 / AC2 / AC3 / BOC / MMW / FYW / CMC…）。')
        .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
      TextArea({ placeholder: '例：\nAC2, 1503, 讲堂 1503, 1/F\nLAU, 6-213, 实验室 213, 6/F' })
        .fontSize(13.5)
        .height(110)
        .backgroundColor(Theme.CARD_SOFT)
        .borderRadius(14)
        .border({ width: 2, color: Theme.LINE })
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onChange((v: string) => {
          this.text = v;
        })
      Text('区域不存在会自动新建；同一个区域里代码或名称已存在就跳过，所以反复导入是安全的。')
        .fontSize(Theme.F_META).fontColor(Theme.INK3).width('100%')
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
            label: '导入',
            kind: 'primary',
            compact: true,
            onTap: (): void => {
              this.controller?.close();
              if (this.onSave) {
                this.onSave(this.text);
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

  /**
   * 新建区域对话框：**按点击时的分区动态构造**。
   * 不放在成员初始化器里 —— 那样只能有一个固定的默认分类，两个分区各自的「＋」就没法各自预选了
   * （而且成员初始化阶段 this 上的属性还可能尚未赋值，这是本工程踩过的坑）。
   */
  private addDialog: CustomDialogController | null = null;

  private openAddArea(category: string): void {
    this.addDialog = new CustomDialogController({
      builder: AddAreaDialog({
        defaultCategory: category,
        onSave: (name: string, note: string, cat: string): void => {
          const n = name.trim();
          if (n.length === 0) {
            return;
          }
          Store.insertArea(n, note.trim(), cat).then((id: number) => {
            this.onOpenArea(id);
          });
        }
      }),
      customStyle: false
    });
    this.addDialog.open();
  }

  /** 教室名单导入对话框（按楼批量建房间） */
  private classroomDialog: CustomDialogController = new CustomDialogController({
    builder: ClassroomImportDialog({
      onSave: (pasted: string): void => {
        this.runClassroomImport(pasted);
      }
    }),
    customStyle: false
  });

  private isEmpty(): boolean {
    return this.areas.length === 0 && this.unassignedRoomCount === 0 && this.unassignedTrackCount === 0;
  }

  /**
   * 某个分类下的区域（首页分区显示用）。
   * 分类为空的区域（理论上老库归类跑完后不该出现）一律当「城市大学」，保证不会有区域从列表里漏掉。
   */
  private areasOf(category: string): Area[] {
    const out: Area[] = [];
    for (const a of this.areas) {
      const cat: string = a.category.length > 0 ? a.category : AREA_CATEGORY_CITYU;
      if (cat === category) {
        out.push(a);
      }
    }
    return out;
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
        return Store.insertArea(b.name, b.note, AREA_CATEGORY_CITYU).then(() => {
        });
      });
    }
    pending.then(() => {
      promptAction.showToast({ message: `已导入 ${drafts.length} 个建筑区域` });
    }).catch((e: Error) => {
      promptAction.showToast({ message: `导入失败：${e.message}` });
    });
  }

  // ---------- 导入教室名单（按楼批量建房间） ----------

  /** 区域 id → 区域名（房间的去重键要用「区域名 + 代码/名称」） */
  private areaNameOfId(areas: Area[], id?: number): string {
    if (id === undefined) {
      return '';
    }
    for (const a of areas) {
      if (a.id === id) {
        return a.name;
      }
    }
    return '';
  }

  private runClassroomImport(pasted: string): void {
    const parsed: ClassroomParseResult = parseClassroomLines(pasted);
    // 粘贴的排前面（用户自己写的优先），内置种子跟在后面
    const rows: ClassroomRow[] = mergeRows(parsed.rows, seedClassrooms());
    Store.listAreas().then((areas: Area[]) => {
      const areaNames: string[] = [];
      for (const a of areas) {
        areaNames.push(a.name);
      }
      return Store.listRooms().then((rooms: Room[]) => {
        // 库里已有房间 → 去重键（同区域同代码、或同名，都算重复）
        const keys: string[] = [];
        for (const r of rooms) {
          const ks: string[] = roomKeysOf(this.areaNameOfId(areas, r.areaId), r.code, r.name);
          for (const k of ks) {
            keys.push(k);
          }
        }
        const plan: ClassroomPlan = planClassrooms(rows, areaNames, keys);
        if (plan.rooms.length === 0) {
          promptAction.showToast({ message: '没有要新建的教室：名单里的都已经在库里了' });
          return;
        }
        this.confirmClassrooms(plan, parsed.badLines.length);
      });
    }).catch((e: Error) => {
      promptAction.showToast({ message: `读取房间失败：${e.message}` });
    });
  }

  /** 导入前确认：列出要新建的区域与教室（重复的已在上一步跳过） */
  private confirmClassrooms(plan: ClassroomPlan, badLines: number): void {
    const lines: string[] = [];
    if (plan.newAreas.length > 0) {
      lines.push(`新建区域 ${plan.newAreas.length} 个：${plan.newAreas.join('、')}`);
    }
    const seenAreas: string[] = [];
    let shown = 0;
    for (const d of plan.rooms) {
      if (seenAreas.indexOf(d.areaName) < 0) {
        seenAreas.push(d.areaName);
        lines.push(`【${d.areaName}】`);
      }
      if (shown < 12) {
        lines.push(`  · ${d.code.length > 0 ? `${d.code} ${d.name}` : d.name}`);
        shown++;
      }
    }
    if (plan.rooms.length > shown) {
      lines.push(`  … 还有 ${plan.rooms.length - shown} 间`);
    }
    const badNote: string = badLines > 0 ? `\n（有 ${badLines} 行没认出格式，已跳过）` : '';
    promptAction.showDialog({
      title: `新建 ${plan.rooms.length} 个教室房间`,
      message: `${lines.join('\n')}\n\n同区域同代码或同名会自动跳过，反复导入是安全的。${badNote}`,
      buttons: [
        { text: '取消', color: Theme.INK2 },
        { text: `创建 ${plan.rooms.length} 个`, color: Theme.RED }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        this.createClassrooms(plan);
      }
    }).catch(() => {
    });
  }

  private createClassrooms(plan: ClassroomPlan): void {
    let pending: Promise<void> = Promise.resolve();
    for (const name of plan.newAreas) {
      pending = pending.then((): Promise<void> => {
        // 教室名单来源是城大的课表，所以按楼建出来的区域一律归「城市大学」
        return Store.insertArea(name, buildingNoteOf(name), AREA_CATEGORY_CITYU).then(() => {
        });
      });
    }
    // 区域建完再查一次 id，然后逐个建房间（串行，避免并发写库）
    pending.then((): Promise<void> => {
      return Store.listAreas().then((areas: Area[]) => {
        const ids: number[] = [];
        const names: string[] = [];
        for (const a of areas) {
          ids.push(a.id);
          names.push(a.name);
        }
        let inner: Promise<void> = Promise.resolve();
        for (const room of plan.rooms) {
          inner = inner.then((): Promise<void> => {
            const idx: number = names.indexOf(room.areaName);
            if (idx < 0) {
              return Promise.resolve();
            }
            return Store.insertRoom(room.name, room.note, ids[idx], room.code).then(() => {
            });
          });
        }
        return inner;
      });
    }).then(() => {
      const areaPart: string = plan.newAreas.length > 0 ? `、新建 ${plan.newAreas.length} 个区域` : '';
      promptAction.showToast({ message: `已建 ${plan.rooms.length} 个教室房间${areaPart}` });
    }).catch((e: Error) => {
      promptAction.showToast({ message: `教室导入失败：${e.message}` });
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

              // 区域列表：固定两大类（城市大学 / 测试集），各一段；每段带自己的「＋ 添加」，
              // 点哪个分区的加号，新建出来的区域就落在哪一类。
              //
              // ⚠️ 行样式在下面**刻意重复写了两遍**，没有抽成带参 @Builder、也没有嵌两层 ForEach：
              // 本工程踩过「ForEach 复用同一节点时 @Builder 按值传参不刷新」的坑，两段各用一个
              // 普通 ForEach（数据直接来自 @State this.areas）是行为最好预测的写法。以后加第三类，
              // 照着再复制一段即可 —— 别急着"优化"成循环，那会把这个坑重新引回来。
              Row({ space: 8 }) {
                Text(`城市大学（${this.areasOf(AREA_CATEGORY_CITYU).length}）`)
                  .fontSize(Theme.F_SECTION).fontWeight(FontWeight.Bold).fontColor(Theme.INK)
                  .layoutWeight(1)
                PillButton({
                  label: '＋ 添加',
                  onTap: (): void => {
                    this.openAddArea(AREA_CATEGORY_CITYU);
                  }
                })
              }.width('100%')

              if (this.areasOf(AREA_CATEGORY_CITYU).length === 0) {
                Text('还没有校园区域：可从下面「从城大建筑清单导入区域」一键建好')
                  .fontSize(Theme.F_META).fontColor(Theme.INK3).width('100%')
              }
              ForEach(this.areasOf(AREA_CATEGORY_CITYU), (a: Area) => {
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

              Row({ space: 8 }) {
                Text(`测试集（${this.areasOf(AREA_CATEGORY_TEST).length}）`)
                  .fontSize(Theme.F_SECTION).fontWeight(FontWeight.Bold).fontColor(Theme.INK)
                  .layoutWeight(1)
                PillButton({
                  label: '＋ 添加',
                  onTap: (): void => {
                    this.openAddArea(AREA_CATEGORY_TEST);
                  }
                })
              }.width('100%')

              if (this.areasOf(AREA_CATEGORY_TEST).length === 0) {
                Text('还没有测试区域：试采集、试标签、试拍照放这里，和正式校园数据分开')
                  .fontSize(Theme.F_META).fontColor(Theme.INK3).width('100%')
              }
              ForEach(this.areasOf(AREA_CATEGORY_TEST), (a: Area) => {
                Row({ space: 12 }) {
                  Column() {
                    Image($r('app.media.ic_layers')).width(22).height(22).objectFit(ImageFit.Contain)
                  }
                  .width(44).height(44)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor(Theme.PLACEHOLDER)
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

              // 教室名单：按楼批量建房间（教室代码 + 教室名称），也可粘贴 AIMS 课表里的清单
              Row({ space: 12 }) {
                Column() {
                  Text('课')
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Theme.RED)
                }
                .width(44).height(44)
                .justifyContent(FlexAlign.Center)
                .backgroundColor(Theme.RED_SOFT)
                .borderRadius(Theme.R_THUMB)

                Column({ space: 3 }) {
                  Text('导入教室名单')
                    .fontSize(15).fontWeight(FontWeight.Bold).fontColor(Theme.INK)
                    .width('100%')
                  Text('按楼批量建房间（教室代码 + 名称）；也可以粘贴 AIMS 课表里的清单')
                    .fontSize(Theme.F_META).fontColor(Theme.INK2).width('100%')
                    .maxLines(2)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text('›').fontSize(18).fontColor(Theme.INK3)
              }
              .width('100%')
              .padding(14)
              .backgroundColor(Theme.CARD)
              .borderRadius(18)
              .border({ width: 2, color: Theme.LINE, style: BorderStyle.Dashed })
              .onClick(() => {
                this.classroomDialog.open();
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
          // 底部 FAB 没有分区上下文，默认建到「城市大学」；想建到测试集用那个分区标题旁的「＋」
          this.openAddArea(AREA_CATEGORY_CITYU);
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
