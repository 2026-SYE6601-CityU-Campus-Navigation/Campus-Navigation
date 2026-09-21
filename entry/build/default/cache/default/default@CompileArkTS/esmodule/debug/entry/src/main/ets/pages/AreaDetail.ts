if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface AreaDetailPage_Params {
    areaId?: number;
    onBack?: () => void;
    onOpenRoom?: (id: number) => void;
    onOpenTrack?: (id: number) => void;
    area?: Area | undefined;
    rooms?: Room[];
    tracks?: Track[];
    heartbeat?: number;
    timer?: number;
    reload?;
    addRoomDialog?: CustomDialogController;
    startDialog?: CustomDialogController | null;
}
interface AddRoomDialog_Params {
    controller?: CustomDialogController;
    onSave?: (name: string, note: string) => void;
    name?: string;
    note?: string;
}
import promptAction from "@ohos:promptAction";
import type { Area, Room, Track } from '../data/Entities';
import { Store, UNASSIGNED_AREA_ID } from "@bundle:com.example.roommarker/entry/ets/data/Store";
import { TrackRecorder } from "@bundle:com.example.roommarker/entry/ets/sensors/TrackRecorder";
import { RecordingBanner } from "@bundle:com.example.roommarker/entry/ets/pages/RecordingBanner";
import { StartTrackDialog } from "@bundle:com.example.roommarker/entry/ets/pages/TrackList";
import { Exporter } from "@bundle:com.example.roommarker/entry/ets/common/Exporter";
import { fmtDuration, fmtTime } from "@bundle:com.example.roommarker/entry/ets/common/Utils";
class AddRoomDialog extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.controller = undefined;
        this.onSave = undefined;
        this.__name = new ObservedPropertySimplePU('', this, "name");
        this.__note = new ObservedPropertySimplePU('', this, "note");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: AddRoomDialog_Params) {
        if (params.controller !== undefined) {
            this.controller = params.controller;
        }
        if (params.onSave !== undefined) {
            this.onSave = params.onSave;
        }
        if (params.name !== undefined) {
            this.name = params.name;
        }
        if (params.note !== undefined) {
            this.note = params.note;
        }
    }
    updateStateVars(params: AddRoomDialog_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__name.purgeDependencyOnElmtId(rmElmtId);
        this.__note.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__name.aboutToBeDeleted();
        this.__note.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private controller?: CustomDialogController;
    setController(ctr: CustomDialogController) {
        this.controller = ctr;
    }
    private onSave?: (name: string, note: string) => void;
    private __name: ObservedPropertySimplePU<string>;
    get name() {
        return this.__name.get();
    }
    set name(newValue: string) {
        this.__name.set(newValue);
    }
    private __note: ObservedPropertySimplePU<string>;
    get note() {
        return this.__note.get();
    }
    set note(newValue: string) {
        this.__note.set(newValue);
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.padding(16);
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('添加房间');
            Text.fontSize(18);
            Text.fontWeight(FontWeight.Medium);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ placeholder: '房间名称（如：301 会议室）' });
            TextInput.onChange((v: string) => {
                this.name = v;
            });
        }, TextInput);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ placeholder: '备注（可选）' });
            TextInput.onChange((v: string) => {
                this.note = v;
            });
        }, TextInput);
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
            Button.createWithLabel('保存并打开');
            Button.enabled(this.name.trim().length > 0);
            Button.onClick(() => {
                this.controller?.close();
                if (this.onSave) {
                    this.onSave(this.name.trim(), this.note.trim());
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
export class AreaDetailPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.areaId = UNASSIGNED_AREA_ID;
        this.onBack = () => {
        };
        this.onOpenRoom = (id: number) => {
        };
        this.onOpenTrack = (id: number) => {
        };
        this.__area = new ObservedPropertyObjectPU(undefined, this, "area");
        this.__rooms = new ObservedPropertyObjectPU([], this, "rooms");
        this.__tracks = new ObservedPropertyObjectPU([], this, "tracks");
        this.__heartbeat = new ObservedPropertySimplePU(0, this, "heartbeat");
        this.timer = -1;
        this.reload = (): void => {
            if (this.isUnassigned()) {
                this.area = {
                    id: UNASSIGNED_AREA_ID,
                    name: '未分区',
                    note: '升级前的旧数据，尚未归属任何区域',
                    roomCount: 0,
                    trackCount: 0,
                    createdAt: 0
                };
            }
            else {
                Store.getArea(this.areaId).then((a: Area | undefined) => {
                    if (a) {
                        this.area = a;
                    }
                });
            }
            Store.listRooms(this.areaId).then((r: Room[]) => {
                this.rooms = r;
            });
            Store.listTracksInArea(this.areaId).then((t: Track[]) => {
                this.tracks = t;
            });
        };
        this.addRoomDialog = new CustomDialogController({
            builder: () => {
                let jsDialog = new AddRoomDialog(this, {
                    onSave: (name: string, note: string): void => {
                        const n = name.trim();
                        if (n.length === 0) {
                            return;
                        }
                        Store.insertRoom(n, note.trim(), this.areaId).then((id: number) => {
                            this.onOpenRoom(id);
                        });
                    }
                }, undefined, -1, () => { }, { page: "entry/src/main/ets/pages/AreaDetail.ets", line: 114, col: 14 });
                jsDialog.setController(this.addRoomDialog);
                ViewPU.create(jsDialog);
                let paramsLambda = () => {
                    return {
                        onSave: (name: string, note: string): void => {
                            const n = name.trim();
                            if (n.length === 0) {
                                return;
                            }
                            Store.insertRoom(n, note.trim(), this.areaId).then((id: number) => {
                                this.onOpenRoom(id);
                            });
                        }
                    };
                };
                jsDialog.paramsGenerator_ = paramsLambda;
            },
            customStyle: false
        }, this);
        this.startDialog = null;
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: AreaDetailPage_Params) {
        if (params.areaId !== undefined) {
            this.areaId = params.areaId;
        }
        if (params.onBack !== undefined) {
            this.onBack = params.onBack;
        }
        if (params.onOpenRoom !== undefined) {
            this.onOpenRoom = params.onOpenRoom;
        }
        if (params.onOpenTrack !== undefined) {
            this.onOpenTrack = params.onOpenTrack;
        }
        if (params.area !== undefined) {
            this.area = params.area;
        }
        if (params.rooms !== undefined) {
            this.rooms = params.rooms;
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
        if (params.addRoomDialog !== undefined) {
            this.addRoomDialog = params.addRoomDialog;
        }
        if (params.startDialog !== undefined) {
            this.startDialog = params.startDialog;
        }
    }
    updateStateVars(params: AreaDetailPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__area.purgeDependencyOnElmtId(rmElmtId);
        this.__rooms.purgeDependencyOnElmtId(rmElmtId);
        this.__tracks.purgeDependencyOnElmtId(rmElmtId);
        this.__heartbeat.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__area.aboutToBeDeleted();
        this.__rooms.aboutToBeDeleted();
        this.__tracks.aboutToBeDeleted();
        this.__heartbeat.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private areaId: number;
    private onBack: () => void;
    private onOpenRoom: (id: number) => void;
    private onOpenTrack: (id: number) => void;
    private __area: ObservedPropertyObjectPU<Area | undefined>;
    get area() {
        return this.__area.get();
    }
    set area(newValue: Area | undefined) {
        this.__area.set(newValue);
    }
    private __rooms: ObservedPropertyObjectPU<Room[]>;
    get rooms() {
        return this.__rooms.get();
    }
    set rooms(newValue: Room[]) {
        this.__rooms.set(newValue);
    }
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
    private areaName(): string {
        if (this.areaId === UNASSIGNED_AREA_ID) {
            return '未分区';
        }
        return this.area ? this.area.name : '区域';
    }
    private isUnassigned(): boolean {
        return this.areaId === UNASSIGNED_AREA_ID;
    }
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
    private addRoomDialog: CustomDialogController;
    private startDialog: CustomDialogController | null;
    /** 打开时动态构造（成员初始化阶段 this.areaId 可能尚未赋值，须在点击时读取） */
    private openStartDialog(): void {
        this.startDialog = new CustomDialogController({
            builder: () => {
                let jsDialog = new StartTrackDialog(this, {
                    defaultAreaId: this.areaId,
                    onStart: (name: string, areaId: number): void => {
                        TrackRecorder.get().start(name, areaId).catch(() => {
                            promptAction.showToast({ message: '启动记录失败' });
                        });
                    }
                }, undefined, -1, () => { }, { page: "entry/src/main/ets/pages/AreaDetail.ets", line: 133, col: 16 });
                jsDialog.setController(this.startDialog);
                ViewPU.create(jsDialog);
                let paramsLambda = () => {
                    return {
                        defaultAreaId: this.areaId,
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
        this.startDialog.open();
    }
    private exportZip(): void {
        const name = this.areaName();
        promptAction.showToast({ message: `正在打包「${name}」的数据…` });
        Exporter.exportAreaZip(this.areaId, name).then((zipName: string) => {
            promptAction.showToast({ message: `已导出 ${zipName}` });
        }).catch((e: Error) => {
            promptAction.showToast({ message: e.message });
        });
    }
    private deleteArea(): void {
        promptAction.showDialog({
            title: `删除区域「${this.areaName()}」`,
            message: `房间 ${this.rooms.length} 个 · 轨迹 ${this.tracks.length} 条。\n移入未分区：保留全部数据；彻底删除：数据与照片将全部丢失。`,
            buttons: [
                { text: '取消', color: '#0A59F7' },
                { text: '移入未分区', color: '#99000000' },
                { text: '彻底删除', color: '#E84026' }
            ]
        }).then((res: promptAction.ShowDialogSuccessResponse) => {
            if (res.index === 1) {
                Store.moveAreaToUnassigned(this.areaId).then(() => {
                    promptAction.showToast({ message: '已移入未分区' });
                    this.onBack();
                });
            }
            else if (res.index === 2) {
                // 若正在记录该区域的轨迹，先停止，避免写入已删除的轨迹
                const rec = TrackRecorder.get();
                if (rec.isRunning()) {
                    rec.stop().catch(() => {
                    });
                }
                Store.deleteAreaCascade(this.areaId).then(() => {
                    promptAction.showToast({ message: '区域已删除' });
                    this.onBack();
                });
            }
        }).catch(() => {
        });
    }
    private trackSub(t: Track): string {
        const end = t.endedAt !== undefined ? t.endedAt : t.startedAt;
        let s = `${fmtTime(t.startedAt)} · 时长 ${fmtDuration(Math.floor((end - t.startedAt) / 1000))} · ${t.pointCount} 点`;
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
            Text.create(this.areaName());
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
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('导出');
            Button.fontSize(12);
            Button.onClick(() => {
                this.exportZip();
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (!this.isUnassigned()) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Button.createWithLabel('删除');
                        Button.fontSize(12);
                        Button.fontColor('#E84026');
                        Button.margin({ left: 8 });
                        Button.onClick(() => {
                            this.deleteArea();
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
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Divider.create();
        }, Divider);
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new RecordingBanner(this, {}, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/AreaDetail.ets", line: 222, col: 9 });
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
            Scroll.create();
            Scroll.layoutWeight(1);
            Scroll.width('100%');
            Scroll.scrollBar(BarState.Off);
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.padding(16);
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // 房间
            Column.create({ space: 8 });
            // 房间
            Column.width('100%');
            // 房间
            Column.padding(16);
            // 房间
            Column.backgroundColor('#FFF7F7F7');
            // 房间
            Column.borderRadius(12);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`房间（${this.rooms.length}）`);
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Medium);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('添加房间');
            Button.fontSize(13);
            Button.onClick(() => {
                this.addRoomDialog.open();
            });
        }, Button);
        Button.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.rooms.length === 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('该区域还没有房间');
                        Text.fontSize(13);
                        Text.fontColor('#99000000');
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
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const r = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Row.create();
                    Row.width('100%');
                    Row.padding({ top: 10, bottom: 10 });
                    Row.onClick(() => {
                        this.onOpenRoom(r.id);
                    });
                }, Row);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Column.create({ space: 4 });
                    Column.layoutWeight(1);
                }, Column);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(r.name);
                    Text.fontSize(15);
                    Text.width('100%');
                }, Text);
                Text.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(r.note.length > 0 ? r.note : '点击打开，可添加前门/后门等标记');
                    Text.fontSize(12);
                    Text.fontColor('#99000000');
                    Text.width('100%');
                }, Text);
                Text.pop();
                Column.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create('›');
                    Text.fontSize(18);
                    Text.fontColor('#99000000');
                }, Text);
                Text.pop();
                Row.pop();
            };
            this.forEachUpdateFunction(elmtId, this.rooms, forEachItemGenFunction, (r: Room) => r.id + '', false, false);
        }, ForEach);
        ForEach.pop();
        // 房间
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // 轨迹
            Column.create({ space: 8 });
            // 轨迹
            Column.width('100%');
            // 轨迹
            Column.padding(16);
            // 轨迹
            Column.backgroundColor('#FFF7F7F7');
            // 轨迹
            Column.borderRadius(12);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`轨迹（${this.tracks.length}）`);
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Medium);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.isUnassigned()) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('须在具体区域中记录轨迹');
                        Text.fontSize(12);
                        Text.fontColor('#99000000');
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Button.createWithLabel('开始记录');
                        Button.fontSize(13);
                        Button.onClick(() => {
                            this.openStartDialog();
                        });
                    }, Button);
                    Button.pop();
                });
            }
        }, If);
        If.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.tracks.length === 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.isUnassigned()
                            ? '未分区没有轨迹'
                            : '该区域还没有轨迹，点「开始记录」采集（途中可拍照/打标签）');
                        Text.fontSize(13);
                        Text.fontColor('#99000000');
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
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const t = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Row.create();
                    Row.width('100%');
                    Row.padding({ top: 10, bottom: 10 });
                    Row.onClick(() => {
                        this.onOpenTrack(t.id);
                    });
                }, Row);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Column.create({ space: 4 });
                    Column.layoutWeight(1);
                }, Column);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(t.name);
                    Text.fontSize(15);
                    Text.width('100%');
                }, Text);
                Text.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(this.trackSub(t));
                    Text.fontSize(12);
                    Text.fontColor('#99000000');
                    Text.width('100%');
                }, Text);
                Text.pop();
                Column.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create('›');
                    Text.fontSize(18);
                    Text.fontColor('#99000000');
                }, Text);
                Text.pop();
                Row.pop();
            };
            this.forEachUpdateFunction(elmtId, this.tracks, forEachItemGenFunction, (t: Track) => t.id + '', false, false);
        }, ForEach);
        ForEach.pop();
        // 轨迹
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.area && this.area.note.length > 0 && !this.isUnassigned()) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.area.note);
                        Text.fontSize(12);
                        Text.fontColor('#66000000');
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
        Column.pop();
        Scroll.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // FAB：未分区不允许开始记录；记录中横幅自带停止按钮（心跳重建驱动刷新）
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const h = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    If.create();
                    if (!AppStorage.get<boolean>('rm_recording') && !this.isUnassigned()) {
                        this.ifElseBranchUpdateFunction(0, () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Button.createWithLabel('开始记录');
                                Button.margin(16);
                                Button.onClick(() => {
                                    this.openStartDialog();
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
        // FAB：未分区不允许开始记录；记录中横幅自带停止按钮（心跳重建驱动刷新）
        ForEach.pop();
        Stack.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
