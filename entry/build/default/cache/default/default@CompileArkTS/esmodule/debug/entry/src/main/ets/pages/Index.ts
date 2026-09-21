if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface AreaListPage_Params {
    areas?: Area[];
    unassignedRoomCount?: number;
    unassignedTrackCount?: number;
    onOpenArea?: (id: number) => void;
    onTracks?: () => void;
    onLive?: () => void;
    reload?;
    addDialog?: CustomDialogController;
}
interface AddAreaDialog_Params {
    controller?: CustomDialogController;
    onSave?: (name: string, note: string) => void;
    name?: string;
    note?: string;
}
interface Index_Params {
    navStack?: NavPathStack;
}
import type { Area } from '../data/Entities';
import { Store, UNASSIGNED_AREA_ID } from "@bundle:com.example.roommarker/entry/ets/data/Store";
import { AreaDetailPage } from "@bundle:com.example.roommarker/entry/ets/pages/AreaDetail";
import { TrackListPage } from "@bundle:com.example.roommarker/entry/ets/pages/TrackList";
import { TrackDetailPage } from "@bundle:com.example.roommarker/entry/ets/pages/TrackDetail";
import { LiveSensorsPage } from "@bundle:com.example.roommarker/entry/ets/pages/LiveSensors";
import { RoomDetailPage } from "@bundle:com.example.roommarker/entry/ets/pages/RoomDetail";
class Index extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__navStack = new ObservedPropertyObjectPU(new NavPathStack(), this, "navStack");
        this.addProvidedVar("navStack", this.__navStack, false);
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: Index_Params) {
        if (params.navStack !== undefined) {
            this.navStack = params.navStack;
        }
    }
    updateStateVars(params: Index_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__navStack.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__navStack.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __navStack: ObservedPropertyObjectPU<NavPathStack>;
    get navStack() {
        return this.__navStack.get();
    }
    set navStack(newValue: NavPathStack) {
        this.__navStack.set(newValue);
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Navigation.create(this.navStack, { moduleName: "entry", pagePath: "entry/src/main/ets/pages/Index", isUserCreateStack: true });
            Navigation.hideTitleBar(true);
            Navigation.mode(NavigationMode.Stack);
            Navigation.navDestination({ builder: this.pageMapBuilder.bind(this) });
        }, Navigation);
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new AreaListPage(this, {
                        onOpenArea: (id: number) => {
                            this.navStack.pushPath({ name: 'area', param: id });
                        },
                        onTracks: () => {
                            this.navStack.pushPath({ name: 'tracks' });
                        },
                        onLive: () => {
                            this.navStack.pushPath({ name: 'live' });
                        }
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 17, col: 7 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            onOpenArea: (id: number) => {
                                this.navStack.pushPath({ name: 'area', param: id });
                            },
                            onTracks: () => {
                                this.navStack.pushPath({ name: 'tracks' });
                            },
                            onLive: () => {
                                this.navStack.pushPath({ name: 'live' });
                            }
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {});
                }
            }, { name: "AreaListPage" });
        }
        Navigation.pop();
    }
    pageMapBuilder(name: string, param?: Object, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (name === 'tracks') {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        NavDestination.create(() => {
                            {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    if (isInitialRender) {
                                        let componentCall = new TrackListPage(this, {
                                            onBack: () => {
                                                this.navStack.pop();
                                            },
                                            onOpenTrack: (id: number) => {
                                                this.navStack.pushPath({ name: 'track', param: id });
                                            }
                                        }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 38, col: 9 });
                                        ViewPU.create(componentCall);
                                        let paramsLambda = () => {
                                            return {
                                                onBack: () => {
                                                    this.navStack.pop();
                                                },
                                                onOpenTrack: (id: number) => {
                                                    this.navStack.pushPath({ name: 'track', param: id });
                                                }
                                            };
                                        };
                                        componentCall.paramsGenerator_ = paramsLambda;
                                    }
                                    else {
                                        this.updateStateVarsOfChildByElmtId(elmtId, {});
                                    }
                                }, { name: "TrackListPage" });
                            }
                        }, { moduleName: "entry", pagePath: "entry/src/main/ets/pages/Index" });
                        NavDestination.hideTitleBar(true);
                    }, NavDestination);
                    NavDestination.pop();
                });
            }
            else if (name === 'live') {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        NavDestination.create(() => {
                            {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    if (isInitialRender) {
                                        let componentCall = new LiveSensorsPage(this, {
                                            onBack: () => {
                                                this.navStack.pop();
                                            }
                                        }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 50, col: 9 });
                                        ViewPU.create(componentCall);
                                        let paramsLambda = () => {
                                            return {
                                                onBack: () => {
                                                    this.navStack.pop();
                                                }
                                            };
                                        };
                                        componentCall.paramsGenerator_ = paramsLambda;
                                    }
                                    else {
                                        this.updateStateVarsOfChildByElmtId(elmtId, {});
                                    }
                                }, { name: "LiveSensorsPage" });
                            }
                        }, { moduleName: "entry", pagePath: "entry/src/main/ets/pages/Index" });
                        NavDestination.hideTitleBar(true);
                    }, NavDestination);
                    NavDestination.pop();
                });
            }
            else if (name === 'room') {
                this.ifElseBranchUpdateFunction(2, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        NavDestination.create(() => {
                            {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    if (isInitialRender) {
                                        let componentCall = new RoomDetailPage(this, {
                                            roomId: param as number,
                                            onBack: () => {
                                                this.navStack.pop();
                                            }
                                        }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 59, col: 9 });
                                        ViewPU.create(componentCall);
                                        let paramsLambda = () => {
                                            return {
                                                roomId: param as number,
                                                onBack: () => {
                                                    this.navStack.pop();
                                                }
                                            };
                                        };
                                        componentCall.paramsGenerator_ = paramsLambda;
                                    }
                                    else {
                                        this.updateStateVarsOfChildByElmtId(elmtId, {});
                                    }
                                }, { name: "RoomDetailPage" });
                            }
                        }, { moduleName: "entry", pagePath: "entry/src/main/ets/pages/Index" });
                        NavDestination.hideTitleBar(true);
                    }, NavDestination);
                    NavDestination.pop();
                });
            }
            else if (name === 'track') {
                this.ifElseBranchUpdateFunction(3, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        NavDestination.create(() => {
                            {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    if (isInitialRender) {
                                        let componentCall = new TrackDetailPage(this, {
                                            trackId: param as number,
                                            onBack: () => {
                                                this.navStack.pop();
                                            }
                                        }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 69, col: 9 });
                                        ViewPU.create(componentCall);
                                        let paramsLambda = () => {
                                            return {
                                                trackId: param as number,
                                                onBack: () => {
                                                    this.navStack.pop();
                                                }
                                            };
                                        };
                                        componentCall.paramsGenerator_ = paramsLambda;
                                    }
                                    else {
                                        this.updateStateVarsOfChildByElmtId(elmtId, {});
                                    }
                                }, { name: "TrackDetailPage" });
                            }
                        }, { moduleName: "entry", pagePath: "entry/src/main/ets/pages/Index" });
                        NavDestination.hideTitleBar(true);
                    }, NavDestination);
                    NavDestination.pop();
                });
            }
            else if (name === 'area') {
                this.ifElseBranchUpdateFunction(4, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        NavDestination.create(() => {
                            {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    if (isInitialRender) {
                                        let componentCall = new AreaDetailPage(this, {
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
                                        }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 79, col: 9 });
                                        ViewPU.create(componentCall);
                                        let paramsLambda = () => {
                                            return {
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
                                            };
                                        };
                                        componentCall.paramsGenerator_ = paramsLambda;
                                    }
                                    else {
                                        this.updateStateVarsOfChildByElmtId(elmtId, {});
                                    }
                                }, { name: "AreaDetailPage" });
                            }
                        }, { moduleName: "entry", pagePath: "entry/src/main/ets/pages/Index" });
                        NavDestination.hideTitleBar(true);
                    }, NavDestination);
                    NavDestination.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(5, () => {
                });
            }
        }, If);
        If.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "Index";
    }
}
class AddAreaDialog extends ViewPU {
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
    setInitiallyProvidedValue(params: AddAreaDialog_Params) {
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
    updateStateVars(params: AddAreaDialog_Params) {
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
            Text.create('新建区域');
            Text.fontSize(18);
            Text.fontWeight(FontWeight.Medium);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ placeholder: '区域名称（如：AC1 三楼 / 图书馆二层）' });
            TextInput.onChange((v: string) => {
                this.name = v;
            });
        }, TextInput);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ placeholder: '备注（可选，如：含 301-320 教室）' });
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
            Button.createWithLabel('创建');
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
class AreaListPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__areas = new ObservedPropertyObjectPU([], this, "areas");
        this.__unassignedRoomCount = new ObservedPropertySimplePU(0, this, "unassignedRoomCount");
        this.__unassignedTrackCount = new ObservedPropertySimplePU(0, this, "unassignedTrackCount");
        this.onOpenArea = (id: number) => {
        };
        this.onTracks = () => {
        };
        this.onLive = () => {
        };
        this.reload = (): void => {
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
        this.addDialog = new CustomDialogController({
            builder: () => {
                let jsDialog = new AddAreaDialog(this, {
                    onSave: (name: string, note: string): void => {
                        const n = name.trim();
                        if (n.length === 0) {
                            return;
                        }
                        Store.insertArea(n, note.trim()).then((id: number) => {
                            this.onOpenArea(id);
                        });
                    }
                }, undefined, -1, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 166, col: 14 });
                jsDialog.setController(this.addDialog);
                ViewPU.create(jsDialog);
                let paramsLambda = () => {
                    return {
                        onSave: (name: string, note: string): void => {
                            const n = name.trim();
                            if (n.length === 0) {
                                return;
                            }
                            Store.insertArea(n, note.trim()).then((id: number) => {
                                this.onOpenArea(id);
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
    setInitiallyProvidedValue(params: AreaListPage_Params) {
        if (params.areas !== undefined) {
            this.areas = params.areas;
        }
        if (params.unassignedRoomCount !== undefined) {
            this.unassignedRoomCount = params.unassignedRoomCount;
        }
        if (params.unassignedTrackCount !== undefined) {
            this.unassignedTrackCount = params.unassignedTrackCount;
        }
        if (params.onOpenArea !== undefined) {
            this.onOpenArea = params.onOpenArea;
        }
        if (params.onTracks !== undefined) {
            this.onTracks = params.onTracks;
        }
        if (params.onLive !== undefined) {
            this.onLive = params.onLive;
        }
        if (params.reload !== undefined) {
            this.reload = params.reload;
        }
        if (params.addDialog !== undefined) {
            this.addDialog = params.addDialog;
        }
    }
    updateStateVars(params: AreaListPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__areas.purgeDependencyOnElmtId(rmElmtId);
        this.__unassignedRoomCount.purgeDependencyOnElmtId(rmElmtId);
        this.__unassignedTrackCount.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__areas.aboutToBeDeleted();
        this.__unassignedRoomCount.aboutToBeDeleted();
        this.__unassignedTrackCount.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __areas: ObservedPropertyObjectPU<Area[]>;
    get areas() {
        return this.__areas.get();
    }
    set areas(newValue: Area[]) {
        this.__areas.set(newValue);
    }
    private __unassignedRoomCount: ObservedPropertySimplePU<number>;
    get unassignedRoomCount() {
        return this.__unassignedRoomCount.get();
    }
    set unassignedRoomCount(newValue: number) {
        this.__unassignedRoomCount.set(newValue);
    }
    private __unassignedTrackCount: ObservedPropertySimplePU<number>;
    get unassignedTrackCount() {
        return this.__unassignedTrackCount.get();
    }
    set unassignedTrackCount(newValue: number) {
        this.__unassignedTrackCount.set(newValue);
    }
    private onOpenArea: (id: number) => void;
    private onTracks: () => void;
    private onLive: () => void;
    private reload;
    aboutToAppear(): void {
        this.reload();
        Store.subscribe(this.reload);
    }
    aboutToDisappear(): void {
        Store.unsubscribe(this.reload);
    }
    private addDialog: CustomDialogController;
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
            Row.padding({ left: 16, right: 12, top: 14, bottom: 12 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('RoomMarker 数据采集');
            Text.fontSize(20);
            Text.fontWeight(FontWeight.Bold);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('全部轨迹');
            Button.fontSize(13);
            Button.onClick(() => {
                this.onTracks();
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('实时');
            Button.fontSize(13);
            Button.margin({ left: 8 });
            Button.onClick(() => {
                this.onLive();
            });
        }, Button);
        Button.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Divider.create();
        }, Divider);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.areas.length === 0 && this.unassignedRoomCount === 0 && this.unassignedTrackCount === 0) {
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
                        Text.create('还没有区域，点击右下角新建');
                        Text.fontColor('#99000000');
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('按楼栋/楼层划区域后开始收集数据');
                        Text.fontSize(12);
                        Text.fontColor('#66000000');
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
                        If.create();
                        if (this.unassignedRoomCount + this.unassignedTrackCount > 0) {
                            this.ifElseBranchUpdateFunction(0, () => {
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
                                            this.onOpenArea(UNASSIGNED_AREA_ID);
                                        });
                                    };
                                    const deepRenderFunction = (elmtId, isInitialRender) => {
                                        itemCreation(elmtId, isInitialRender);
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            Column.create({ space: 4 });
                                            Column.width('100%');
                                            Column.padding({ left: 16, right: 16, top: 12, bottom: 12 });
                                        }, Column);
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            Text.create('未分区数据');
                                            Text.fontSize(16);
                                            Text.width('100%');
                                        }, Text);
                                        Text.pop();
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            Text.create(`旧数据 · 房间 ${this.unassignedRoomCount} · 轨迹 ${this.unassignedTrackCount}`);
                                            Text.fontSize(13);
                                            Text.fontColor('#99000000');
                                            Text.width('100%');
                                        }, Text);
                                        Text.pop();
                                        Column.pop();
                                        ListItem.pop();
                                    };
                                    this.observeComponentCreation2(itemCreation2, ListItem);
                                    ListItem.pop();
                                }
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
                            const a = _item;
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
                                        this.onOpenArea(a.id);
                                    });
                                };
                                const deepRenderFunction = (elmtId, isInitialRender) => {
                                    itemCreation(elmtId, isInitialRender);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Column.create({ space: 4 });
                                        Column.width('100%');
                                        Column.padding({ left: 16, right: 16, top: 12, bottom: 12 });
                                    }, Column);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create(a.name);
                                        Text.fontSize(16);
                                        Text.width('100%');
                                    }, Text);
                                    Text.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create(a.note.length > 0
                                            ? `${a.note} · 房间 ${a.roomCount} · 轨迹 ${a.trackCount}`
                                            : `房间 ${a.roomCount} · 轨迹 ${a.trackCount}`);
                                        Text.fontSize(13);
                                        Text.fontColor('#99000000');
                                        Text.width('100%');
                                    }, Text);
                                    Text.pop();
                                    Column.pop();
                                    ListItem.pop();
                                };
                                this.observeComponentCreation2(itemCreation2, ListItem);
                                ListItem.pop();
                            }
                        };
                        this.forEachUpdateFunction(elmtId, this.areas, forEachItemGenFunction, (a: Area) => a.id + '', false, false);
                    }, ForEach);
                    ForEach.pop();
                    List.pop();
                });
            }
        }, If);
        If.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('新建区域');
            Button.margin(16);
            Button.onClick(() => {
                this.addDialog.open();
            });
        }, Button);
        Button.pop();
        Stack.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
registerNamedRoute(() => new Index(undefined, {}), "", { bundleName: "com.example.roommarker", moduleName: "entry", pagePath: "pages/Index", pageFullPath: "entry/src/main/ets/pages/Index", integratedHsp: "false", moduleType: "followWithHap" });
