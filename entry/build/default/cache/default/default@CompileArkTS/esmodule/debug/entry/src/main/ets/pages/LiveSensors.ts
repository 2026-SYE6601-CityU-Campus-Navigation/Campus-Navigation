if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface LiveSensorsPage_Params {
    onBack?: () => void;
    loc?: LocView | null;
    pressure?: PressureView | null;
    mag?: MagView | null;
    wifi?: WifiView[];
    lastScanMs?: number;
    hasPressure?: boolean;
    hasMagnetic?: boolean;
    sensorList?: SensorInfoView[];
    tickMs?: number;
    pressureMs?: number;
    magMs?: number;
    accel?: Vec3View | null;
    linear?: Vec3View | null;
    gravity?: Vec3View | null;
    gyro?: Vec3View | null;
    rotvec?: QuatView | null;
    orient?: OrientView | null;
    light?: number;
    proximity?: number;
    humidity?: number;
    ambTemp?: number;
    hall?: number;
    pedometer?: number;
    hasAccel?: boolean;
    hasLinear?: boolean;
    hasGravity?: boolean;
    hasGyro?: boolean;
    hasRotVec?: boolean;
    hasOrient?: boolean;
    hasLight?: boolean;
    hasProximity?: boolean;
    hasHumidity?: boolean;
    hasAmbTemp?: boolean;
    hasHall?: boolean;
    hasPedometer?: boolean;
    pressureAnchor?: number;
    heartbeat?: number;
    hbTimer?: number;
    liveListener?: LiveListener;
}
import { LiveStream } from "@bundle:com.example.roommarker/entry/ets/sensors/LiveStream";
import type { LocView, MagView, PressureView, WifiView, SensorInfoView, LiveListener, Vec3View, QuatView, OrientView } from "@bundle:com.example.roommarker/entry/ets/sensors/LiveStream";
import { fmtTime } from "@bundle:com.example.roommarker/entry/ets/common/Utils";
export class LiveSensorsPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.onBack = () => {
        };
        this.__loc = this.createStorageLink('rm_live_location', null, "loc");
        this.__pressure = this.createStorageLink('rm_live_pressure', null, "pressure");
        this.__mag = this.createStorageLink('rm_live_magnetic', null, "mag");
        this.__wifi = this.createStorageLink('rm_live_wifi', [], "wifi");
        this.__lastScanMs = this.createStorageLink('rm_live_wifi_scan_ms', 0, "lastScanMs");
        this.__hasPressure = this.createStorageLink('rm_live_has_pressure', false, "hasPressure");
        this.__hasMagnetic = this.createStorageLink('rm_live_has_magnetic', false, "hasMagnetic");
        this.__sensorList = this.createStorageLink('rm_sensor_list', [], "sensorList");
        this.__tickMs = this.createStorageLink('rm_live_tick_ms', 0, "tickMs");
        this.__pressureMs = this.createStorageLink('rm_live_pressure_ms', 0, "pressureMs");
        this.__magMs = this.createStorageLink('rm_live_mag_ms', 0, "magMs");
        this.__accel = this.createStorageLink('rm_live_accel', null, "accel");
        this.__linear = this.createStorageLink('rm_live_linear', null, "linear");
        this.__gravity = this.createStorageLink('rm_live_gravity', null, "gravity");
        this.__gyro = this.createStorageLink('rm_live_gyro', null, "gyro");
        this.__rotvec = this.createStorageLink('rm_live_rotvec', null, "rotvec");
        this.__orient = this.createStorageLink('rm_live_orient', null, "orient");
        this.__light = this.createStorageLink('rm_live_light', -1, "light");
        this.__proximity = this.createStorageLink('rm_live_proximity', -1, "proximity");
        this.__humidity = this.createStorageLink('rm_live_humidity', -1, "humidity");
        this.__ambTemp = this.createStorageLink('rm_live_ambtemp', -999, "ambTemp");
        this.__hall = this.createStorageLink('rm_live_hall', -1, "hall");
        this.__pedometer = this.createStorageLink('rm_live_pedometer', -1, "pedometer");
        this.__hasAccel = this.createStorageLink('rm_live_has_accel', false, "hasAccel");
        this.__hasLinear = this.createStorageLink('rm_live_has_linear', false, "hasLinear");
        this.__hasGravity = this.createStorageLink('rm_live_has_gravity', false, "hasGravity");
        this.__hasGyro = this.createStorageLink('rm_live_has_gyro', false, "hasGyro");
        this.__hasRotVec = this.createStorageLink('rm_live_has_rotvec', false, "hasRotVec");
        this.__hasOrient = this.createStorageLink('rm_live_has_orient', false, "hasOrient");
        this.__hasLight = this.createStorageLink('rm_live_has_light', false, "hasLight");
        this.__hasProximity = this.createStorageLink('rm_live_has_proximity', false, "hasProximity");
        this.__hasHumidity = this.createStorageLink('rm_live_has_humidity', false, "hasHumidity");
        this.__hasAmbTemp = this.createStorageLink('rm_live_has_ambtemp', false, "hasAmbTemp");
        this.__hasHall = this.createStorageLink('rm_live_has_hall', false, "hasHall");
        this.__hasPedometer = this.createStorageLink('rm_live_has_pedometer', false, "hasPedometer");
        this.__pressureAnchor = new ObservedPropertySimplePU(-1, this, "pressureAnchor");
        this.__heartbeat = new ObservedPropertySimplePU(0, this, "heartbeat");
        this.hbTimer = -1;
        this.liveListener = {
            onLoc: (v: LocView): void => {
                this.loc = v;
            },
            onPressure: (v: PressureView): void => {
                if (this.pressureAnchor < 0) {
                    this.pressureAnchor = v.hpa;
                }
                this.pressure = v;
                this.pressureMs = Date.now();
            },
            onMag: (v: MagView): void => {
                this.mag = v;
                this.magMs = Date.now();
            },
            onWifi: (list: WifiView[]): void => {
                this.wifi = list;
                this.lastScanMs = Date.now();
            },
            onFlags: (hp: boolean, hm: boolean): void => {
                this.hasPressure = hp;
                this.hasMagnetic = hm;
            },
            onSensorList: (list: SensorInfoView[]): void => {
                this.sensorList = list;
            },
            onTick: (ms: number): void => {
                this.tickMs = ms;
            }
        };
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: LiveSensorsPage_Params) {
        if (params.onBack !== undefined) {
            this.onBack = params.onBack;
        }
        if (params.pressureAnchor !== undefined) {
            this.pressureAnchor = params.pressureAnchor;
        }
        if (params.heartbeat !== undefined) {
            this.heartbeat = params.heartbeat;
        }
        if (params.hbTimer !== undefined) {
            this.hbTimer = params.hbTimer;
        }
        if (params.liveListener !== undefined) {
            this.liveListener = params.liveListener;
        }
    }
    updateStateVars(params: LiveSensorsPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__loc.purgeDependencyOnElmtId(rmElmtId);
        this.__pressure.purgeDependencyOnElmtId(rmElmtId);
        this.__mag.purgeDependencyOnElmtId(rmElmtId);
        this.__wifi.purgeDependencyOnElmtId(rmElmtId);
        this.__lastScanMs.purgeDependencyOnElmtId(rmElmtId);
        this.__hasPressure.purgeDependencyOnElmtId(rmElmtId);
        this.__hasMagnetic.purgeDependencyOnElmtId(rmElmtId);
        this.__sensorList.purgeDependencyOnElmtId(rmElmtId);
        this.__tickMs.purgeDependencyOnElmtId(rmElmtId);
        this.__pressureMs.purgeDependencyOnElmtId(rmElmtId);
        this.__magMs.purgeDependencyOnElmtId(rmElmtId);
        this.__accel.purgeDependencyOnElmtId(rmElmtId);
        this.__linear.purgeDependencyOnElmtId(rmElmtId);
        this.__gravity.purgeDependencyOnElmtId(rmElmtId);
        this.__gyro.purgeDependencyOnElmtId(rmElmtId);
        this.__rotvec.purgeDependencyOnElmtId(rmElmtId);
        this.__orient.purgeDependencyOnElmtId(rmElmtId);
        this.__light.purgeDependencyOnElmtId(rmElmtId);
        this.__proximity.purgeDependencyOnElmtId(rmElmtId);
        this.__humidity.purgeDependencyOnElmtId(rmElmtId);
        this.__ambTemp.purgeDependencyOnElmtId(rmElmtId);
        this.__hall.purgeDependencyOnElmtId(rmElmtId);
        this.__pedometer.purgeDependencyOnElmtId(rmElmtId);
        this.__hasAccel.purgeDependencyOnElmtId(rmElmtId);
        this.__hasLinear.purgeDependencyOnElmtId(rmElmtId);
        this.__hasGravity.purgeDependencyOnElmtId(rmElmtId);
        this.__hasGyro.purgeDependencyOnElmtId(rmElmtId);
        this.__hasRotVec.purgeDependencyOnElmtId(rmElmtId);
        this.__hasOrient.purgeDependencyOnElmtId(rmElmtId);
        this.__hasLight.purgeDependencyOnElmtId(rmElmtId);
        this.__hasProximity.purgeDependencyOnElmtId(rmElmtId);
        this.__hasHumidity.purgeDependencyOnElmtId(rmElmtId);
        this.__hasAmbTemp.purgeDependencyOnElmtId(rmElmtId);
        this.__hasHall.purgeDependencyOnElmtId(rmElmtId);
        this.__hasPedometer.purgeDependencyOnElmtId(rmElmtId);
        this.__pressureAnchor.purgeDependencyOnElmtId(rmElmtId);
        this.__heartbeat.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__loc.aboutToBeDeleted();
        this.__pressure.aboutToBeDeleted();
        this.__mag.aboutToBeDeleted();
        this.__wifi.aboutToBeDeleted();
        this.__lastScanMs.aboutToBeDeleted();
        this.__hasPressure.aboutToBeDeleted();
        this.__hasMagnetic.aboutToBeDeleted();
        this.__sensorList.aboutToBeDeleted();
        this.__tickMs.aboutToBeDeleted();
        this.__pressureMs.aboutToBeDeleted();
        this.__magMs.aboutToBeDeleted();
        this.__accel.aboutToBeDeleted();
        this.__linear.aboutToBeDeleted();
        this.__gravity.aboutToBeDeleted();
        this.__gyro.aboutToBeDeleted();
        this.__rotvec.aboutToBeDeleted();
        this.__orient.aboutToBeDeleted();
        this.__light.aboutToBeDeleted();
        this.__proximity.aboutToBeDeleted();
        this.__humidity.aboutToBeDeleted();
        this.__ambTemp.aboutToBeDeleted();
        this.__hall.aboutToBeDeleted();
        this.__pedometer.aboutToBeDeleted();
        this.__hasAccel.aboutToBeDeleted();
        this.__hasLinear.aboutToBeDeleted();
        this.__hasGravity.aboutToBeDeleted();
        this.__hasGyro.aboutToBeDeleted();
        this.__hasRotVec.aboutToBeDeleted();
        this.__hasOrient.aboutToBeDeleted();
        this.__hasLight.aboutToBeDeleted();
        this.__hasProximity.aboutToBeDeleted();
        this.__hasHumidity.aboutToBeDeleted();
        this.__hasAmbTemp.aboutToBeDeleted();
        this.__hasHall.aboutToBeDeleted();
        this.__hasPedometer.aboutToBeDeleted();
        this.__pressureAnchor.aboutToBeDeleted();
        this.__heartbeat.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private onBack: () => void;
    // 数据字段用 @StorageLink（与 WiFi 卡片同款路径）；显示刷新由 heartbeat 重建驱动
    private __loc: ObservedPropertyAbstractPU<LocView | null>;
    get loc() {
        return this.__loc.get();
    }
    set loc(newValue: LocView | null) {
        this.__loc.set(newValue);
    }
    private __pressure: ObservedPropertyAbstractPU<PressureView | null>;
    get pressure() {
        return this.__pressure.get();
    }
    set pressure(newValue: PressureView | null) {
        this.__pressure.set(newValue);
    }
    private __mag: ObservedPropertyAbstractPU<MagView | null>;
    get mag() {
        return this.__mag.get();
    }
    set mag(newValue: MagView | null) {
        this.__mag.set(newValue);
    }
    private __wifi: ObservedPropertyAbstractPU<WifiView[]>;
    get wifi() {
        return this.__wifi.get();
    }
    set wifi(newValue: WifiView[]) {
        this.__wifi.set(newValue);
    }
    private __lastScanMs: ObservedPropertyAbstractPU<number>;
    get lastScanMs() {
        return this.__lastScanMs.get();
    }
    set lastScanMs(newValue: number) {
        this.__lastScanMs.set(newValue);
    }
    private __hasPressure: ObservedPropertyAbstractPU<boolean>;
    get hasPressure() {
        return this.__hasPressure.get();
    }
    set hasPressure(newValue: boolean) {
        this.__hasPressure.set(newValue);
    }
    private __hasMagnetic: ObservedPropertyAbstractPU<boolean>;
    get hasMagnetic() {
        return this.__hasMagnetic.get();
    }
    set hasMagnetic(newValue: boolean) {
        this.__hasMagnetic.set(newValue);
    }
    private __sensorList: ObservedPropertyAbstractPU<SensorInfoView[]>;
    get sensorList() {
        return this.__sensorList.get();
    }
    set sensorList(newValue: SensorInfoView[]) {
        this.__sensorList.set(newValue);
    }
    private __tickMs: ObservedPropertyAbstractPU<number>;
    get tickMs() {
        return this.__tickMs.get();
    }
    set tickMs(newValue: number) {
        this.__tickMs.set(newValue);
    }
    private __pressureMs: ObservedPropertyAbstractPU<number>;
    get pressureMs() {
        return this.__pressureMs.get();
    }
    set pressureMs(newValue: number) {
        this.__pressureMs.set(newValue);
    }
    private __magMs: ObservedPropertyAbstractPU<number>;
    get magMs() {
        return this.__magMs.get();
    }
    set magMs(newValue: number) {
        this.__magMs.set(newValue);
    }
    private __accel: ObservedPropertyAbstractPU<Vec3View | null>;
    get accel() {
        return this.__accel.get();
    }
    set accel(newValue: Vec3View | null) {
        this.__accel.set(newValue);
    }
    private __linear: ObservedPropertyAbstractPU<Vec3View | null>;
    get linear() {
        return this.__linear.get();
    }
    set linear(newValue: Vec3View | null) {
        this.__linear.set(newValue);
    }
    private __gravity: ObservedPropertyAbstractPU<Vec3View | null>;
    get gravity() {
        return this.__gravity.get();
    }
    set gravity(newValue: Vec3View | null) {
        this.__gravity.set(newValue);
    }
    private __gyro: ObservedPropertyAbstractPU<Vec3View | null>;
    get gyro() {
        return this.__gyro.get();
    }
    set gyro(newValue: Vec3View | null) {
        this.__gyro.set(newValue);
    }
    private __rotvec: ObservedPropertyAbstractPU<QuatView | null>;
    get rotvec() {
        return this.__rotvec.get();
    }
    set rotvec(newValue: QuatView | null) {
        this.__rotvec.set(newValue);
    }
    private __orient: ObservedPropertyAbstractPU<OrientView | null>;
    get orient() {
        return this.__orient.get();
    }
    set orient(newValue: OrientView | null) {
        this.__orient.set(newValue);
    }
    private __light: ObservedPropertyAbstractPU<number>;
    get light() {
        return this.__light.get();
    }
    set light(newValue: number) {
        this.__light.set(newValue);
    }
    private __proximity: ObservedPropertyAbstractPU<number>;
    get proximity() {
        return this.__proximity.get();
    }
    set proximity(newValue: number) {
        this.__proximity.set(newValue);
    }
    private __humidity: ObservedPropertyAbstractPU<number>;
    get humidity() {
        return this.__humidity.get();
    }
    set humidity(newValue: number) {
        this.__humidity.set(newValue);
    }
    private __ambTemp: ObservedPropertyAbstractPU<number>;
    get ambTemp() {
        return this.__ambTemp.get();
    }
    set ambTemp(newValue: number) {
        this.__ambTemp.set(newValue);
    }
    private __hall: ObservedPropertyAbstractPU<number>;
    get hall() {
        return this.__hall.get();
    }
    set hall(newValue: number) {
        this.__hall.set(newValue);
    }
    private __pedometer: ObservedPropertyAbstractPU<number>;
    get pedometer() {
        return this.__pedometer.get();
    }
    set pedometer(newValue: number) {
        this.__pedometer.set(newValue);
    }
    private __hasAccel: ObservedPropertyAbstractPU<boolean>;
    get hasAccel() {
        return this.__hasAccel.get();
    }
    set hasAccel(newValue: boolean) {
        this.__hasAccel.set(newValue);
    }
    private __hasLinear: ObservedPropertyAbstractPU<boolean>;
    get hasLinear() {
        return this.__hasLinear.get();
    }
    set hasLinear(newValue: boolean) {
        this.__hasLinear.set(newValue);
    }
    private __hasGravity: ObservedPropertyAbstractPU<boolean>;
    get hasGravity() {
        return this.__hasGravity.get();
    }
    set hasGravity(newValue: boolean) {
        this.__hasGravity.set(newValue);
    }
    private __hasGyro: ObservedPropertyAbstractPU<boolean>;
    get hasGyro() {
        return this.__hasGyro.get();
    }
    set hasGyro(newValue: boolean) {
        this.__hasGyro.set(newValue);
    }
    private __hasRotVec: ObservedPropertyAbstractPU<boolean>;
    get hasRotVec() {
        return this.__hasRotVec.get();
    }
    set hasRotVec(newValue: boolean) {
        this.__hasRotVec.set(newValue);
    }
    private __hasOrient: ObservedPropertyAbstractPU<boolean>;
    get hasOrient() {
        return this.__hasOrient.get();
    }
    set hasOrient(newValue: boolean) {
        this.__hasOrient.set(newValue);
    }
    private __hasLight: ObservedPropertyAbstractPU<boolean>;
    get hasLight() {
        return this.__hasLight.get();
    }
    set hasLight(newValue: boolean) {
        this.__hasLight.set(newValue);
    }
    private __hasProximity: ObservedPropertyAbstractPU<boolean>;
    get hasProximity() {
        return this.__hasProximity.get();
    }
    set hasProximity(newValue: boolean) {
        this.__hasProximity.set(newValue);
    }
    private __hasHumidity: ObservedPropertyAbstractPU<boolean>;
    get hasHumidity() {
        return this.__hasHumidity.get();
    }
    set hasHumidity(newValue: boolean) {
        this.__hasHumidity.set(newValue);
    }
    private __hasAmbTemp: ObservedPropertyAbstractPU<boolean>;
    get hasAmbTemp() {
        return this.__hasAmbTemp.get();
    }
    set hasAmbTemp(newValue: boolean) {
        this.__hasAmbTemp.set(newValue);
    }
    private __hasHall: ObservedPropertyAbstractPU<boolean>;
    get hasHall() {
        return this.__hasHall.get();
    }
    set hasHall(newValue: boolean) {
        this.__hasHall.set(newValue);
    }
    private __hasPedometer: ObservedPropertyAbstractPU<boolean>;
    get hasPedometer() {
        return this.__hasPedometer.get();
    }
    set hasPedometer(newValue: boolean) {
        this.__hasPedometer.set(newValue);
    }
    private __pressureAnchor: ObservedPropertySimplePU<number>;
    get pressureAnchor() {
        return this.__pressureAnchor.get();
    }
    set pressureAnchor(newValue: number) {
        this.__pressureAnchor.set(newValue);
    }
    /** 本地心跳：每 100ms 自增，驱动 ForEach 按 key 重建卡片树（等价于自动"重新进入页面"） */
    private __heartbeat: ObservedPropertySimplePU<number>;
    get heartbeat() {
        return this.__heartbeat.get();
    }
    set heartbeat(newValue: number) {
        this.__heartbeat.set(newValue);
    }
    private hbTimer: number;
    /** 传感器回调：仅用于气压锚点等本地逻辑（显示刷新由心跳重建驱动） */
    private liveListener: LiveListener;
    aboutToAppear(): void {
        LiveStream.get().setListener(this.liveListener);
        LiveStream.get().start();
        if (this.hbTimer >= 0) {
            clearInterval(this.hbTimer);
        }
        this.hbTimer = setInterval(() => {
            this.heartbeat++;
        }, 100);
    }
    aboutToDisappear(): void {
        if (this.hbTimer >= 0) {
            clearInterval(this.hbTimer);
            this.hbTimer = -1;
        }
        LiveStream.get().stop();
        LiveStream.get().setListener(null);
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
            Text.create('实时传感器');
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
            Text.create(this.tickMs > 0 ? `更新 ${fmtTime(this.tickMs)}` : '等待数据');
            Text.fontSize(12);
            Text.fontColor('#99000000');
        }, Text);
        Text.pop();
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
            Column.create();
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // 以 heartbeat 为 key：每 0.5s 键变化 → 整个卡片列销毁重建 →
            // @StorageLink 重新初始化读取 AppStorage 最新值（等价于自动"重新进入页面"）
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const h = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Column.create({ space: 12 });
                    Column.padding(16);
                    Column.width('100%');
                }, Column);
                this.LocationCard.bind(this)();
                this.PressureCard.bind(this)();
                this.MagneticCard.bind(this)();
                this.MotionCard.bind(this)();
                this.EnvCard.bind(this)();
                this.WifiCard.bind(this)();
                this.SensorListCard.bind(this)();
                Column.pop();
            };
            this.forEachUpdateFunction(elmtId, [this.heartbeat], forEachItemGenFunction, (h: number) => `${h}`, false, false);
        }, ForEach);
        // 以 heartbeat 为 key：每 0.5s 键变化 → 整个卡片列销毁重建 →
        // @StorageLink 重新初始化读取 AppStorage 最新值（等价于自动"重新进入页面"）
        ForEach.pop();
        Column.pop();
        Scroll.pop();
        Column.pop();
    }
    LocationCard(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 8 });
            Column.width('100%');
            Column.padding(16);
            Column.backgroundColor('#FFF7F7F7');
            Column.borderRadius(12);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('定位 / GPS');
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Medium);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.LocationBody.bind(this)();
        Column.pop();
    }
    PressureCard(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 8 });
            Column.width('100%');
            Column.padding(16);
            Column.backgroundColor('#FFF7F7F7');
            Column.borderRadius(12);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('气压计');
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Medium);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.PressureBody.bind(this)();
        Column.pop();
    }
    MagneticCard(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 8 });
            Column.width('100%');
            Column.padding(16);
            Column.backgroundColor('#FFF7F7F7');
            Column.borderRadius(12);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('地磁 / 磁力计');
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Medium);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.MagneticBody.bind(this)();
        Column.pop();
    }
    MotionCard(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 8 });
            Column.width('100%');
            Column.padding(16);
            Column.backgroundColor('#FFF7F7F7');
            Column.borderRadius(12);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('运动传感器');
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Medium);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.Vec3Row.bind(this)('加速度计', this.hasAccel, ObservedObject.GetRawObject(this.accel), 'm/s²');
        this.Vec3Row.bind(this)('线性加速度', this.hasLinear, ObservedObject.GetRawObject(this.linear), 'm/s²');
        this.Vec3Row.bind(this)('重力', this.hasGravity, ObservedObject.GetRawObject(this.gravity), 'm/s²');
        this.Vec3Row.bind(this)('陀螺仪', this.hasGyro, ObservedObject.GetRawObject(this.gyro), 'rad/s');
        this.QuatRow.bind(this)('旋转矢量', this.hasRotVec, ObservedObject.GetRawObject(this.rotvec));
        this.OrientRow.bind(this)('方向', this.hasOrient, ObservedObject.GetRawObject(this.orient));
        Column.pop();
    }
    EnvCard(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 8 });
            Column.width('100%');
            Column.padding(16);
            Column.backgroundColor('#FFF7F7F7');
            Column.borderRadius(12);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('环境与状态传感器');
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Medium);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.ScalarRow.bind(this)('环境光', this.hasLight, this.light, `${this.light.toFixed(0)} lux`);
        this.ScalarRow.bind(this)('接近', this.hasProximity, this.proximity, `${this.proximity.toFixed(1)} cm`);
        this.ScalarRow.bind(this)('湿度', this.hasHumidity, this.humidity, `${this.humidity.toFixed(1)} %`);
        this.ScalarRow.bind(this)('环境温度', this.hasAmbTemp, this.ambTemp, this.ambTemp > -900 ? `${this.ambTemp.toFixed(1)} °C` : '');
        this.ScalarRow.bind(this)('霍尔', this.hasHall, this.hall, `状态 ${this.hall}`);
        this.ScalarRow.bind(this)('计步器', this.hasPedometer, this.pedometer, `${this.pedometer} 步`);
        Column.pop();
    }
    WifiCard(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 8 });
            Column.width('100%');
            Column.padding(16);
            Column.backgroundColor('#FFF7F7F7');
            Column.borderRadius(12);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`WiFi 指纹（${this.wifi.length} 个 AP）`);
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Medium);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.WifiBody.bind(this)();
        Column.pop();
    }
    SensorListCard(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 8 });
            Column.width('100%');
            Column.padding(16);
            Column.backgroundColor('#FFF7F7F7');
            Column.borderRadius(12);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`设备传感器清单（${this.sensorList.length} 个）`);
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Medium);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.sensorList.length === 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('无法读取传感器列表');
                        Text.fontSize(14);
                        Text.fontColor('#99000000');
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const s = _item;
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Row.create();
                                Row.width('100%');
                                Row.padding({ top: 6, bottom: 6 });
                            }, Row);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 2 });
                                Column.layoutWeight(1);
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(s.label);
                                Text.fontSize(14);
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(`${s.name} · ${s.vendor}`);
                                Text.fontSize(11);
                                Text.fontColor('#99000000');
                                Text.maxLines(1);
                                Text.textOverflow({ overflow: TextOverflow.Ellipsis });
                            }, Text);
                            Text.pop();
                            Column.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(`id ${s.id}`);
                                Text.fontSize(11);
                                Text.fontColor('#99000000');
                            }, Text);
                            Text.pop();
                            Row.pop();
                        };
                        this.forEachUpdateFunction(elmtId, this.sensorList, forEachItemGenFunction, (s: SensorInfoView) => s.id + '', false, false);
                    }, ForEach);
                    ForEach.pop();
                });
            }
        }, If);
        If.pop();
        Column.pop();
    }
    Vec3Row(label: string, has: boolean, v: Vec3View | null, unit: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
            Row.padding({ top: 4, bottom: 4 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(label);
            Text.fontSize(13);
            Text.fontColor('#99000000');
            Text.width(88);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (!has) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('此设备无该传感器');
                        Text.fontSize(13);
                        Text.fontColor('#99000000');
                    }, Text);
                    Text.pop();
                });
            }
            else if (v === null) {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('等待读数…');
                        Text.fontSize(13);
                        Text.fontColor('#99000000');
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(2, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(`X ${v.x.toFixed(2)} · Y ${v.y.toFixed(2)} · Z ${v.z.toFixed(2)} · 模 ${v.m.toFixed(2)} ${unit}`);
                        Text.fontSize(12);
                    }, Text);
                    Text.pop();
                });
            }
        }, If);
        If.pop();
        Row.pop();
    }
    QuatRow(label: string, has: boolean, v: QuatView | null, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
            Row.padding({ top: 4, bottom: 4 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(label);
            Text.fontSize(13);
            Text.fontColor('#99000000');
            Text.width(88);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (!has) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('此设备无该传感器');
                        Text.fontSize(13);
                        Text.fontColor('#99000000');
                    }, Text);
                    Text.pop();
                });
            }
            else if (v === null) {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('等待读数…');
                        Text.fontSize(13);
                        Text.fontColor('#99000000');
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(2, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(`X ${v.x.toFixed(3)} · Y ${v.y.toFixed(3)} · Z ${v.z.toFixed(3)} · W ${v.w.toFixed(3)}`);
                        Text.fontSize(12);
                    }, Text);
                    Text.pop();
                });
            }
        }, If);
        If.pop();
        Row.pop();
    }
    OrientRow(label: string, has: boolean, v: OrientView | null, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
            Row.padding({ top: 4, bottom: 4 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(label);
            Text.fontSize(13);
            Text.fontColor('#99000000');
            Text.width(88);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (!has) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('此设备无该传感器');
                        Text.fontSize(13);
                        Text.fontColor('#99000000');
                    }, Text);
                    Text.pop();
                });
            }
            else if (v === null) {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('等待读数…');
                        Text.fontSize(13);
                        Text.fontColor('#99000000');
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(2, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(`α ${v.alpha.toFixed(0)}° · β ${v.beta.toFixed(0)}° · γ ${v.gamma.toFixed(0)}°`);
                        Text.fontSize(12);
                    }, Text);
                    Text.pop();
                });
            }
        }, If);
        If.pop();
        Row.pop();
    }
    ScalarRow(label: string, has: boolean, v: number, text: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
            Row.padding({ top: 4, bottom: 4 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(label);
            Text.fontSize(13);
            Text.fontColor('#99000000');
            Text.width(88);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (!has) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('此设备无该传感器');
                        Text.fontSize(13);
                        Text.fontColor('#99000000');
                    }, Text);
                    Text.pop();
                });
            }
            else if (v < 0 || text.length === 0) {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('等待读数…');
                        Text.fontSize(13);
                        Text.fontColor('#99000000');
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(2, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(text);
                        Text.fontSize(12);
                    }, Text);
                    Text.pop();
                });
            }
        }, If);
        If.pop();
        Row.pop();
    }
    LocationBody(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.loc === null) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('等待定位中…（室内可能长时间无定位信号）');
                        Text.fontSize(14);
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.InfoRow.bind(this)('纬度', this.loc.lat.toFixed(6));
                    this.InfoRow.bind(this)('经度', this.loc.lng.toFixed(6));
                    this.InfoRow.bind(this)('海拔', `${this.loc.alt.toFixed(1)} m`);
                    this.InfoRow.bind(this)('精度', this.loc.acc !== undefined ? `±${this.loc.acc.toFixed(1)} m` : '未知');
                    this.InfoRow.bind(this)('速度', this.loc.spd !== undefined ? `${this.loc.spd.toFixed(2)} m/s` : '未知');
                    this.InfoRow.bind(this)('方位', this.loc.brg !== undefined ? `${((this.loc.brg + 360) % 360).toFixed(0)}°` : '未知');
                    this.InfoRow.bind(this)('更新', fmtTime(this.loc.timeMs));
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        If.create();
                        if (this.tickMs > 0) {
                            this.ifElseBranchUpdateFunction(0, () => {
                                this.InfoRow.bind(this)('距上次定位', this.locAgoText());
                            });
                        }
                        else {
                            this.ifElseBranchUpdateFunction(1, () => {
                            });
                        }
                    }, If);
                    If.pop();
                });
            }
        }, If);
        If.pop();
    }
    PressureBody(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (!this.hasPressure) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('此设备无气压计传感器');
                        Text.fontSize(14);
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                });
            }
            else if (this.pressure === null) {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('等待读数…');
                        Text.fontSize(14);
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(2, () => {
                    this.InfoRow.bind(this)('气压', `${this.pressure.hpa.toFixed(3)} hPa`);
                    this.InfoRow.bind(this)('相对变化', this.pressureAnchor >= 0
                        ? `${(this.pressure.hpa - this.pressureAnchor).toFixed(3)} hPa（进出页面时归零）` : '—');
                    this.InfoRow.bind(this)('推算海拔', `${this.pressure.alt.toFixed(1)} m（相对海平面，楼层判断约 3m/层）`);
                    this.InfoRow.bind(this)('更新', this.pressureMs > 0 ? fmtTime(this.pressureMs) : '—');
                });
            }
        }, If);
        If.pop();
    }
    MagneticBody(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (!this.hasMagnetic) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('此设备无磁力计传感器');
                        Text.fontSize(14);
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                });
            }
            else if (this.mag === null) {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('等待读数…');
                        Text.fontSize(14);
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(2, () => {
                    this.InfoRow.bind(this)('X / Y / Z', `${this.mag.x.toFixed(2)} / ${this.mag.y.toFixed(2)} / ${this.mag.z.toFixed(2)} µT`);
                    this.InfoRow.bind(this)('总场强', `${this.mag.mag.toFixed(2)} µT（地磁基准约 45-55）`);
                    this.InfoRow.bind(this)('方位角', this.mag.az !== undefined ? `${this.mag.az.toFixed(0)}°` : '不可用');
                    this.InfoRow.bind(this)('更新', this.magMs > 0 ? fmtTime(this.magMs) : '—');
                });
            }
        }, If);
        If.pop();
    }
    WifiBody(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.lastScanMs === 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('尚未完成扫描');
                        Text.fontSize(12);
                        Text.fontColor('#99000000');
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(`最近扫描：${fmtTime(this.lastScanMs)}`);
                        Text.fontSize(12);
                        Text.fontColor('#99000000');
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.wifi.length === 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('暂无 WiFi 扫描结果 —— 需授权位置权限并打开系统定位开关；扫描受系统节流（约 30 秒一次）');
                        Text.fontSize(12);
                        Text.fontColor('#99000000');
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const ap = _item;
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 2 });
                                Column.width('100%');
                                Column.padding({ top: 6, bottom: 6 });
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(`${ap.ssid.length > 0 ? ap.ssid : '(隐藏网络)'}  ${ap.bssid}`);
                                Text.fontSize(14);
                                Text.width('100%');
                                Text.maxLines(1);
                                Text.textOverflow({ overflow: TextOverflow.Ellipsis });
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(`${ap.rssi} dBm · ${ap.freq} MHz`);
                                Text.fontSize(12);
                                Text.fontColor('#99000000');
                                Text.width('100%');
                            }, Text);
                            Text.pop();
                            Column.pop();
                        };
                        this.forEachUpdateFunction(elmtId, this.wifi, forEachItemGenFunction, (ap: WifiView) => ap.bssid, false, false);
                    }, ForEach);
                    ForEach.pop();
                });
            }
        }, If);
        If.pop();
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
    /** 「距上次定位」文案：随 tick 实时变化，证明定位卡片在等 GPS 修正 */
    private locAgoText(): string {
        if (this.tickMs <= 0 || this.loc === null) {
            return '';
        }
        const ago = Math.max(0, Math.floor((this.tickMs - this.loc.timeMs) / 1000));
        return ago < 60 ? `${ago} 秒前` : `${Math.floor(ago / 60)} 分钟前（室内 GPS 信号弱属正常）`;
    }
    rerender() {
        this.updateDirtyElements();
    }
}
