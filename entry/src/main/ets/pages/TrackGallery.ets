import { promptAction } from '@kit.ArkUI';
import { PhotoKind, Track, TrackPhoto, TrackTag } from '../data/Entities';
import { Store } from '../data/Store';
import { photoUrl } from '../sensors/TrackMedia';
import { compassDir, coordText, fmtFullTime, fmtTime } from '../common/Utils';
import { Theme } from '../common/Theme';
import { Chip, PillButton } from '../common/Widgets';

/**
 * 单条轨迹的照片相册（独立全屏页）：
 *  - 按「节点照 / 风景照」分组：节点照属于某个节点（楼梯/门/电梯…），
 *    风景照只作宣传美化用、不参与节点体系；
 *  - 点任意一张进入全屏大图，可左右滑动切换，下方参数卡显示这张照片的全部参数：
 *    所属节点、时间、经纬度、海拔、朝向（度数 + 中文方位）、沙箱相对路径。
 *    相对路径与导出 zip 里的文件名一致，便于人工核对，也便于 AI 直接对照图片。
 */
/** 打开相册页的参数（NavDestination param，必须是显式声明的 interface） */
export interface GalleryParam {
  trackId: number;
  /** 直接定位到第几张（-1 = 只看网格） */
  startIndex: number;
}

@Component
export struct TrackGalleryPage {
  trackId: number = -1;
  /** 进入时想直接打开的照片下标（-1 = 只看网格） */
  startIndex: number = -1;
  onBack: () => void = () => {
  };
  @State track: Track | undefined = undefined;
  @State photos: TrackPhoto[] = [];
  @State tags: TrackTag[] = [];
  /** 大图浏览中的下标；-1 表示只看网格 */
  @State viewerIndex: number = -1;
  /** startIndex 只在首次加载后生效一次 */
  private startApplied: boolean = false;

  private reload = (): void => {
    Store.getTrack(this.trackId).then((t: Track | undefined) => {
      if (t) {
        this.track = t;
      }
    });
    Store.listTrackTags(this.trackId).then((ts: TrackTag[]) => {
      this.tags = ts;
    });
    Store.listTrackPhotos(this.trackId).then((ps: TrackPhoto[]) => {
      this.photos = ps;
      // 从详情页点缩略图进来时，直接展开那一张
      if (!this.startApplied && this.startIndex >= 0 && ps.length > 0) {
        this.startApplied = true;
        this.viewerIndex = Math.min(this.startIndex, ps.length - 1);
        return;
      }
      // 删除后下标越界时回退到最后一张，删空则关闭大图
      if (this.viewerIndex >= ps.length) {
        this.viewerIndex = ps.length - 1;
      }
    });
  };

  aboutToAppear(): void {
    this.reload();
    Store.subscribe(this.reload);
  }

  aboutToDisappear(): void {
    Store.unsubscribe(this.reload);
  }

  private current(): TrackPhoto | undefined {
    if (this.viewerIndex < 0 || this.viewerIndex >= this.photos.length) {
      return undefined;
    }
    return this.photos[this.viewerIndex];
  }

  private headingText(deg?: number): string {
    return deg === undefined ? '无朝向数据' : `${deg.toFixed(0)}° ${compassDir(deg)}`;
  }

  /** 照片所属的节点（风景照返回 undefined） */
  private nodeOfPhoto(ph: TrackPhoto): TrackTag | undefined {
    if (ph.kind !== PhotoKind.NODE || ph.tagId === undefined) {
      return undefined;
    }
    return this.tags.find((g: TrackTag) => g.id === ph.tagId);
  }

  private nodePhotos(): TrackPhoto[] {
    return this.photos.filter((ph: TrackPhoto) => ph.kind === PhotoKind.NODE);
  }

  private sceneryPhotos(): TrackPhoto[] {
    return this.photos.filter((ph: TrackPhoto) => ph.kind === PhotoKind.SCENERY);
  }

  /** 照片在整条轨迹照片序列里的下标（相册页按整序列滑动） */
  private photoIndex(ph: TrackPhoto): number {
    return this.photos.findIndex((x: TrackPhoto) => x.id === ph.id);
  }

  /** 缩略图左上角的节点类型角标 */
  private nodeTypeOf(ph: TrackPhoto): string {
    const g = this.nodeOfPhoto(ph);
    return g === undefined ? '节点' : g.tagType;
  }

  /** 大图里「楼层」那一行的文字（楼层来自所属节点，手填值；未填提示可补） */
  private curFloorText(): string {
    const c = this.current();
    if (c === undefined) {
      return '';
    }
    const g = this.nodeOfPhoto(c);
    if (g === undefined) {
      return c.kind === PhotoKind.NODE ? '所属节点已删除' : '风景照不记楼层';
    }
    return g.floor.length > 0 ? g.floor : '未填写（记录节点时可填）';
  }

  /** 大图里「所属节点」那一行的文字 */
  private curNodeText(): string {
    const c = this.current();
    if (c === undefined) {
      return '';
    }
    const g = this.nodeOfPhoto(c);
    if (g === undefined) {
      return c.kind === PhotoKind.NODE ? '节点已被删除' : '风景照（不参与节点）';
    }
    return g.note.length > 0 ? `${g.tagType} · ${g.note}` : g.tagType;
  }

  private curNote(): string {
    const c = this.current();
    if (c === undefined) {
      return '';
    }
    return c.note.length > 0 ? c.note : '（拍摄时未填写备注）';
  }

  private curTime(): string {
    const c = this.current();
    return c === undefined ? '' : fmtFullTime(c.timeMs);
  }

  private curCoord(): string {
    const c = this.current();
    return c === undefined ? '' : coordText(c.latitude, c.longitude);
  }

  private curHeading(): string {
    const c = this.current();
    return c === undefined ? '' : this.headingText(c.headingDeg);
  }

  private curAlt(): string {
    const c = this.current();
    if (c === undefined || c.altitude === undefined) {
      return '无海拔数据（室内 GPS 常缺失）';
    }
    return `${c.altitude.toFixed(1)} m`;
  }

  private curFile(): string {
    const c = this.current();
    return c === undefined ? '' : c.filePath;
  }

  /** 大图参数卡顶部的胶囊：节点类型 / 楼层（楼层没填就不显示） */
  private curChipText(): string {
    const c = this.current();
    if (c === undefined) {
      return '';
    }
    if (c.kind === PhotoKind.SCENERY) {
      return '风景照';
    }
    const g = this.nodeOfPhoto(c);
    return g === undefined ? '节点已删除' : g.tagType;
  }

  private curChipKind(): string {
    const c = this.current();
    if (c === undefined || c.kind === PhotoKind.SCENERY) {
      return 'scene';
    }
    return 'tag';
  }

  private curChipIconKey(): string {
    const c = this.current();
    if (c === undefined || c.kind === PhotoKind.SCENERY) {
      return 'scene';
    }
    const g = this.nodeOfPhoto(c);
    return g === undefined ? '' : g.tagType;
  }

  private curFloorChip(): string {
    const c = this.current();
    if (c === undefined) {
      return '';
    }
    const g = this.nodeOfPhoto(c);
    return g === undefined ? '' : g.floor.trim();
  }

  private askDelete(ph: TrackPhoto): void {
    promptAction.showDialog({
      title: '删除这张照片？',
      message: '照片文件与这条记录会一并删除，无法恢复。',
      buttons: [
        { text: '取消', color: Theme.INK2 },
        { text: '删除', color: Theme.DANGER }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        Store.deleteTrackPhoto(ph.id).then(() => {
          promptAction.showToast({ message: '照片已删除' });
        });
      }
    }).catch(() => {
    });
  }

  build() {
    Stack() {
      Column() {
        Row({ space: 10 }) {
          PillButton({
            label: '‹ 返回',
            onTap: (): void => {
              this.onBack();
            }
          })
          Column({ space: 2 }) {
            Text('相册').fontSize(Theme.F_TITLE).fontWeight(FontWeight.Bold).fontColor(Theme.INK)
            Text(this.track ? this.track.name : '轨迹照片')
              .fontSize(Theme.F_META)
              .fontColor(Theme.INK2)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').padding({ left: 14, right: 14, top: 12, bottom: 10 })
        Divider()

        if (this.photos.length === 0) {
          Column({ space: 6 }) {
            Blank()
            Text('这条轨迹还没有照片').fontWeight(FontWeight.Bold).fontColor(Theme.INK2)
            Text('录制时点横幅上的「记录节点」或「风景照」，就会出现在这里')
              .fontSize(Theme.F_META).fontColor(Theme.INK3)
            Blank()
          }.width('100%').layoutWeight(1)
        } else {
          Scroll() {
            Column({ space: 12 }) {
              Text('点任意一张看大图与完整参数（所属节点 / 楼层 / 位置 / 朝向）')
                .fontSize(Theme.F_META)
                .fontColor(Theme.INK2)
                .width('100%')

              // 节点照：属于某个节点，缩略图上标出节点类型
              if (this.nodePhotos().length > 0) {
                Column({ space: 8 }) {
                  Row({ space: 6 }) {
                    Chip({ text: '节点照', kind: 'tag' })
                    Text(`${this.nodePhotos().length} 张 · 属于节点`)
                      .fontSize(Theme.F_META).fontColor(Theme.INK2)
                    Blank()
                  }.width('100%')
                  Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
                    ForEach(this.nodePhotos(), (ph: TrackPhoto) => {
                      Column({ space: 4 }) {
                        Stack({ alignContent: Alignment.TopEnd }) {
                          Image(photoUrl(ph.filePath))
                            .width('100%')
                            .aspectRatio(1)
                            .objectFit(ImageFit.Cover)
                            .borderRadius(8)
                          Text(this.nodeTypeOf(ph))
                            .fontSize(9)
                            .fontColor(Theme.ON_RED)
                            .backgroundColor(Theme.RED)
                            .borderRadius(4)
                            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                            .margin(4)
                        }
                        .width('100%')
                        .onClick(() => {
                          this.viewerIndex = this.photoIndex(ph);
                        })

                        Text(ph.note.length > 0 ? ph.note : '（无备注）')
                          .fontSize(11)
                          .width('100%')
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(`${this.photoIndex(ph) + 1} · ${fmtTime(ph.timeMs)}`)
                          .fontSize(10)
                          .fontColor(Theme.INK2)
                          .width('100%')
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }.width('32%').margin({ bottom: 10 })
                    }, (ph: TrackPhoto) => ph.id + '')
                  }.width('100%')
                }.width('100%')
              }

              // 风景照：宣传美化用，不属于节点
              if (this.sceneryPhotos().length > 0) {
                Column({ space: 8 }) {
                  Row({ space: 6 }) {
                    Chip({ text: '风景照', kind: 'scene', iconKey: 'scene' })
                    Text(`${this.sceneryPhotos().length} 张 · 宣传美化用，不参与节点`)
                      .fontSize(Theme.F_META).fontColor(Theme.INK2)
                    Blank()
                  }.width('100%')
                  Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
                    ForEach(this.sceneryPhotos(), (ph: TrackPhoto) => {
                      Column({ space: 4 }) {
                        Stack({ alignContent: Alignment.TopEnd }) {
                          Image(photoUrl(ph.filePath))
                            .width('100%')
                            .aspectRatio(1)
                            .objectFit(ImageFit.Cover)
                            .borderRadius(8)
                          Text('风景')
                            .fontSize(9)
                            .fontColor(Theme.ON_RED)
                            .backgroundColor(Theme.YELLOW_INK)
                            .borderRadius(4)
                            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                            .margin(4)
                        }
                        .width('100%')
                        .onClick(() => {
                          this.viewerIndex = this.photoIndex(ph);
                        })

                        Text(ph.note.length > 0 ? ph.note : '（无备注）')
                          .fontSize(11)
                          .width('100%')
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(`${this.photoIndex(ph) + 1} · ${fmtTime(ph.timeMs)}`)
                          .fontSize(10)
                          .fontColor(Theme.INK2)
                          .width('100%')
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }.width('32%').margin({ bottom: 10 })
                    }, (ph: TrackPhoto) => ph.id + '')
                  }.width('100%')
                }.width('100%')
              }
            }.padding(16).width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
        }
      }.width('100%').height('100%')

      // 全屏大图浏览：顶部序号/删除/关闭 + 可左右滑动的图 + 参数卡
      // 配色全部走主题令牌（浅色卡片风），与其它页面统一；这里不再有硬编码色值
      if (this.viewerIndex >= 0 && this.photos.length > 0) {
        Column() {
          Row({ space: 8 }) {
            Text(`第 ${this.viewerIndex + 1} / ${this.photos.length} 张`)
              .fontSize(Theme.F_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.INK)
              .layoutWeight(1)
            PillButton({
              label: '删除',
              kind: 'danger',
              onTap: (): void => {
                const c = this.current();
                if (c !== undefined) {
                  this.askDelete(c);
                }
              }
            })
            PillButton({
              label: '关闭',
              onTap: (): void => {
                this.viewerIndex = -1;
              }
            })
          }.width('100%').padding({ left: 16, right: 14, top: 12, bottom: 10 })

          Swiper() {
            ForEach(this.photos, (ph: TrackPhoto) => {
              Image(photoUrl(ph.filePath))
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Contain)
            }, (ph: TrackPhoto) => ph.id + '')
          }
          .index(this.viewerIndex)
          .loop(false)
          .indicator(true)
          .onChange((i: number) => {
            this.viewerIndex = i;
          })
          .layoutWeight(1)
          .width('100%')

          Scroll() {
            // ⚠️ 参数逐行写出来，没有用「带参数的 @Builder」：@Builder 默认按值传参，
            // 按值传递时参数变化**不会**引起 Builder 内的 UI 刷新，滑到下一张照片时
            // 参数卡就会一直停在第一张的值上（轨迹详情页的统计卡片踩过同一个坑）。
            // 要让 @Builder 刷新得改成按引用传参（传对象），这里直接内联最稳妥。
            Column({ space: 9 }) {
              Row({ space: 6 }) {
                if (this.curChipText().length > 0) {
                  Chip({
                    text: this.curChipText(),
                    kind: this.curChipKind(),
                    iconKey: this.curChipIconKey()
                  })
                }
                if (this.curFloorChip().length > 0) {
                  Chip({ text: this.curFloorChip(), kind: 'floor', iconKey: 'floor' })
                }
                Blank()
              }.width('100%')
              Row({ space: 10 }) {
                Text('所属节点').fontSize(Theme.F_META).fontColor(Theme.INK2).width(52)
                Text(this.curNodeText()).fontSize(Theme.F_META).fontColor(Theme.INK).layoutWeight(1)
              }.width('100%').alignItems(VerticalAlign.Top)
              Row({ space: 10 }) {
                Text('楼层').fontSize(Theme.F_META).fontColor(Theme.INK2).width(52)
                Text(this.curFloorText()).fontSize(Theme.F_META).fontColor(Theme.INK).layoutWeight(1)
              }.width('100%').alignItems(VerticalAlign.Top)
              Row({ space: 10 }) {
                Text('备注').fontSize(Theme.F_META).fontColor(Theme.INK2).width(52)
                Text(this.curNote()).fontSize(Theme.F_META).fontColor(Theme.INK).layoutWeight(1)
              }.width('100%').alignItems(VerticalAlign.Top)
              Row({ space: 10 }) {
                Text('时间').fontSize(Theme.F_META).fontColor(Theme.INK2).width(52)
                Text(this.curTime()).fontSize(Theme.F_META).fontColor(Theme.INK).layoutWeight(1)
              }.width('100%').alignItems(VerticalAlign.Top)
              Row({ space: 10 }) {
                Text('经纬度').fontSize(Theme.F_META).fontColor(Theme.INK2).width(52)
                Text(this.curCoord()).fontSize(Theme.F_META).fontColor(Theme.INK).layoutWeight(1)
              }.width('100%').alignItems(VerticalAlign.Top)
              Row({ space: 10 }) {
                Text('海拔').fontSize(Theme.F_META).fontColor(Theme.INK2).width(52)
                Text(this.curAlt()).fontSize(Theme.F_META).fontColor(Theme.INK).layoutWeight(1)
              }.width('100%').alignItems(VerticalAlign.Top)
              Row({ space: 10 }) {
                Text('朝向').fontSize(Theme.F_META).fontColor(Theme.INK2).width(52)
                Text(this.curHeading()).fontSize(Theme.F_META).fontColor(Theme.INK).layoutWeight(1)
              }.width('100%').alignItems(VerticalAlign.Top)
              Row({ space: 10 }) {
                Text('文件').fontSize(Theme.F_META).fontColor(Theme.INK2).width(52)
                Text(this.curFile()).fontSize(Theme.F_META).fontColor(Theme.INK).layoutWeight(1)
              }.width('100%').alignItems(VerticalAlign.Top)
            }
            .padding(16)
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .backgroundColor(Theme.CARD)
            .borderRadius(Theme.R_CARD)
            .border({ width: 2, color: Theme.LINE })
          }
          .height(240)
          .width('100%')
          .padding({ left: Theme.PAD, right: Theme.PAD, top: 4 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.BG)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
