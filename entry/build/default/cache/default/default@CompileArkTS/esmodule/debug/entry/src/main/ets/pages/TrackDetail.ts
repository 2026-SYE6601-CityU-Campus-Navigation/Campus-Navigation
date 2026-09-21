if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface TrackDetailPage_Params {
    trackId?: number;
    onBack?: () => void;
    track?: Track | undefined;
    points?: TrackPoint[];
    tags?: TrackTag[];
    photos?: TrackPhoto[];
    photoViewDialog?: CustomDialogController | null;
    ctx?: CanvasRenderingContext2D;
    canvasW?;
    canvasH?;
    reload?;
}
interface PhotoViewDialog_Params {
    controller?: CustomDialogController;
    absPath?: string;
}
import type { Track, TrackPhoto, TrackPoint, TrackTag } from '../data/Entities';
import { Store } from "@bundle:com.example.roommarker/entry/ets/data/Store";
import { Ctx, compassDir, fmtDuration, fmtTime } from "@bundle:com.example.roommarker/entry/ets/common/Utils";
class PhotoViewDialog extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.controller = undefined;
        this.absPath = '';
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: PhotoViewDialog_Params) {
        if (params.controller !== undefined) {
            this.controller = params.controller;
        }
        if (params.absPath !== undefined) {
            this.absPath = params.absPath;
        }
    }
    updateStateVars(params: PhotoViewDialog_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
    }
    aboutToBeDeleted() {
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private controller?: CustomDialogController;
    setController(ctr: CustomDialogController) {
        this.controller = ctr;
    }
    private absPath: string;
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.padding(16);
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Image.create('file://' + this.absPath);
            Image.width('100%');
            Image.height(320);
            Image.objectFit(ImageFit.Contain);
            Image.borderRadius(8);
        }, Image);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('关闭');
            Button.onClick(() => {
                this.controller?.close();
            });
        }, Button);
        Button.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
export class TrackDetailPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.trackId = -1;
        this.onBack = () => {
        };
        this.__track = new ObservedPropertyObjectPU(undefined, this, "track");
        this.__points = new ObservedPropertyObjectPU([], this, "points");
        this.__tags = new ObservedPropertyObjectPU([], this, "tags");
        this.__photos = new ObservedPropertyObjectPU([], this, "photos");
        this.photoViewDialog = null;
        this.ctx = new CanvasRenderingContext2D(new RenderingContextSettings(true));
        this.canvasW = 0;
        this.canvasH = 0;
        this.reload = (): void => {
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
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: TrackDetailPage_Params) {
        if (params.trackId !== undefined) {
            this.trackId = params.trackId;
        }
        if (params.onBack !== undefined) {
            this.onBack = params.onBack;
        }
        if (params.track !== undefined) {
            this.track = params.track;
        }
        if (params.points !== undefined) {
            this.points = params.points;
        }
        if (params.tags !== undefined) {
            this.tags = params.tags;
        }
        if (params.photos !== undefined) {
            this.photos = params.photos;
        }
        if (params.photoViewDialog !== undefined) {
            this.photoViewDialog = params.photoViewDialog;
        }
        if (params.ctx !== undefined) {
            this.ctx = params.ctx;
        }
        if (params.canvasW !== undefined) {
            this.canvasW = params.canvasW;
        }
        if (params.canvasH !== undefined) {
            this.canvasH = params.canvasH;
        }
        if (params.reload !== undefined) {
            this.reload = params.reload;
        }
    }
    updateStateVars(params: TrackDetailPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__track.purgeDependencyOnElmtId(rmElmtId);
        this.__points.purgeDependencyOnElmtId(rmElmtId);
        this.__tags.purgeDependencyOnElmtId(rmElmtId);
        this.__photos.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__track.aboutToBeDeleted();
        this.__points.aboutToBeDeleted();
        this.__tags.aboutToBeDeleted();
        this.__photos.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private trackId: number;
    private onBack: () => void;
    private __track: ObservedPropertyObjectPU<Track | undefined>;
    get track() {
        return this.__track.get();
    }
    set track(newValue: Track | undefined) {
        this.__track.set(newValue);
    }
    private __points: ObservedPropertyObjectPU<TrackPoint[]>;
    get points() {
        return this.__points.get();
    }
    set points(newValue: TrackPoint[]) {
        this.__points.set(newValue);
    }
    private __tags: ObservedPropertyObjectPU<TrackTag[]>;
    get tags() {
        return this.__tags.get();
    }
    set tags(newValue: TrackTag[]) {
        this.__tags.set(newValue);
    }
    private __photos: ObservedPropertyObjectPU<TrackPhoto[]>;
    get photos() {
        return this.__photos.get();
    }
    set photos(newValue: TrackPhoto[]) {
        this.__photos.set(newValue);
    }
    private photoViewDialog: CustomDialogController | null;
    private ctx: CanvasRenderingContext2D;
    private canvasW;
    private canvasH;
    private reload;
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
            builder: () => {
                let jsDialog = new PhotoViewDialog(this, { absPath: this.photoAbs(ph) }, undefined, -1, () => { }, { page: "entry/src/main/ets/pages/TrackDetail.ets", line: 83, col: 16 });
                jsDialog.setController(this.photoViewDialog);
                ViewPU.create(jsDialog);
                let paramsLambda = () => {
                    return {
                        absPath: this.photoAbs(ph)
                    };
                };
                jsDialog.paramsGenerator_ = paramsLambda;
            },
            customStyle: false
        }, this);
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
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('100%');
            Column.height('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
            Row.padding({ left: 8, right: 12, top: 10, bottom: 10 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('‹ 返回');
            Button.fontSize(14);
            Button.onClick(() => {
                this.onBack();
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.track ? this.track.name : '轨迹详情');
            Text.fontSize(18);
            Text.fontWeight(FontWeight.Medium);
            Text.margin({ left: 12 });
            Text.maxLines(1);
            Text.textOverflow({ overflow: TextOverflow.Ellipsis });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
        }, Blank);
        Blank.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Divider.create();
        }, Divider);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.layoutWeight(1);
            Scroll.width('100%');
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.padding(16);
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 6 });
            Column.width('100%');
            Column.padding(16);
            Column.backgroundColor('#FFF7F7F7');
            Column.borderRadius(12);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('统计');
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Medium);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.InfoRow.bind(this)('区域', this.track
            ? (this.track.areaName !== undefined ? this.track.areaName : '未分区') : '-');
        this.InfoRow.bind(this)('开始', this.track ? fmtTime(this.track.startedAt) : '-');
        this.InfoRow.bind(this)('结束', this.track && this.track.endedAt !== undefined
            ? fmtTime(this.track.endedAt as number) : '进行中');
        this.InfoRow.bind(this)('时长', this.track ? fmtDuration(Math.floor(((this.track.endedAt !== undefined ? this.track.endedAt : Date.now()) - this.track.startedAt) /
            1000)) : '-');
        this.InfoRow.bind(this)('采样点', `${this.points.length}`);
        this.InfoRow.bind(this)('标签', `${this.tags.length}`);
        this.InfoRow.bind(this)('照片', `${this.photos.length}`);
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.tags.length > 0 || this.photos.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create({ space: 10 });
                        Column.width('100%');
                        Column.padding(16);
                        Column.backgroundColor('#FFF7F7F7');
                        Column.borderRadius(12);
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('标签与照片');
                        Text.fontSize(16);
                        Text.fontWeight(FontWeight.Medium);
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        If.create();
                        if (this.tags.length > 0) {
                            this.ifElseBranchUpdateFunction(0, () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    ForEach.create();
                                    const forEachItemGenFunction = _item => {
                                        const g = _item;
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            Row.create({ space: 8 });
                                            Row.width('100%');
                                        }, Row);
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            Text.create(g.tagType);
                                            Text.fontSize(12);
                                            Text.fontColor('#0A59F7');
                                            Text.backgroundColor('#1A0A59F7');
                                            Text.borderRadius(4);
                                            Text.padding({ left: 6, right: 6, top: 2, bottom: 2 });
                                        }, Text);
                                        Text.pop();
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            Column.create({ space: 2 });
                                            Column.layoutWeight(1);
                                            Column.alignItems(HorizontalAlign.Start);
                                        }, Column);
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            If.create();
                                            if (g.note.length > 0) {
                                                this.ifElseBranchUpdateFunction(0, () => {
                                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                        Text.create(g.note);
                                                        Text.fontSize(13);
                                                        Text.width('100%');
                                                    }, Text);
                                                    Text.pop();
                                                });
                                            }
                                            else {
                                                this.ifElseBranchUpdateFunction(1, () => {
                                                });
                                            }
                                        }, If);
                                        If.pop();
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            Text.create(this.tagSub(g));
                                            Text.fontSize(11);
                                            Text.fontColor('#99000000');
                                            Text.width('100%');
                                        }, Text);
                                        Text.pop();
                                        Column.pop();
                                        Row.pop();
                                    };
                                    this.forEachUpdateFunction(elmtId, this.tags, forEachItemGenFunction, (g: TrackTag) => g.id + '', false, false);
                                }, ForEach);
                                ForEach.pop();
                            });
                        }
                        else {
                            this.ifElseBranchUpdateFunction(1, () => {
                            });
                        }
                    }, If);
                    If.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        If.create();
                        if (this.photos.length > 0) {
                            this.ifElseBranchUpdateFunction(0, () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Flex.create({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start });
                                    Flex.width('100%');
                                }, Flex);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    ForEach.create();
                                    const forEachItemGenFunction = _item => {
                                        const ph = _item;
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            Column.create({ space: 4 });
                                            Column.alignItems(HorizontalAlign.Start);
                                            Column.margin({ right: 8, bottom: 8 });
                                        }, Column);
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            Image.create(this.photoAbs(ph));
                                            Image.width(84);
                                            Image.height(84);
                                            Image.objectFit(ImageFit.Cover);
                                            Image.borderRadius(8);
                                            Image.onClick(() => {
                                                this.openPhoto(ph);
                                            });
                                        }, Image);
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            Text.create(fmtTime(ph.timeMs));
                                            Text.fontSize(10);
                                            Text.fontColor('#99000000');
                                        }, Text);
                                        Text.pop();
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            If.create();
                                            if (ph.note.length > 0) {
                                                this.ifElseBranchUpdateFunction(0, () => {
                                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                        Text.create(ph.note);
                                                        Text.fontSize(10);
                                                        Text.fontColor('#99000000');
                                                        Text.width(84);
                                                        Text.maxLines(1);
                                                        Text.textOverflow({ overflow: TextOverflow.Ellipsis });
                                                    }, Text);
                                                    Text.pop();
                                                });
                                            }
                                            else {
                                                this.ifElseBranchUpdateFunction(1, () => {
                                                });
                                            }
                                        }, If);
                                        If.pop();
                                        Column.pop();
                                    };
                                    this.forEachUpdateFunction(elmtId, this.photos, forEachItemGenFunction, (ph: TrackPhoto) => ph.id + '', false, false);
                                }, ForEach);
                                ForEach.pop();
                                Flex.pop();
                            });
                        }
                        else {
                            this.ifElseBranchUpdateFunction(1, () => {
                            });
                        }
                    }, If);
                    If.pop();
                    Column.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.geoCount() >= 2) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create({ space: 6 });
                        Column.width('100%');
                        Column.padding(16);
                        Column.backgroundColor('#FFF7F7F7');
                        Column.borderRadius(12);
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(`轨迹形状（${this.geoCount()} 个定位点，无 GPS 的室内点不显示）`);
                        Text.fontSize(14);
                        Text.fontWeight(FontWeight.Medium);
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Canvas.create(this.ctx);
                        Canvas.width('100%');
                        Canvas.height(200);
                        Canvas.backgroundColor('#FFF5F5F5');
                        Canvas.borderRadius(8);
                        Canvas.onReady(() => {
                            this.drawPath();
                        });
                        Canvas.onAreaChange((oldA: Area, newA: Area) => {
                            this.canvasW = Number(newA.width);
                            this.canvasH = Number(newA.height);
                            this.drawPath();
                        });
                    }, Canvas);
                    Canvas.pop();
                    Column.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 0 });
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const p = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Column.create({ space: 4 });
                    Column.width('100%');
                    Column.padding({ top: 8, bottom: 8 });
                }, Column);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Row.create();
                    Row.width('100%');
                }, Row);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(fmtTime(p.timeMs));
                    Text.fontSize(14);
                }, Text);
                Text.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Blank.create();
                }, Blank);
                Blank.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(p.pressureHpa !== undefined ? `${p.pressureHpa.toFixed(1)} hPa` : '');
                    Text.fontSize(12);
                    Text.fontColor('#99000000');
                }, Text);
                Text.pop();
                Row.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(this.pointSub(p));
                    Text.fontSize(12);
                    Text.fontColor('#99000000');
                    Text.width('100%');
                }, Text);
                Text.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    If.create();
                    if (p.wifiTop.length > 0) {
                        this.ifElseBranchUpdateFunction(0, () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(`AP: ${p.wifiTop}`);
                                Text.fontSize(12);
                                Text.fontColor('#99000000');
                                Text.width('100%');
                                Text.maxLines(1);
                                Text.textOverflow({ overflow: TextOverflow.Ellipsis });
                            }, Text);
                            Text.pop();
                        });
                    }
                    else {
                        this.ifElseBranchUpdateFunction(1, () => {
                        });
                    }
                }, If);
                If.pop();
                Column.pop();
            };
            this.forEachUpdateFunction(elmtId, this.points, forEachItemGenFunction, (p: TrackPoint) => p.id + '', false, false);
        }, ForEach);
        ForEach.pop();
        Column.pop();
        Column.pop();
        Scroll.pop();
        Column.pop();
    }
    InfoRow(label: string, value: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(label);
            Text.fontSize(14);
            Text.fontColor('#99000000');
            Text.width(72);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(value);
            Text.fontSize(14);
        }, Text);
        Text.pop();
        Row.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
