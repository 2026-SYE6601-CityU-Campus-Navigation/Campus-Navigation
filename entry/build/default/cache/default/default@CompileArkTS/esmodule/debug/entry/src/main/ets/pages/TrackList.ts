if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface TrackListPage_Params {
    onBack?: () => void;
    onOpenTrack?: (id: number) => void;
    tracks?: Track[];
    heartbeat?: number;
    timer?: number;
    reload?;
    startDialog?: CustomDialogController;
}
interface StartTrackDialog_Params {
    controller?: CustomDialogController;
    onStart?: (name: string, areaId: number) => void;
    /** 预选区域 id（从区域详情页进入时传入）；-1 表示不预选 */
    defaultAreaId?: number;
    name?: string;
    areas?: Area[];
    selAreaId?: number;
    selIndex?: number;
}
import promptAction from "@ohos:promptAction";
import type { Area, Track } from '../data/Entities';
import { Store } from "@bundle:com.example.roommarker/entry/ets/data/Store";
import { TrackRecorder } from "@bundle:com.example.roommarker/entry/ets/sensors/TrackRecorder";
import { RecordingBanner } from "@bundle:com.example.roommarker/entry/ets/pages/RecordingBanner";
import { defaultTrackName, fmtDuration, fmtTime } from "@bundle:com.example.roommarker/entry/ets/common/Utils";
export class StartTrackDialog extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.controller = undefined;
        this.onStart = undefined;
        this.defaultAreaId = -1;
        this.__name = new ObservedPropertySimplePU('', this, "name");
        this.__areas = new ObservedPropertyObjectPU([], this, "areas");
        this.__selAreaId = new ObservedPropertySimplePU(-1, this, "selAreaId");
        this.__selIndex = new ObservedPropertySimplePU(0, this, "selIndex");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: StartTrackDialog_Params) {
        if (params.controller !== undefined) {
            this.controller = params.controller;
        }
        if (params.onStart !== undefined) {
            this.onStart = params.onStart;
        }
        if (params.defaultAreaId !== undefined) {
            this.defaultAreaId = params.defaultAreaId;
        }
        if (params.name !== undefined) {
            this.name = params.name;
        }
        if (params.areas !== undefined) {
            this.areas = params.areas;
        }
        if (params.selAreaId !== undefined) {
            this.selAreaId = params.selAreaId;
        }
        if (params.selIndex !== undefined) {
            this.selIndex = params.selIndex;
        }
    }
    updateStateVars(params: StartTrackDialog_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__name.purgeDependencyOnElmtId(rmElmtId);
        this.__areas.purgeDependencyOnElmtId(rmElmtId);
        this.__selAreaId.purgeDependencyOnElmtId(rmElmtId);
        this.__selIndex.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__name.aboutToBeDeleted();
        this.__areas.aboutToBeDeleted();
        this.__selAreaId.aboutToBeDeleted();
        this.__selIndex.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private controller?: CustomDialogController;
    setController(ctr: CustomDialogController) {
        this.controller = ctr;
    }
    private onStart?: (name: string, areaId: number) => void;
    /** 预选区域 id（从区域详情页进入时传入）；-1 表示不预选 */
    private defaultAreaId: number;
    private __name: ObservedPropertySimplePU<string>;
    get name() {
        return this.__name.get();
    }
    set name(newValue: string) {
        this.__name.set(newValue);
    }
    private __areas: ObservedPropertyObjectPU<Area[]>;
    get areas() {
        return this.__areas.get();
    }
    set areas(newValue: Area[]) {
        this.__areas.set(newValue);
    }
    private __selAreaId: ObservedPropertySimplePU<number>;
    get selAreaId() {
        return this.__selAreaId.get();
    }
    set selAreaId(newValue: number) {
        this.__selAreaId.set(newValue);
    }
    private __selIndex: ObservedPropertySimplePU<number>;
    get selIndex() {
        return this.__selIndex.get();
    }
    set selIndex(newValue: number) {
        this.__selIndex.set(newValue);
    }
    aboutToAppear(): void {
        this.name = defaultTrackName();
        Store.listAreas().then((list: Area[]) => {
            this.areas = list;
            if (list.length === 0) {
                this.selAreaId = -1;
                this.selIndex = 0;
                return;
            }
            let idx = 0;
            for (let i = 0; i < list.length; i++) {
                if (list[i].id === this.defaultAreaId) {
                    idx = i;
                    break;
                }
            }
            this.selIndex = idx;
            this.selAreaId = list[idx].id;
        });
    }
    private areaOptions(): Array<SelectOption> {
        const out: SelectOption[] = [];
        for (const a of this.areas) {
            out.push({ value: a.name });
        }
        return out;
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.padding(16);
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('开始记录轨迹');
            Text.fontSize(18);
            Text.fontWeight(FontWeight.Medium);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ text: this.name, placeholder: '轨迹名称' });
            TextInput.onChange((v: string) => {
                this.name = v;
            });
        }, TextInput);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('所在区域（必选）');
            Text.fontSize(14);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.areas.length === 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('还没有区域，请先在首页新建区域');
                        Text.fontSize(12);
                        Text.fontColor('#E84026');
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Select.create(this.areaOptions());
                        Select.selected(this.selIndex);
                        Select.onSelect((index: number, value: string) => {
                            this.selIndex = index;
                            this.selAreaId = this.areas[index].id;
                        });
                        Select.width('100%');
                    }, Select);
                    Select.pop();
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('开始后每秒采样 定位 + 气压 + 地磁 + 朝向 + WiFi，每 5 秒自动保存；途中可拍照、打标签');
            Text.fontSize(12);
            Text.fontColor('#99000000');
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 12 });
            Row.width('100%');
            Row.justifyContent(FlexAlign.End);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('取消');
            Button.onClick(() => {
                this.controller?.close();
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('开始');
            Button.enabled(this.name.trim().length > 0 && this.areas.length > 0);
            Button.onClick(() => {
                this.controller?.close();
                if (this.onStart) {
                    this.onStart(this.name.trim(), this.selAreaId);
                }
            });
        }, Button);
        Button.pop();
        Row.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
export class TrackListPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.onBack = () => {
        };
        this.onOpenTrack = (id: number) => {
        };
        this.__tracks = new ObservedPropertyObjectPU([], this, "tracks");
        this.__heartbeat = new ObservedPropertySimplePU(0, this, "heartbeat");
        this.timer = -1;
        this.reload = (): void => {
            Store.listTracks().then((t: Track[]) => {
                this.tracks = t;
            });
        };
        this.startDialog = new CustomDialogController({
            builder: () => {
                let jsDialog = new StartTrackDialog(this, {
                    defaultAreaId: -1,
                    onStart: (name: string, areaId: number): void => {
                        TrackRecorder.get().start(name, areaId).catch(() => {
                            promptAction.showToast({ message: '启动记录失败' });
                        });
                    }
                }, undefined, -1, () => { }, { page: "entry/src/main/ets/pages/TrackList.ets", line: 121, col: 14 });
                jsDialog.setController(this.startDialog);
                ViewPU.create(jsDialog);
                let paramsLambda = () => {
                    return {
                        defaultAreaId: -1,
                        onStart: (name: string, areaId: number): void => {
                            TrackRecorder.get().start(name, areaId).catch(() => {
                                promptAction.showToast({ message: '启动记录失败' });
                            });
                        }
                    };
                };
                jsDialog.paramsGenerator_ = paramsLambda;
            },
            customStyle: false
        }, this);
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: TrackListPage_Params) {
        if (params.onBack !== undefined) {
            this.onBack = params.onBack;
        }
        if (params.onOpenTrack !== undefined) {
            this.onOpenTrack = params.onOpenTrack;
        }
        if (params.tracks !== undefined) {
            this.tracks = params.tracks;
        }
        if (params.heartbeat !== undefined) {
            this.heartbeat = params.heartbeat;
        }
        if (params.timer !== undefined) {
            this.timer = params.timer;
        }
        if (params.reload !== undefined) {
            this.reload = params.reload;
        }
        if (params.startDialog !== undefined) {
            this.startDialog = params.startDialog;
        }
    }
    updateStateVars(params: TrackListPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__tracks.purgeDependencyOnElmtId(rmElmtId);
        this.__heartbeat.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__tracks.aboutToBeDeleted();
        this.__heartbeat.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private onBack: () => void;
    private onOpenTrack: (id: number) => void;
    private __tracks: ObservedPropertyObjectPU<Track[]>;
    get tracks() {
        return this.__tracks.get();
    }
    set tracks(newValue: Track[]) {
        this.__tracks.set(newValue);
    }
    private __heartbeat: ObservedPropertySimplePU<number>;
    get heartbeat() {
        return this.__heartbeat.get();
    }
    set heartbeat(newValue: number) {
        this.__heartbeat.set(newValue);
    }
    private timer: number;
    private reload;
    aboutToAppear(): void {
        this.reload();
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
    private startDialog: CustomDialogController;
    private trackSub(t: Track): string {
        const end = t.endedAt !== undefined ? t.endedAt : t.startedAt;
        const area = t.areaName !== undefined ? t.areaName : '未分区';
        let s = `[${area}] ${fmtTime(t.startedAt)} · 时长 ${fmtDuration(Math.floor((end - t.startedAt) / 1000))} · ${t.pointCount} 点`;
        if (t.endedAt === undefined) {
            s += ' · 进行中';
        }
        return s;
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create({ alignContent: Alignment.BottomEnd });
            Stack.width('100%');
            Stack.height('100%');
        }, Stack);
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
            Text.create('轨迹记录');
            Text.fontSize(18);
            Text.fontWeight(FontWeight.Medium);
            Text.margin({ left: 12 });
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
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new RecordingBanner(this, {}, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/TrackList.ets", line: 155, col: 9 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {};
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {});
                }
            }, { name: "RecordingBanner" });
        }
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.tracks.length === 0 && !AppStorage.get<boolean>('rm_recording')) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.width('100%');
                        Column.layoutWeight(1);
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Blank.create();
                    }, Blank);
                    Blank.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('还没有轨迹，点击右下角开始记录');
                        Text.fontColor('#99000000');
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Blank.create();
                    }, Blank);
                    Blank.pop();
                    Column.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        List.create();
                        List.width('100%');
                        List.layoutWeight(1);
                        List.divider({ strokeWidth: 0.5, color: '#1A000000' });
                    }, List);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const t = _item;
                            {
                                const itemCreation = (elmtId, isInitialRender) => {
                                    ViewStackProcessor.StartGetAccessRecordingFor(elmtId);
                                    ListItem.create(deepRenderFunction, true);
                                    if (!isInitialRender) {
                                        ListItem.pop();
                                    }
                                    ViewStackProcessor.StopGetAccessRecording();
                                };
                                const itemCreation2 = (elmtId, isInitialRender) => {
                                    ListItem.create(deepRenderFunction, true);
                                    ListItem.onClick(() => {
                                        this.onOpenTrack(t.id);
                                    });
                                };
                                const deepRenderFunction = (elmtId, isInitialRender) => {
                                    itemCreation(elmtId, isInitialRender);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Row.create();
                                        Row.width('100%');
                                        Row.padding({ left: 16, right: 12, top: 12, bottom: 12 });
                                    }, Row);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Column.create({ space: 4 });
                                        Column.layoutWeight(1);
                                    }, Column);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create(t.name);
                                        Text.fontSize(16);
                                        Text.width('100%');
                                    }, Text);
                                    Text.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create(this.trackSub(t));
                                        Text.fontSize(13);
                                        Text.fontColor('#99000000');
                                        Text.width('100%');
                                    }, Text);
                                    Text.pop();
                                    Column.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Button.createWithLabel('删除');
                                        Button.fontSize(12);
                                        Button.fontColor('#E84026');
                                        Button.onClick(() => {
                                            Store.deleteTrack(t.id).then(() => {
                                                promptAction.showToast({ message: '已删除轨迹' });
                                            });
                                        });
                                    }, Button);
                                    Button.pop();
                                    Row.pop();
                                    ListItem.pop();
                                };
                                this.observeComponentCreation2(itemCreation2, ListItem);
                                ListItem.pop();
                            }
                        };
                        this.forEachUpdateFunction(elmtId, this.tracks, forEachItemGenFunction, (t: Track) => t.id + '', false, false);
                    }, ForEach);
                    ForEach.pop();
                    List.pop();
                });
            }
        }, If);
        If.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // 记录中横幅自带停止按钮，FAB 只在未记录时显示（心跳重建驱动刷新）
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const h = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    If.create();
                    if (!AppStorage.get<boolean>('rm_recording')) {
                        this.ifElseBranchUpdateFunction(0, () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Button.createWithLabel('开始记录');
                                Button.margin(16);
                                Button.onClick(() => {
                                    this.startDialog.open();
                                });
                            }, Button);
                            Button.pop();
                        });
                    }
                    else {
                        this.ifElseBranchUpdateFunction(1, () => {
                        });
                    }
                }, If);
                If.pop();
            };
            this.forEachUpdateFunction(elmtId, [this.heartbeat], forEachItemGenFunction, (h: number) => h + '', false, false);
        }, ForEach);
        // 记录中横幅自带停止按钮，FAB 只在未记录时显示（心跳重建驱动刷新）
        ForEach.pop();
        Stack.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
