import { sensor } from '@kit.SensorServiceKit';
import { geoLocationManager } from '@kit.LocationKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fusedAzimuth } from '../common/Utils';

const TAG = 'RoomMarker';

export interface LocView {
  lat: number; lng: number; alt: number;
  acc?: number; spd?: number; brg?: number; timeMs: number;
}
export interface PressureView { hpa: number; alt: number; }
export interface MagView { x: number; y: number; z: number; mag: number; az?: number; }
export interface WifiView { ssid: string; bssid: string; rssi: number; freq: number; }
export interface SensorInfoView { id: number; label: string; name: string; vendor: string; }
export interface Vec3View { x: number; y: number; z: number; m: number; }
export interface QuatView { x: number; y: number; z: number; w: number; }
export interface OrientView { alpha: number; beta: number; gamma: number; }

/** 实时数据监听器（页面保留用于气压锚点等本地逻辑，显示刷新由心跳重建驱动） */
export interface LiveListener {
  onLoc?: (v: LocView) => void;
  onPressure?: (v: PressureView) => void;
  onMag?: (v: MagView) => void;
  onWifi?: (list: WifiView[]) => void;
  onFlags?: (hasPressure: boolean, hasMag: boolean) => void;
  onSensorList?: (list: SensorInfoView[]) => void;
  onTick?: (ms: number) => void;
}

function hasSensor(t: sensor.SensorId): boolean {
  try {
    sensor.getSingleSensorSync(t);
    return true;
  } catch (e) {
    return false;
  }
}

function vec3(x: number, y: number, z: number): Vec3View {
  return { x: x, y: y, z: z, m: Math.sqrt(x * x + y * y + z * z) } as Vec3View;
}

/**
 * 实时传感器流：
 * 数据源为 500ms 定时器 + sensor.once 轮询（真机验证可靠；持续订阅在本环境无效）；
 * 全部写入 AppStorage，页面通过心跳重建机制读取（见 LiveSensors 页）。
 */
export class LiveStream {
  private static inst: LiveStream | null = null;
  static get(): LiveStream {
    if (!LiveStream.inst) {
      LiveStream.inst = new LiveStream();
    }
    return LiveStream.inst;
  }

  private started = false;
  private listener: LiveListener | null = null;
  private sensorTimer = -1;
  private locTimer = -1;
  private wifiTimer = -1;
  private wifiReadTimer = -1;
  private accel: number[] = [0, 0, 0];
  private mag: number[] = [0, 0, 0];
  private hasAccelData = false;
  private hasMagData = false;

  // 设备传感器可用标志（start 时探测一次，onceRead 按需轮询）
  private hasLinearAccel = false;
  private hasGravity = false;
  private hasGyro = false;
  private hasRotVec = false;
  private hasOrient = false;
  private hasLight = false;
  private hasProx = false;
  private hasHumidity = false;
  private hasAmbTemp = false;
  private hasHall = false;
  private hasPedometer = false;

  /** 页面进入时注册、离开时注销 */
  setListener(l: LiveListener | null): void {
    this.listener = l;
  }

  private handlePressure = (d: sensor.BarometerResponse): void => {
    const p = d.pressure;
    const alt = 44330 * (1 - Math.pow(p / 1013.25, 0.1903));
    const v: PressureView = { hpa: p, alt: alt } as PressureView;
    this.push('rm_live_pressure', v);
    this.setVal('rm_live_pressure_ms', Date.now());
    if (this.listener && this.listener.onPressure) {
      this.listener.onPressure(v);
    }
  };
  private handleMag = (d: sensor.MagneticFieldResponse): void => {
    this.mag = [d.x, d.y, d.z];
    this.hasMagData = true;
    this.publishMag();
  };
  private handleAccel = (d: sensor.AccelerometerResponse): void => {
    this.accel = [d.x, d.y, d.z];
    this.hasAccelData = true;
    this.publishMag();
    this.push('rm_live_accel', vec3(d.x, d.y, d.z));
  };
  private handleLinear = (d: sensor.LinearAccelerometerResponse): void => {
    this.push('rm_live_linear', vec3(d.x, d.y, d.z));
  };
  private handleGravity = (d: sensor.GravityResponse): void => {
    this.push('rm_live_gravity', vec3(d.x, d.y, d.z));
  };
  private handleGyro = (d: sensor.GyroscopeResponse): void => {
    this.push('rm_live_gyro', vec3(d.x, d.y, d.z));
  };
  private handleRotVec = (d: sensor.RotationVectorResponse): void => {
    this.push('rm_live_rotvec', { x: d.x, y: d.y, z: d.z, w: d.w } as QuatView);
  };
  private handleOrient = (d: sensor.OrientationResponse): void => {
    this.push('rm_live_orient',
      { alpha: d.alpha, beta: d.beta, gamma: d.gamma } as OrientView);
  };
  private handleLight = (d: sensor.LightResponse): void => {
    this.push('rm_live_light', d.intensity);
  };
  private handleProx = (d: sensor.ProximityResponse): void => {
    this.push('rm_live_proximity', d.distance);
  };
  private handleHumidity = (d: sensor.HumidityResponse): void => {
    this.push('rm_live_humidity', d.humidity);
  };
  private handleAmbTemp = (d: sensor.AmbientTemperatureResponse): void => {
    this.push('rm_live_ambtemp', d.temperature);
  };
  private handleHall = (d: sensor.HallResponse): void => {
    this.push('rm_live_hall', d.status);
  };
  private handlePedo = (d: sensor.PedometerResponse): void => {
    this.push('rm_live_pedometer', d.steps);
  };
  private handleLoc = (loc: geoLocationManager.Location): void => {
    const v: LocView = {
      lat: loc.latitude, lng: loc.longitude, alt: loc.altitude,
      acc: loc.accuracy, spd: loc.speed, brg: loc.direction,
      timeMs: loc.timeStamp
    };
    this.push('rm_live_location', v);
    if (this.listener && this.listener.onLoc) {
      this.listener.onLoc(v);
    }
  };

  /** 写 AppStorage（setOrCreate 与 WiFi 路径同款）+ 更新全局时间戳 */
  private push(key: string, v: Object): void {
    try {
      AppStorage.setOrCreate(key, v);
    } catch (e) {
    }
    const now = Date.now();
    try {
      AppStorage.setOrCreate('rm_live_tick_ms', now);
    } catch (e) {
    }
    if (this.listener && this.listener.onTick) {
      this.listener.onTick(now);
    }
  }

  private setVal(key: string, v: Object): void {
    try {
      AppStorage.setOrCreate(key, v);
    } catch (e) {
    }
  }

  private publishMag(): void {
    const x = this.mag[0], y = this.mag[1], z = this.mag[2];
    const mag = Math.sqrt(x * x + y * y + z * z);
    let az: number | undefined = undefined;
    if (this.hasAccelData && this.hasMagData) {
      az = fusedAzimuth(this.accel, this.mag);
    }
    const v: MagView = { x: x, y: y, z: z, mag: mag, az: az };
    this.push('rm_live_magnetic', v);
    this.setVal('rm_live_mag_ms', Date.now());
    if (this.listener && this.listener.onMag) {
      this.listener.onMag(v);
    }
  }

  private labelFor(id: number): string {
    if (id === sensor.SensorId.ACCELEROMETER) {
      return '加速度计';
    }
    if (id === sensor.SensorId.ACCELEROMETER_UNCALIBRATED) {
      return '加速度计·未校准';
    }
    if (id === sensor.SensorId.LINEAR_ACCELEROMETER) {
      return '线性加速度';
    }
    if (id === sensor.SensorId.GRAVITY) {
      return '重力';
    }
    if (id === sensor.SensorId.GYROSCOPE) {
      return '陀螺仪';
    }
    if (id === sensor.SensorId.GYROSCOPE_UNCALIBRATED) {
      return '陀螺仪·未校准';
    }
    if (id === sensor.SensorId.MAGNETIC_FIELD) {
      return '磁力计';
    }
    if (id === sensor.SensorId.MAGNETIC_FIELD_UNCALIBRATED) {
      return '磁力计·未校准';
    }
    if (id === sensor.SensorId.BAROMETER) {
      return '气压计';
    }
    if (id === sensor.SensorId.ROTATION_VECTOR) {
      return '旋转矢量';
    }
    if (id === sensor.SensorId.ORIENTATION) {
      return '方向';
    }
    if (id === sensor.SensorId.AMBIENT_LIGHT) {
      return '环境光';
    }
    if (id === sensor.SensorId.PROXIMITY) {
      return '接近';
    }
    if (id === sensor.SensorId.HUMIDITY) {
      return '湿度';
    }
    if (id === sensor.SensorId.AMBIENT_TEMPERATURE) {
      return '环境温度';
    }
    if (id === sensor.SensorId.HALL) {
      return '霍尔';
    }
    if (id === sensor.SensorId.PEDOMETER) {
      return '计步器';
    }
    if (id === sensor.SensorId.PEDOMETER_DETECTION) {
      return '计步检测';
    }
    if (id === sensor.SensorId.HEART_RATE) {
      return '心率';
    }
    if (id === sensor.SensorId.SIGNIFICANT_MOTION) {
      return '大幅运动';
    }
    return `传感器 #${id}`;
  }

  /** 枚举设备全部传感器（供「设备传感器清单」卡片展示） */
  private scanSensorList(): void {
    let out: SensorInfoView[] = [];
    try {
      const list = sensor.getSensorListSync();
      out = list.map((s: sensor.Sensor) => {
        return {
          id: s.sensorId,
          label: this.labelFor(s.sensorId),
          name: s.sensorName,
          vendor: s.vendorName
        } as SensorInfoView;
      });
    } catch (e) {
    }
    AppStorage.setOrCreate('rm_sensor_list', out);
    if (this.listener && this.listener.onSensorList) {
      this.listener.onSensorList(out);
    }
  }

  /**
   * 定时轮询一次传感器读数（sensor.once，按设备能力按需调用）。
   * 开头无条件刷新时间戳心跳：页面 @State heartbeat 依赖其节奏重建卡片（见 LiveSensors 页）。
   */
  private onceRead(): void {
    const now = Date.now();
    try {
      AppStorage.setOrCreate('rm_live_tick_ms', now);
    } catch (e) {
    }
    if (this.listener && this.listener.onTick) {
      this.listener.onTick(now);
    }
    try {
      sensor.once(sensor.SensorId.BAROMETER, this.handlePressure);
    } catch (e) {
    }
    try {
      sensor.once(sensor.SensorId.MAGNETIC_FIELD, this.handleMag);
    } catch (e) {
    }
    try {
      sensor.once(sensor.SensorId.ACCELEROMETER, this.handleAccel);
    } catch (e) {
    }
    if (this.hasLinearAccel) {
      try {
        sensor.once(sensor.SensorId.LINEAR_ACCELEROMETER, this.handleLinear);
      } catch (e) {
      }
    }
    if (this.hasGravity) {
      try {
        sensor.once(sensor.SensorId.GRAVITY, this.handleGravity);
      } catch (e) {
      }
    }
    if (this.hasGyro) {
      try {
        sensor.once(sensor.SensorId.GYROSCOPE, this.handleGyro);
      } catch (e) {
      }
    }
    if (this.hasRotVec) {
      try {
        sensor.once(sensor.SensorId.ROTATION_VECTOR, this.handleRotVec);
      } catch (e) {
      }
    }
    if (this.hasOrient) {
      try {
        sensor.once(sensor.SensorId.ORIENTATION, this.handleOrient);
      } catch (e) {
      }
    }
    if (this.hasLight) {
      try {
        sensor.once(sensor.SensorId.AMBIENT_LIGHT, this.handleLight);
      } catch (e) {
      }
    }
    if (this.hasProx) {
      try {
        sensor.once(sensor.SensorId.PROXIMITY, this.handleProx);
      } catch (e) {
      }
    }
    if (this.hasHumidity) {
      try {
        sensor.once(sensor.SensorId.HUMIDITY, this.handleHumidity);
      } catch (e) {
      }
    }
    if (this.hasAmbTemp) {
      try {
        sensor.once(sensor.SensorId.AMBIENT_TEMPERATURE, this.handleAmbTemp);
      } catch (e) {
      }
    }
    if (this.hasHall) {
      try {
        sensor.once(sensor.SensorId.HALL, this.handleHall);
      } catch (e) {
      }
    }
    if (this.hasPedometer) {
      try {
        sensor.once(sensor.SensorId.PEDOMETER, this.handlePedo);
      } catch (e) {
      }
    }
  }

  /** 定位兜底轮询：除持续订阅外，每 5 秒主动请求一次单次定位 */
  private pollLoc(): void {
    try {
      const oneShot: geoLocationManager.SingleLocationRequest = {
        locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_ACCURACY,
        locatingTimeoutMs: 4000
      };
      geoLocationManager.getCurrentLocation(oneShot).then((l: geoLocationManager.Location) => {
        this.handleLoc(l);
      }).catch(() => {
      });
    } catch (e) {
    }
  }

  start(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    AppStorage.setOrCreate('rm_live_tick_ms', 0);
    AppStorage.setOrCreate('rm_live_pressure_ms', 0);
    AppStorage.setOrCreate('rm_live_mag_ms', 0);
    this.scanSensorList();
    const hp = hasSensor(sensor.SensorId.BAROMETER);
    const hm = hasSensor(sensor.SensorId.MAGNETIC_FIELD);
    this.hasLinearAccel = hasSensor(sensor.SensorId.LINEAR_ACCELEROMETER);
    this.hasGravity = hasSensor(sensor.SensorId.GRAVITY);
    this.hasGyro = hasSensor(sensor.SensorId.GYROSCOPE);
    this.hasRotVec = hasSensor(sensor.SensorId.ROTATION_VECTOR);
    this.hasOrient = hasSensor(sensor.SensorId.ORIENTATION);
    this.hasLight = hasSensor(sensor.SensorId.AMBIENT_LIGHT);
    this.hasProx = hasSensor(sensor.SensorId.PROXIMITY);
    this.hasHumidity = hasSensor(sensor.SensorId.HUMIDITY);
    this.hasAmbTemp = hasSensor(sensor.SensorId.AMBIENT_TEMPERATURE);
    this.hasHall = hasSensor(sensor.SensorId.HALL);
    this.hasPedometer = hasSensor(sensor.SensorId.PEDOMETER);
    AppStorage.setOrCreate('rm_live_has_pressure', hp);
    AppStorage.setOrCreate('rm_live_has_magnetic', hm);
    AppStorage.setOrCreate('rm_live_has_accel', hasSensor(sensor.SensorId.ACCELEROMETER));
    AppStorage.setOrCreate('rm_live_has_linear', this.hasLinearAccel);
    AppStorage.setOrCreate('rm_live_has_gravity', this.hasGravity);
    AppStorage.setOrCreate('rm_live_has_gyro', this.hasGyro);
    AppStorage.setOrCreate('rm_live_has_rotvec', this.hasRotVec);
    AppStorage.setOrCreate('rm_live_has_orient', this.hasOrient);
    AppStorage.setOrCreate('rm_live_has_light', this.hasLight);
    AppStorage.setOrCreate('rm_live_has_proximity', this.hasProx);
    AppStorage.setOrCreate('rm_live_has_humidity', this.hasHumidity);
    AppStorage.setOrCreate('rm_live_has_ambtemp', this.hasAmbTemp);
    AppStorage.setOrCreate('rm_live_has_hall', this.hasHall);
    AppStorage.setOrCreate('rm_live_has_pedometer', this.hasPedometer);
    if (this.listener && this.listener.onFlags) {
      this.listener.onFlags(hp, hm);
    }
    AppStorage.setOrCreate('rm_live_location', null);
    AppStorage.setOrCreate('rm_live_pressure', null);
    AppStorage.setOrCreate('rm_live_magnetic', null);
    AppStorage.setOrCreate('rm_live_wifi', [] as WifiView[]);
    AppStorage.setOrCreate('rm_live_wifi_scan_ms', 0);
    AppStorage.setOrCreate('rm_live_accel', null);
    AppStorage.setOrCreate('rm_live_linear', null);
    AppStorage.setOrCreate('rm_live_gravity', null);
    AppStorage.setOrCreate('rm_live_gyro', null);
    AppStorage.setOrCreate('rm_live_rotvec', null);
    AppStorage.setOrCreate('rm_live_orient', null);
    AppStorage.setOrCreate('rm_live_light', -1);
    AppStorage.setOrCreate('rm_live_proximity', -1);
    AppStorage.setOrCreate('rm_live_humidity', -1);
    AppStorage.setOrCreate('rm_live_ambtemp', -999);
    AppStorage.setOrCreate('rm_live_hall', -1);
    AppStorage.setOrCreate('rm_live_pedometer', -1);

    // 传感器：250ms 定时器 once 轮询（真机持续订阅不可靠，定时器模式与 WiFi 一致、已验证；
    // once 完整周期约 200ms，间隔低于 250ms 会造成订阅重叠）
    this.onceRead();
    this.sensorTimer = setInterval(() => {
      this.onceRead();
    }, 250);

    // 定位：持续订阅 + 5 秒轮询兜底
    const req: geoLocationManager.ContinuousLocationRequest = {
      interval: 1,
      locationScenario: geoLocationManager.UserActivityScenario.NAVIGATION
    };
    try {
      geoLocationManager.on('locationChange', req, this.handleLoc);
    } catch (e) {
      hilog.error(0x0000, TAG, '定位订阅失败: %{public}s', JSON.stringify(e));
    }
    this.pollLoc();
    this.locTimer = setInterval(() => {
      this.pollLoc();
    }, 5000);

    this.doWifiScan();
    this.wifiTimer = setInterval(() => {
      this.doWifiScan();
    }, 30000);
  }

  stop(): void {
    if (!this.started) {
      return;
    }
    this.started = false;
    if (this.sensorTimer >= 0) {
      clearInterval(this.sensorTimer);
      this.sensorTimer = -1;
    }
    if (this.locTimer >= 0) {
      clearInterval(this.locTimer);
      this.locTimer = -1;
    }
    if (this.wifiTimer >= 0) {
      clearInterval(this.wifiTimer);
      this.wifiTimer = -1;
    }
    if (this.wifiReadTimer >= 0) {
      clearTimeout(this.wifiReadTimer);
      this.wifiReadTimer = -1;
    }
    try {
      geoLocationManager.off('locationChange', this.handleLoc);
    } catch (e) {
    }
  }

  private doWifiScan(): void {
    try {
      wifiManager.scan();
    } catch (e) {
    }
    // 扫描结果异步返回，1.5s 后读取一次最新列表（受系统节流限制）
    if (this.wifiReadTimer >= 0) {
      clearTimeout(this.wifiReadTimer);
    }
    this.wifiReadTimer = setTimeout(() => {
      this.readWifi();
    }, 1500);
  }

  private readWifi(): void {
    try {
      const list = wifiManager.getScanInfoList();
      const out: WifiView[] = list.map((i: wifiManager.WifiScanInfo) => {
        return { ssid: i.ssid, bssid: i.bssid, rssi: i.rssi, freq: i.frequency } as WifiView;
      });
      out.sort((a: WifiView, b: WifiView) => b.rssi - a.rssi);
      AppStorage.setOrCreate('rm_live_wifi', out);
      AppStorage.setOrCreate('rm_live_wifi_scan_ms', Date.now());
      if (this.listener && this.listener.onWifi) {
        this.listener.onWifi(out);
      }
    } catch (e) {
    }
  }
}
