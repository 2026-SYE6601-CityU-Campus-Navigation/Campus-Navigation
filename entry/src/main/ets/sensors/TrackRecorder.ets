import { sensor } from '@kit.SensorServiceKit';
import { geoLocationManager } from '@kit.LocationKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { notificationManager } from '@kit.NotificationKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent } from '@kit.AbilityKit';
import { Store } from '../data/Store';
import { TrackPointDraft } from '../data/Entities';
import { Ctx, fusedAzimuth } from '../common/Utils';

const NOTIF_ID = 1001;

/** 记录中的当前传感器快照（供拍照/标签关联） */
export interface RecSnapshot {
  latitude?: number;
  longitude?: number;
  altitude?: number;
  headingDeg?: number;
  pressureHpa?: number;
}

/**
 * 轨迹记录器（≈ Android 版 TrackRecorder + RecordingService）：
 * 每秒采样一次 定位+气压+地磁+WiFi 摘要，每 5 秒批量落库；
 * 用 LOCATION 型长时任务 + 常驻通知保持后台记录。单例，页面间共享。
 */
export class TrackRecorder {
  private static inst: TrackRecorder | null = null;
  static get(): TrackRecorder {
    if (!TrackRecorder.inst) {
      TrackRecorder.inst = new TrackRecorder();
    }
    return TrackRecorder.inst;
  }

  private running = false;
  private trackId = -1;
  private t0 = 0;
  private pointCount = 0;
  private buffer: TrackPointDraft[] = [];
  private sampleTimer = -1;
  private elapsedTimer = -1;
  private wifiTimer = -1;

  private lastLoc: geoLocationManager.Location | null = null;
  private lastPressure: number | undefined = undefined;
  private lastMag: number[] = [0, 0, 0];
  private hasMag = false;
  private lastAccel: number[] = [0, 0, 0];
  private hasAccel = false;
  private lastHeading: number | undefined = undefined;
  private lastWifi = '';
  private lastWifiCount = 0;

  private pressureCb = (d: sensor.BarometerResponse): void => {
    this.lastPressure = d.pressure;
  };
  private magCb = (d: sensor.MagneticFieldResponse): void => {
    this.lastMag = [d.x, d.y, d.z];
    this.hasMag = true;
  };
  private accelCb = (d: sensor.AccelerometerResponse): void => {
    this.lastAccel = [d.x, d.y, d.z];
    this.hasAccel = true;
  };
  private locCb = (loc: geoLocationManager.Location): void => {
    this.lastLoc = loc;
  };

  isRunning(): boolean {
    return this.running;
  }

  /** 当前轨迹 id；未在记录时返回 -1 */
  getTrackId(): number {
    return this.trackId;
  }

  /** 当前传感器快照（供轨迹途中拍照/打标签时关联定位与朝向） */
  getSnapshot(): RecSnapshot {
    const loc = this.lastLoc;
    const snap: RecSnapshot = {
      latitude: loc ? loc.latitude : undefined,
      longitude: loc ? loc.longitude : undefined,
      altitude: loc ? loc.altitude : undefined,
      headingDeg: this.lastHeading,
      pressureHpa: this.lastPressure
    };
    return snap;
  }

  async start(name: string, areaId: number): Promise<void> {
    if (this.running) {
      return;
    }
    this.trackId = await Store.insertTrack(name, areaId);
    this.t0 = Date.now();
    this.pointCount = 0;
    this.buffer = [];
    this.running = true;

    AppStorage.setOrCreate('rm_recording', true);
    AppStorage.setOrCreate('rm_rec_track_name', name);
    AppStorage.setOrCreate('rm_elapsed', 0);

    try {
      sensor.on(sensor.SensorId.BAROMETER, this.pressureCb);
    } catch (e) {
    }
    try {
      sensor.on(sensor.SensorId.MAGNETIC_FIELD, this.magCb);
    } catch (e) {
    }
    try {
      sensor.on(sensor.SensorId.ACCELEROMETER, this.accelCb);
    } catch (e) {
    }
    const req: geoLocationManager.ContinuousLocationRequest = {
      interval: 1,
      locationScenario: geoLocationManager.UserActivityScenario.NAVIGATION
    };
    try {
      geoLocationManager.on('locationChange', req, this.locCb);
    } catch (e) {
    }

    this.refreshWifi();
    this.wifiTimer = setInterval(() => {
      this.refreshWifi();
    }, 30000);
    this.sampleTimer = setInterval(() => {
      this.sample();
    }, 1000);
    this.elapsedTimer = setInterval(() => {
      AppStorage.setOrCreate('rm_elapsed', Math.floor((Date.now() - this.t0) / 1000));
    }, 1000);

    this.startBackground(name);
  }

  async stop(): Promise<void> {
    if (!this.running) {
      return;
    }
    this.running = false;
    if (this.sampleTimer >= 0) {
      clearInterval(this.sampleTimer);
      this.sampleTimer = -1;
    }
    if (this.elapsedTimer >= 0) {
      clearInterval(this.elapsedTimer);
      this.elapsedTimer = -1;
    }
    if (this.wifiTimer >= 0) {
      clearInterval(this.wifiTimer);
      this.wifiTimer = -1;
    }
    try {
      sensor.off(sensor.SensorId.BAROMETER, this.pressureCb);
    } catch (e) {
    }
    try {
      sensor.off(sensor.SensorId.MAGNETIC_FIELD, this.magCb);
    } catch (e) {
    }
    try {
      sensor.off(sensor.SensorId.ACCELEROMETER, this.accelCb);
    } catch (e) {
    }
    try {
      geoLocationManager.off('locationChange', this.locCb);
    } catch (e) {
    }

    const batch = this.buffer;
    this.buffer = [];
    try {
      await Store.insertPoints(batch);
    } catch (e) {
    }
    try {
      await Store.finishTrack(this.trackId, Date.now(), this.pointCount);
    } catch (e) {
    }

    AppStorage.setOrCreate('rm_recording', false);
    AppStorage.setOrCreate('rm_rec_track_name', '');
    AppStorage.setOrCreate('rm_elapsed', 0);
    this.stopBackground();
  }

  private sample(): void {
    const loc = this.lastLoc;
    // 朝向：加速度+地磁融合方位角，GPS direction 兜底
    let headingDeg: number | undefined = undefined;
    if (this.hasAccel && this.hasMag) {
      headingDeg = fusedAzimuth(this.lastAccel, this.lastMag);
    }
    if (headingDeg === undefined && loc && loc.direction !== undefined) {
      headingDeg = loc.direction;
    }
    this.lastHeading = headingDeg;
    const pt: TrackPointDraft = {
      trackId: this.trackId,
      timeMs: Date.now(),
      latitude: loc ? loc.latitude : undefined,
      longitude: loc ? loc.longitude : undefined,
      altitude: loc ? loc.altitude : undefined,
      accuracy: loc ? loc.accuracy : undefined,
      pressureHpa: this.lastPressure,
      magneticX: this.hasMag ? this.lastMag[0] : undefined,
      magneticY: this.hasMag ? this.lastMag[1] : undefined,
      magneticZ: this.hasMag ? this.lastMag[2] : undefined,
      headingDeg: headingDeg,
      wifiCount: this.lastWifiCount,
      wifiTop: this.lastWifi
    };
    this.buffer.push(pt);
    this.pointCount++;
    if (this.buffer.length >= 5) {
      const batch = this.buffer;
      this.buffer = [];
      Store.insertPoints(batch).catch(() => {
      });
    }
  }

  private refreshWifi(): void {
    try {
      wifiManager.scan();
    } catch (e) {
    }
    setTimeout(() => {
      try {
        const list = wifiManager.getScanInfoList();
        const top = list.slice()
          .sort((a: wifiManager.WifiScanInfo, b: wifiManager.WifiScanInfo) => b.rssi - a.rssi)
          .slice(0, 5);
        this.lastWifi = top.map((i: wifiManager.WifiScanInfo) => `${i.bssid}:${i.rssi}`).join(';');
        this.lastWifiCount = list.length;
      } catch (e) {
      }
    }, 1500);
  }

  private async startBackground(name: string): Promise<void> {
    try {
      const context = Ctx.ui;
      if (!context) {
        return;
      }
      const info: wantAgent.WantAgentInfo = {
        wants: [{ bundleName: 'com.example.roommarker', abilityName: 'EntryAbility' }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(info);
      // HarmonyOS 6（API 21）：LOCATION 长时任务改用字符串数组形式申请
      await backgroundTaskManager.startBackgroundRunning(context, ['location'], agent);
    } catch (e) {
    }
    try {
      await notificationManager.publish({
        id: NOTIF_ID,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: { title: '正在记录轨迹', text: `「${name}」· 点击返回应用` }
        }
      });
    } catch (e) {
    }
  }

  private stopBackground(): void {
    try {
      notificationManager.cancel(NOTIF_ID);
    } catch (e) {
    }
    try {
      if (Ctx.ui) {
        backgroundTaskManager.stopBackgroundRunning(Ctx.ui);
      }
    } catch (e) {
    }
  }
}
