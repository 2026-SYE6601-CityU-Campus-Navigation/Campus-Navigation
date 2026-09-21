if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface RecordingBanner_Params {
    heartbeat?: number;
    timer?: number;
    tagDialog?: CustomDialogController | null;
    photoDialog?: CustomDialogController | null;
}
import promptAction from "@ohos:promptAction";
import { Store } from "@bundle:com.example.roommarker/entry/ets/data/Store";
import { TrackRecorder } from "@bundle:com.example.roommarker/entry/ets/sensors/TrackRecorder";
import { captureTrackPhoto, deletePhotoFile } from "@bundle:com.example.roommarker/entry/ets/sensors/TrackMedia";
import { fmtDuration } from "@bundle:com.example.roommarker/entry/ets/common/Utils";
import { PhotoNoteDialog, TrackTagDialog } from "@bundle:com.example.roommarker/entry/ets/pages/CaptureDialogs";
export class RecordingBanner extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__heartbeat = new ObservedPropertySimplePU(0, this, "heartbeat");
        this.timer = -1;
        this.tagDialog = null;
        this.photoDialog = null;
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: RecordingBanner_Params) {
        if (params.heartbeat !== undefined) {
            this.heartbeat = params.heartbeat;
        }
        if (params.timer !== undefined) {
            this.timer = params.timer;
        }
        if (params.tagDialog !== undefined) {
            this.tagDialog = params.tagDialog;
        }
        if (params.photoDialog !== undefined) {
            this.photoDialog = params.photoDialog;
        }
    }
    updateStateVars(params: RecordingBanner_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__heartbeat.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__heartbeat.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __heartbeat: ObservedPropertySimplePU<number>;
    get heartbeat() {
        return this.__heartbeat.get();
    }
    set heartbeat(newValue: number) {
        this.__heartbeat.set(newValue);
    }
    private timer: number;
    private tagDialog: CustomDialogController | null;
    private photoDialog: CustomDialogController | null;
    aboutToAppear(): void {
        this.timer = setInterval(() => {
            this.heartbeat++;
        }, 500);
    }
    aboutToDisappear(): void {
        if (this.timer >= 0) {
            clearInterval(this.timer);
            this.timer = -1;
        }
    }
    private openTagDialog(): void {
        const rec = TrackRecorder.get();
        if (!rec.isRunning()) {
            promptAction.showToast({ message: '当前没有进行中的轨迹' });
            return;
        }
        this.tagDialog = new CustomDialogController({
            builder: () => {
                let jsDialog = new TrackTagDialog(this, {
                    onSave: (tagType: string, note: string): void => {
                        const snap = rec.getSnapshot();
                        Store.insertTrackTag(rec.getTrackId(), Date.now(), tagType, note, snap.latitude, snap.longitude, snap.altitude, snap.headingDeg)
                            .then(() => {
                            promptAction.showToast({ message: `已记录「${tagType}」标签` });
                        })
                            .catch(() => {
                            promptAction.showToast({ message: '标签保存失败' });
                        });
                    }
                }, undefined, -1, () => { }, { page: "entry/src/main/ets/pages/RecordingBanner.ets", line: 41, col: 16 });
                jsDialog.setController(this.tagDialog);
                ViewPU.create(jsDialog);
                let paramsLambda = () => {
                    return {
                        onSave: (tagType: string, note: string): void => {
                            const snap = rec.getSnapshot();
                            Store.insertTrackTag(rec.getTrackId(), Date.now(), tagType, note, snap.latitude, snap.longitude, snap.altitude, snap.headingDeg)
                                .then(() => {
                                promptAction.showToast({ message: `已记录「${tagType}」标签` });
                            })
                                .catch(() => {
                                promptAction.showToast({ message: '标签保存失败' });
                            });
                        }
                    };
                };
                jsDialog.paramsGenerator_ = paramsLambda;
            },
            customStyle: false
        }, this);
        this.tagDialog.open();
    }
    private takePhoto(): void {
        const rec = TrackRecorder.get();
        if (!rec.isRunning()) {
            promptAction.showToast({ message: '当前没有进行中的轨迹' });
            return;
        }
        const trackId = rec.getTrackId();
        captureTrackPhoto(trackId).then((cap) => {
            // 拍照期间用户可能已停止记录，此时丢弃照片避免孤儿数据
            if (!rec.isRunning() || rec.getTrackId() !== trackId) {
                deletePhotoFile(cap.absPath);
                promptAction.showToast({ message: '轨迹已停止，照片已丢弃' });
                return;
            }
            this.photoDialog = new CustomDialogController({
                builder: () => {
                    let jsDialog = new PhotoNoteDialog(this, {
                        absPath: cap.absPath,
                        onSave: (note: string): void => {
                            const snap = rec.getSnapshot();
                            Store.insertTrackPhoto(trackId, cap.timeMs, cap.relPath, note, snap.latitude, snap.longitude, snap.altitude, snap.headingDeg)
                                .then(() => {
                                promptAction.showToast({ message: '照片已关联到轨迹' });
                            })
                                .catch(() => {
                                promptAction.showToast({ message: '照片保存失败' });
                            });
                        },
                        onDiscard: (): void => {
                            deletePhotoFile(cap.absPath);
                            promptAction.showToast({ message: '照片已丢弃' });
                        }
                    }, undefined, -1, () => { }, { page: "entry/src/main/ets/pages/RecordingBanner.ets", line: 74, col: 18 });
                    jsDialog.setController(this.photoDialog);
                    ViewPU.create(jsDialog);
                    let paramsLambda = () => {
                        return {
                            absPath: cap.absPath,
                            onSave: (note: string): void => {
                                const snap = rec.getSnapshot();
                                Store.insertTrackPhoto(trackId, cap.timeMs, cap.relPath, note, snap.latitude, snap.longitude, snap.altitude, snap.headingDeg)
                                    .then(() => {
                                    promptAction.showToast({ message: '照片已关联到轨迹' });
                                })
                                    .catch(() => {
                                    promptAction.showToast({ message: '照片保存失败' });
                                });
                            },
                            onDiscard: (): void => {
                                deletePhotoFile(cap.absPath);
                                promptAction.showToast({ message: '照片已丢弃' });
                            }
                        };
                    };
                    jsDialog.paramsGenerator_ = paramsLambda;
                },
                customStyle: false
            }, this);
            this.photoDialog.open();
        }).catch(() => {
            promptAction.showToast({ message: '拍照未完成' });
        });
    }
    private stopRecording(): void {
        TrackRecorder.get().stop().then(() => {
            promptAction.showToast({ message: '轨迹已保存' });
        }).catch(() => {
        });
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (AppStorage.get<boolean>('rm_recording')) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const h = _item;
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 8 });
                                Column.width('100%');
                                Column.padding(12);
                                Column.backgroundColor('#330A59F7');
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(`● 正在记录「${AppStorage.get<string>('rm_rec_track_name')}」  ${fmtDuration(AppStorage.get<number>('rm_elapsed') as number)}（切页面不中断）`);
                                Text.fontSize(14);
                                Text.width('100%');
                                Text.maxLines(1);
                                Text.textOverflow({ overflow: TextOverflow.Ellipsis });
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Row.create({ space: 10 });
                                Row.width('100%');
                            }, Row);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Button.createWithLabel('拍照');
                                Button.fontSize(13);
                                Button.layoutWeight(1);
                                Button.onClick(() => {
                                    this.takePhoto();
                                });
                            }, Button);
                            Button.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Button.createWithLabel('打标签');
                                Button.fontSize(13);
                                Button.layoutWeight(1);
                                Button.onClick(() => {
                                    this.openTagDialog();
                                });
                            }, Button);
                            Button.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Button.createWithLabel('■ 停止');
                                Button.fontSize(13);
                                Button.layoutWeight(1);
                                Button.fontColor(Color.White);
                                Button.backgroundColor('#E84026');
                                Button.onClick(() => {
                                    this.stopRecording();
                                });
                            }, Button);
                            Button.pop();
                            Row.pop();
                            Column.pop();
                        };
                        this.forEachUpdateFunction(elmtId, [this.heartbeat], forEachItemGenFunction, (h: number) => h + '', false, false);
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
    }
    rerender() {
        this.updateDirtyElements();
    }
}
