import sensor from "@ohos:sensor";
import geoLocationManager from "@ohos:geoLocationManager";
export interface Snapshot {
    latitude?: number;
    longitude?: number;
    altitude?: number;
    accuracy?: number;
    pressureHpa?: number;
    magneticX?: number;
    magneticY?: number;
    magneticZ?: number;
}
const SETTLE_MS = 800;
/**
 * 一次性采集所有可用传感器快照：
 *  - 定位（经纬度、海拔、精度）—— Location Kit 单次定位
 *  - 气压计（hPa）
 *  - 磁力计（三分量，µT）
 *
 * 流程：请求一次高精度定位，拿到定位后再等 SETTLE_MS 让传感器读数稳定，
 * 最后统一返回快照；超过 timeoutMs 则返回已拿到的部分数据（室内 GPS 经常超时属正常）。
 * 对应 Android 版 SensorSnapshotter.capture()。
 */
export function captureSnapshot(timeoutMs: number = 6000): Promise<Snapshot> {
    return new Promise<Snapshot>((resolve: (s: Snapshot) => void) => {
        let pressureHpa: number | undefined = undefined;
        let magneticX: number | undefined = undefined;
        let magneticY: number | undefined = undefined;
        let magneticZ: number | undefined = undefined;
        let loc: geoLocationManager.Location | undefined = undefined;
        let finished = false;
        let timer: number = -1;
        const pressureCb = (data: sensor.BarometerResponse): void => {
            pressureHpa = data.pressure;
        };
        const magneticCb = (data: sensor.MagneticFieldResponse): void => {
            magneticX = data.x;
            magneticY = data.y;
            magneticZ = data.z;
        };
        const cleanup = (): void => {
            if (timer >= 0) {
                clearTimeout(timer);
            }
            try {
                sensor.off(sensor.SensorId.BAROMETER, pressureCb);
            }
            catch (e) {
            }
            try {
                sensor.off(sensor.SensorId.MAGNETIC_FIELD, magneticCb);
            }
            catch (e) {
            }
        };
        const finish = (): void => {
            if (finished) {
                return;
            }
            finished = true;
            cleanup();
            resolve({
                latitude: loc ? loc.latitude : undefined,
                longitude: loc ? loc.longitude : undefined,
                altitude: loc ? loc.altitude : undefined,
                accuracy: loc ? loc.accuracy : undefined,
                pressureHpa: pressureHpa,
                magneticX: magneticX,
                magneticY: magneticY,
                magneticZ: magneticZ
            });
        };
        try {
            sensor.on(sensor.SensorId.BAROMETER, pressureCb);
        }
        catch (e) {
        }
        try {
            sensor.on(sensor.SensorId.MAGNETIC_FIELD, magneticCb);
        }
        catch (e) {
        }
        const request: geoLocationManager.SingleLocationRequest = {
            locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_ACCURACY,
            locatingTimeoutMs: timeoutMs
        };
        geoLocationManager.getCurrentLocation(request).then((l: geoLocationManager.Location) => {
            loc = l;
            timer = setTimeout(finish, SETTLE_MS);
        }).catch(() => {
            timer = setTimeout(finish, SETTLE_MS);
        });
        timer = setTimeout(finish, timeoutMs);
    });
}
