import { Track, TrackPhoto, TrackPoint, TrackTag } from '../data/Entities';
import { Store } from '../data/Store';
import { Ctx, compassDir, fmtDuration, fmtTime } from '../common/Utils';

@CustomDialog
struct PhotoViewDialog {
  controller?: CustomDialogController;
  absPath: string = '';

  build() {
    Column({ space: 12 }) {
      Image('file://' + this.absPath)
        .width('100%')
        .height(320)
        .objectFit(ImageFit.Contain)
        .borderRadius(8)
      Button('关闭').onClick(() => {
        this.controller?.close();
      })
    }.padding(16).width('100%')
  }
}

@Component
export struct TrackDetailPage {
  trackId: number = -1;
  onBack: () => void = () => {
  };
  @State track: Track | undefined = undefined;
  @State points: TrackPoint[] = [];
  @State tags: TrackTag[] = [];
  @State photos: TrackPhoto[] = [];
  private photoViewDialog: CustomDialogController | null = null;

  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private canvasW = 0;
  private canvasH = 0;

  private reload = (): void => {
    Store.getTrack(this.trackId).then((t: Track | undefined) => {
      if (t) {
        this.track = t;
      }
    });
    Store.listPoints(this.trackId).then((pts: TrackPoint[]) => {
      this.points = pts;
      this.drawPath();
    });
    Store.listTrackTags(this.trackId).then((ts: TrackTag[]) => {
      this.tags = ts;
    });
    Store.listTrackPhotos(this.trackId).then((ps: TrackPhoto[]) => {
      this.photos = ps;
    });
  };

  aboutToAppear(): void {
    this.reload();
    Store.subscribe(this.reload);
  }

  aboutToDisappear(): void {
    Store.unsubscribe(this.reload);
  }

  private geoCount(): number {
    let n = 0;
    this.points.forEach((p: TrackPoint) => {
      if (p.latitude !== undefined && p.longitude !== undefined) {
        n++;
      }
    });
    return n;
  }

  private photoAbs(ph: TrackPhoto): string {
    const dir = Ctx.ui ? Ctx.ui.filesDir : '';
    return `file://${dir}/${ph.filePath}`;
  }

  private openPhoto(ph: TrackPhoto): void {
    this.photoViewDialog = new CustomDialogController({
      builder: PhotoViewDialog({ absPath: this.photoAbs(ph) }),
      customStyle: false
    });
    this.photoViewDialog.open();
  }

  private drawPath(): void {
    if (this.canvasW <= 0 || this.canvasH <= 0) {
      return;
    }
    const geo: TrackPoint[] = this.points.filter((p: TrackPoint) => {
      return p.latitude !== undefined && p.longitude !== undefined;
    });
    const c = this.ctx;
    c.clearRect(0, 0, this.canvasW, this.canvasH);
    if (geo.length < 2) {
      return;
    }
    const lats: number[] = [];
    const lngs: number[] = [];
    geo.forEach((p: TrackPoint) => {
      lats.push(p.latitude as number);
      lngs.push(p.longitude as number);
    });
    let minLat = lats[0], maxLat = lats[0], minLng = lngs[0], maxLng = lngs[0];
    for (let i = 1; i < lats.length; i++) {
      if (lats[i] < minLat) {
        minLat = lats[i];
      }
      if (lats[i] > maxLat) {
        maxLat = lats[i];
      }
      if (lngs[i] < minLng) {
        minLng = lngs[i];
      }
      if (lngs[i] > maxLng) {
        maxLng = lngs[i];
      }
    }
    const spanLat = Math.max(maxLat - minLat, 1e-6);
    const spanLng = Math.max(maxLng - minLng, 1e-6);
    const pad = 16;
    const toX = (lng: number): number => pad + (lng - minLng) / spanLng * (this.canvasW - 2 * pad);
    const toY = (lat: number): number => pad + (1 - (lat - minLat) / spanLat) * (this.canvasH - 2 * pad);

    c.lineWidth = 4;
    c.strokeStyle = '#0A59F7';
    c.beginPath();
    c.moveTo(toX(lngs[0]), toY(lats[0]));
    for (let i = 1; i < lats.length; i++) {
      c.lineTo(toX(lngs[i]), toY(lats[i]));
    }
    c.stroke();

    c.fillStyle = '#4CAF50';
    c.beginPath();
    c.arc(toX(lngs[0]), toY(lats[0]), 9, 0, Math.PI * 2);
    c.fill();
    c.fillStyle = '#F44336';
    c.beginPath();
    const last = lats.length - 1;
    c.arc(toX(lngs[last]), toY(lats[last]), 9, 0, Math.PI * 2);
    c.fill();
  }

  private pointSub(p: TrackPoint): string {
    let s = p.latitude !== undefined
      ? `${(p.latitude as number).toFixed(5)}, ${(p.longitude as number).toFixed(5)}` : '无 GPS';
    if (p.headingDeg !== undefined) {
      s += `  ·  朝 ${p.headingDeg.toFixed(0)}° ${compassDir(p.headingDeg)}`;
    }
    if (p.magneticX !== undefined) {
      const x = p.magneticX;
      const y = p.magneticY as number;
      const z = p.magneticZ as number;
      const mm = Math.sqrt(x * x + y * y + z * z);
      s += `  ·  |B|=${mm.toFixed(0)} µT`;
    }
    s += `  ·  WiFi ${p.wifiCount} 个`;
    return s;
  }

  private tagSub(g: TrackTag): string {
    let s = fmtTime(g.timeMs);
    if (g.headingDeg !== undefined) {
      s += ` · 朝 ${g.headingDeg.toFixed(0)}°`;
    }
    if (g.latitude !== undefined && g.longitude !== undefined) {
      s += ` · ${g.latitude.toFixed(5)}, ${g.longitude.toFixed(5)}`;
    }
    return s;
  }

  build() {
    Column() {
      Row() {
        Button('‹ 返回').fontSize(14).onClick(() => {
          this.onBack();
        })
        Text(this.track ? this.track.name : '轨迹详情')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
      }.width('100%').padding({ left: 8, right: 12, top: 10, bottom: 10 })
      Divider()

      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 6 }) {
            Text('统计').fontSize(16).fontWeight(FontWeight.Medium).width('100%')
            this.InfoRow('区域', this.track
              ? (this.track.areaName !== undefined ? this.track.areaName : '未分区') : '-')
            this.InfoRow('开始', this.track ? fmtTime(this.track.startedAt) : '-')
            this.InfoRow('结束', this.track && this.track.endedAt !== undefined
              ? fmtTime(this.track.endedAt as number) : '进行中')
            this.InfoRow('时长', this.track ? fmtDuration(Math.floor(
              ((this.track.endedAt !== undefined ? this.track.endedAt : Date.now()) - this.track.startedAt) /
              1000)) : '-')
            this.InfoRow('采样点', `${this.points.length}`)
            this.InfoRow('标签', `${this.tags.length}`)
            this.InfoRow('照片', `${this.photos.length}`)
          }.width('100%').padding(16).backgroundColor('#FFF7F7F7').borderRadius(12)

          if (this.tags.length > 0 || this.photos.length > 0) {
            Column({ space: 10 }) {
              Text('标签与照片').fontSize(16).fontWeight(FontWeight.Medium).width('100%')

              if (this.tags.length > 0) {
                ForEach(this.tags, (g: TrackTag) => {
                  Row({ space: 8 }) {
                    Text(g.tagType)
                      .fontSize(12)
                      .fontColor('#0A59F7')
                      .backgroundColor('#1A0A59F7')
                      .borderRadius(4)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    Column({ space: 2 }) {
                      if (g.note.length > 0) {
                        Text(g.note).fontSize(13).width('100%')
                      }
                      Text(this.tagSub(g)).fontSize(11).fontColor('#99000000').width('100%')
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  }.width('100%')
                }, (g: TrackTag) => g.id + '')
              }

              if (this.photos.length > 0) {
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                  ForEach(this.photos, (ph: TrackPhoto) => {
                    Column({ space: 4 }) {
                      Image(this.photoAbs(ph))
                        .width(84)
                        .height(84)
                        .objectFit(ImageFit.Cover)
                        .borderRadius(8)
                        .onClick(() => {
                          this.openPhoto(ph);
                        })
                      Text(fmtTime(ph.timeMs))
                        .fontSize(10)
                        .fontColor('#99000000')
                      if (ph.note.length > 0) {
                        Text(ph.note)
                          .fontSize(10)
                          .fontColor('#99000000')
                          .width(84)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                    }.alignItems(HorizontalAlign.Start).margin({ right: 8, bottom: 8 })
                  }, (ph: TrackPhoto) => ph.id + '')
                }.width('100%')
              }
            }.width('100%').padding(16).backgroundColor('#FFF7F7F7').borderRadius(12)
          }

          if (this.geoCount() >= 2) {
            Column({ space: 6 }) {
              Text(`轨迹形状（${this.geoCount()} 个定位点，无 GPS 的室内点不显示）`)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .width('100%')
              Canvas(this.ctx)
                .width('100%')
                .height(200)
                .backgroundColor('#FFF5F5F5')
                .borderRadius(8)
                .onReady(() => {
                  this.drawPath();
                })
                .onAreaChange((oldA: Area, newA: Area) => {
                  this.canvasW = Number(newA.width);
                  this.canvasH = Number(newA.height);
                  this.drawPath();
                })
            }.width('100%').padding(16).backgroundColor('#FFF7F7F7').borderRadius(12)
          }

          Column({ space: 0 }) {
            ForEach(this.points, (p: TrackPoint) => {
              Column({ space: 4 }) {
                Row() {
                  Text(fmtTime(p.timeMs)).fontSize(14)
                  Blank()
                  Text(p.pressureHpa !== undefined ? `${p.pressureHpa.toFixed(1)} hPa` : '')
                    .fontSize(12)
                    .fontColor('#99000000')
                }.width('100%')
                Text(this.pointSub(p)).fontSize(12).fontColor('#99000000').width('100%')
                if (p.wifiTop.length > 0) {
                  Text(`AP: ${p.wifiTop}`)
                    .fontSize(12)
                    .fontColor('#99000000')
                    .width('100%')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }.width('100%').padding({ top: 8, bottom: 8 })
            }, (p: TrackPoint) => p.id + '')
          }.width('100%')
        }.padding(16).width('100%')
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%')
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor('#99000000').width(72)
      Text(value).fontSize(14)
    }.width('100%')
  }
}
