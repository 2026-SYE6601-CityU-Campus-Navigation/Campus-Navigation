if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface RoomDetailPage_Params {
    roomId?: number;
    onBack?: () => void;
    room?: Room | undefined;
    markers?: Marker[];
    reload?;
    addDialog?: CustomDialogController;
}
interface AddMarkerDialog_Params {
    controller?: CustomDialogController;
    onSave?: (name: string, typeLabel: string) => void;
    name?: string;
    typeLabel?: string;
}
import promptAction from "@ohos:promptAction";
import { markerTypeOptions } from "@bundle:com.example.roommarker/entry/ets/data/Entities";
import type { Marker, Room } from "@bundle:com.example.roommarker/entry/ets/data/Entities";
import { Store } from "@bundle:com.example.roommarker/entry/ets/data/Store";
import { captureSnapshot } from "@bundle:com.example.roommarker/entry/ets/sensors/SensorSnapshotter";
import { coordText } from "@bundle:com.example.roommarker/entry/ets/common/Utils";
class AddMarkerDialog extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.controller = undefined;
        this.onSave = undefined;
        this.__name = new ObservedPropertySimplePU('', this, "name");
        this.__typeLabel = new ObservedPropertySimplePU('前门', this, "typeLabel");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: AddMarkerDialog_Params) {
        if (params.controller !== undefined) {
            this.controller = params.controller;
        }
        if (params.onSave !== undefined) {
            this.onSave = params.onSave;
        }
        if (params.name !== undefined) {
            this.name = params.name;
        }
        if (params.typeLabel !== undefined) {
            this.typeLabel = params.typeLabel;
        }
    }
    updateStateVars(params: AddMarkerDialog_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__name.purgeDependencyOnElmtId(rmElmtId);
        this.__typeLabel.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__name.aboutToBeDeleted();
        this.__typeLabel.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private controller?: CustomDialogController;
    setController(ctr: CustomDialogController) {
        this.controller = ctr;
    }
    private onSave?: (name: string, typeLabel: string) => void;
    private __name: ObservedPropertySimplePU<string>;
    get name() {
        return this.__name.get();
    }
    set name(newValue: string) {
        this.__name.set(newValue);
    }
    private __typeLabel: ObservedPropertySimplePU<string>;
    get typeLabel() {
        return this.__typeLabel.get();
    }
    set typeLabel(newValue: string) {
        this.__typeLabel.set(newValue);
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.padding(16);
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('添加标记');
            Text.fontSize(18);
            Text.fontWeight(FontWeight.Medium);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ placeholder: '名称（如：前门）' });
            TextInput.onChange((v: string) => {
                this.name = v;
            });
        }, TextInput);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Select.create(markerTypeOptions());
            Select.selected(0);
            Select.onSelect((index: number, value: string) => {
                this.typeLabel = value;
            });
            Select.width('100%');
        }, Select);
        Select.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('保存时将自动采集：定位 + 气压 + 地磁快照');
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
            Button.createWithLabel('采集并保存');
            Button.enabled(this.name.trim().length > 0);
            Button.onClick(() => {
                this.controller?.close();
                if (this.onSave) {
                    this.onSave(this.name, this.typeLabel);
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
export class RoomDetailPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.roomId = -1;
        this.onBack = () => {
        };
        this.__room = new ObservedPropertyObjectPU(undefined, this, "room");
        this.__markers = new ObservedPropertyObjectPU([], this, "markers");
        this.reload = (): void => {
            Store.getRoom(this.roomId).then((r: Room | undefined) => {
                if (r) {
                    this.room = r;
                }
            });
            Store.listMarkers(this.roomId).then((ms: Marker[]) => {
                this.markers = ms;
            });
        };
        this.addDialog = new CustomDialogController({
            builder: () => {
                let jsDialog = new AddMarkerDialog(this, {
                    onSave: (name: string, typeLabel: string): void => {
                        this.addMarker(name, typeLabel);
                    }
                }, undefined, -1, () => { }, { page: "entry/src/main/ets/pages/RoomDetail.ets", line: 77, col: 14 });
                jsDialog.setController(this.addDialog);
                ViewPU.create(jsDialog);
                let paramsLambda = () => {
                    return {
                        onSave: (name: string, typeLabel: string): void => {
                            this.addMarker(name, typeLabel);
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
    setInitiallyProvidedValue(params: RoomDetailPage_Params) {
        if (params.roomId !== undefined) {
            this.roomId = params.roomId;
        }
        if (params.onBack !== undefined) {
            this.onBack = params.onBack;
        }
        if (params.room !== undefined) {
            this.room = params.room;
        }
        if (params.markers !== undefined) {
            this.markers = params.markers;
        }
        if (params.reload !== undefined) {
            this.reload = params.reload;
        }
        if (params.addDialog !== undefined) {
            this.addDialog = params.addDialog;
        }
    }
    updateStateVars(params: RoomDetailPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__room.purgeDependencyOnElmtId(rmElmtId);
        this.__markers.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__room.aboutToBeDeleted();
        this.__markers.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private roomId: number;
    private onBack: () => void;
    private __room: ObservedPropertyObjectPU<Room | undefined>;
    get room() {
        return this.__room.get();
    }
    set room(newValue: Room | undefined) {
        this.__room.set(newValue);
    }
    private __markers: ObservedPropertyObjectPU<Marker[]>;
    get markers() {
        return this.__markers.get();
    }
    set markers(newValue: Marker[]) {
        this.__markers.set(newValue);
    }
    private reload;
    aboutToAppear(): void {
        this.reload();
        Store.subscribe(this.reload);
    }
    aboutToDisappear(): void {
        Store.unsubscribe(this.reload);
    }
    private addDialog: CustomDialogController;
    private addMarker(name: string, typeLabel: string): void {
        captureSnapshot().then((s) => {
            Store.insertMarker(this.roomId, name.trim(), typeLabel, s.latitude, s.longitude, s.altitude, s.accuracy, s.pressureHpa, s.magneticX, s.magneticY, s.magneticZ)
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
                { text: '取消', color: '#0A59F7' },
                { text: '删除', color: '#E84026' }
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
            Text.create(this.room ? this.room.name : '房间');
            Text.fontSize(18);
            Text.fontWeight(FontWeight.Medium);
            Text.margin({ left: 12 });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('记基准点');
            Button.fontSize(12);
            Button.onClick(() => {
                this.setBasePoint();
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('删除');
            Button.fontSize(12);
            Button.fontColor('#E84026');
            Button.margin({ left: 8 });
            Button.onClick(() => {
                this.confirmDeleteRoom();
            });
        }, Button);
        Button.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Divider.create();
        }, Divider);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            List.create();
            List.width('100%');
            List.layoutWeight(1);
            List.divider({ strokeWidth: 0.5, color: '#1A000000' });
        }, List);
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
            };
            const deepRenderFunction = (elmtId, isInitialRender) => {
                itemCreation(elmtId, isInitialRender);
                this.BasePointCard.bind(this)();
                ListItem.pop();
            };
            this.observeComponentCreation2(itemCreation2, ListItem);
            ListItem.pop();
        }
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const m = _item;
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
                    };
                    const deepRenderFunction = (elmtId, isInitialRender) => {
                        itemCreation(elmtId, isInitialRender);
                        this.MarkerRow.bind(this)(m);
                        ListItem.pop();
                    };
                    this.observeComponentCreation2(itemCreation2, ListItem);
                    ListItem.pop();
                }
            };
            this.forEachUpdateFunction(elmtId, this.markers, forEachItemGenFunction, (m: Marker) => m.id + '', false, false);
        }, ForEach);
        ForEach.pop();
        List.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('添加标记');
            Button.margin(16);
            Button.onClick(() => {
                this.addDialog.open();
            });
        }, Button);
        Button.pop();
        Stack.pop();
    }
    BasePointCard(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 4 });
            Column.width('100%');
            Column.padding(16);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('房间基准点');
            Text.fontSize(14);
            Text.fontWeight(FontWeight.Medium);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.room ? coordText(this.room.latitude, this.room.longitude) : '-');
            Text.fontSize(14);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.room && this.room.pressureHpa !== undefined
                ? `气压 ${this.room.pressureHpa.toFixed(1)} hPa` : '气压：未采集');
            Text.fontSize(12);
            Text.fontColor('#99000000');
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
    }
    MarkerRow(m: Marker, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 4 });
            Column.width('100%');
            Column.padding({ left: 16, right: 16, top: 12, bottom: 12 });
            Gesture.create(GesturePriority.Low);
            LongPressGesture.create();
            LongPressGesture.onAction(() => {
                Store.deleteMarker(m.id).then(() => {
                    promptAction.showToast({ message: `已删除「${m.name}」` });
                });
            });
            LongPressGesture.pop();
            Gesture.pop();
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(m.name);
            Text.fontSize(16);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(m.pressureHpa !== undefined ? `${m.pressureHpa.toFixed(1)} hPa` : '');
            Text.fontSize(12);
            Text.fontColor('#99000000');
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${m.markerType} · ${coordText(m.latitude, m.longitude)}`);
            Text.fontSize(13);
            Text.fontColor('#99000000');
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
