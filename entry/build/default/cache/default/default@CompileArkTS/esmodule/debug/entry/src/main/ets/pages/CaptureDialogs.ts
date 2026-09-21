if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface PhotoNoteDialog_Params {
    controller?: CustomDialogController;
    absPath?: string;
    onSave?: (note: string) => void;
    onDiscard?: () => void;
    note?: string;
}
interface TrackTagDialog_Params {
    controller?: CustomDialogController;
    onSave?: (tagType: string, note: string) => void;
    note?: string;
    tagType?: string;
    tagIndex?: number;
}
import { TrackTagType, trackTagOptions } from "@bundle:com.example.roommarker/entry/ets/data/Entities";
export class TrackTagDialog extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.controller = undefined;
        this.onSave = undefined;
        this.__note = new ObservedPropertySimplePU('', this, "note");
        this.__tagType = new ObservedPropertySimplePU(TrackTagType.TOILET, this, "tagType");
        this.__tagIndex = new ObservedPropertySimplePU(0, this, "tagIndex");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: TrackTagDialog_Params) {
        if (params.controller !== undefined) {
            this.controller = params.controller;
        }
        if (params.onSave !== undefined) {
            this.onSave = params.onSave;
        }
        if (params.note !== undefined) {
            this.note = params.note;
        }
        if (params.tagType !== undefined) {
            this.tagType = params.tagType;
        }
        if (params.tagIndex !== undefined) {
            this.tagIndex = params.tagIndex;
        }
    }
    updateStateVars(params: TrackTagDialog_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__note.purgeDependencyOnElmtId(rmElmtId);
        this.__tagType.purgeDependencyOnElmtId(rmElmtId);
        this.__tagIndex.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__note.aboutToBeDeleted();
        this.__tagType.aboutToBeDeleted();
        this.__tagIndex.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private controller?: CustomDialogController;
    setController(ctr: CustomDialogController) {
        this.controller = ctr;
    }
    private onSave?: (tagType: string, note: string) => void;
    private __note: ObservedPropertySimplePU<string>;
    get note() {
        return this.__note.get();
    }
    set note(newValue: string) {
        this.__note.set(newValue);
    }
    private __tagType: ObservedPropertySimplePU<string>;
    get tagType() {
        return this.__tagType.get();
    }
    set tagType(newValue: string) {
        this.__tagType.set(newValue);
    }
    private __tagIndex: ObservedPropertySimplePU<number>;
    get tagIndex() {
        return this.__tagIndex.get();
    }
    set tagIndex(newValue: number) {
        this.__tagIndex.set(newValue);
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.padding(16);
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('打标签');
            Text.fontSize(18);
            Text.fontWeight(FontWeight.Medium);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('标记当前位置的关键信息，保存时自动关联 定位+朝向 快照');
            Text.fontSize(12);
            Text.fontColor('#99000000');
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Select.create(trackTagOptions());
            Select.selected(this.tagIndex);
            Select.onSelect((index: number, value: string) => {
                this.tagIndex = index;
                this.tagType = value;
            });
            Select.width('100%');
        }, Select);
        Select.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ placeholder: '备注（如：3楼男厕，门口右手边）' });
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
            Button.createWithLabel('保存标签');
            Button.onClick(() => {
                this.controller?.close();
                if (this.onSave) {
                    this.onSave(this.tagType, this.note.trim());
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
export class PhotoNoteDialog extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.controller = undefined;
        this.absPath = '';
        this.onSave = undefined;
        this.onDiscard = undefined;
        this.__note = new ObservedPropertySimplePU('', this, "note");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: PhotoNoteDialog_Params) {
        if (params.controller !== undefined) {
            this.controller = params.controller;
        }
        if (params.absPath !== undefined) {
            this.absPath = params.absPath;
        }
        if (params.onSave !== undefined) {
            this.onSave = params.onSave;
        }
        if (params.onDiscard !== undefined) {
            this.onDiscard = params.onDiscard;
        }
        if (params.note !== undefined) {
            this.note = params.note;
        }
    }
    updateStateVars(params: PhotoNoteDialog_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__note.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__note.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private controller?: CustomDialogController;
    setController(ctr: CustomDialogController) {
        this.controller = ctr;
    }
    private absPath: string;
    private onSave?: (note: string) => void;
    private onDiscard?: () => void;
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
            Text.create('照片已拍摄');
            Text.fontSize(18);
            Text.fontWeight(FontWeight.Medium);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Image.create('file://' + this.absPath);
            Image.width('100%');
            Image.height(220);
            Image.objectFit(ImageFit.Cover);
            Image.borderRadius(8);
        }, Image);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ placeholder: '备注（如：教室门口视角，前方是楼梯）' });
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
            Button.createWithLabel('丢弃');
            Button.fontColor('#E84026');
            Button.onClick(() => {
                this.controller?.close();
                if (this.onDiscard) {
                    this.onDiscard();
                }
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('保存并关联');
            Button.onClick(() => {
                this.controller?.close();
                if (this.onSave) {
                    this.onSave(this.note.trim());
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
