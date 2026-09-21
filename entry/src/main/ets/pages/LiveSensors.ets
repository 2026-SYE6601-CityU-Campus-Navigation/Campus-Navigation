import {
  LiveStream,
  LocView,
  MagView,
  PressureView,
  WifiView,
  SensorInfoView,
  LiveListener,
  Vec3View,
  QuatView,
  OrientView
} from '../sensors/LiveStream';
import { fmtTime } from '../common/Utils';

@Component
export struct LiveSensorsPage {
  onBack: () => void = () => {
  };
  // 数据字段用 @StorageLink（与 WiFi 卡片同款路径）；显示刷新由 heartbeat 重建驱动
  @StorageLink('rm_live_location') loc: LocView | null = null;
  @StorageLink('rm_live_pressure') pressure: PressureView | null = null;
  @StorageLink('rm_live_magnetic') mag: MagView | null = null;
  @StorageLink('rm_live_wifi') wifi: WifiView[] = [];
  @StorageLink('rm_live_wifi_scan_ms') lastScanMs: number = 0;
  @StorageLink('rm_live_has_pressure') hasPressure: boolean = false;
  @StorageLink('rm_live_has_magnetic') hasMagnetic: boolean = false;
  @StorageLink('rm_sensor_list') sensorList: SensorInfoView[] = [];
  @StorageLink('rm_live_tick_ms') tickMs: number = 0;
  @StorageLink('rm_live_pressure_ms') pressureMs: number = 0;
  @StorageLink('rm_live_mag_ms') magMs: number = 0;

  @StorageLink('rm_live_accel') accel: Vec3View | null = null;
  @StorageLink('rm_live_linear') linear: Vec3View | null = null;
  @StorageLink('rm_live_gravity') gravity: Vec3View | null = null;
  @StorageLink('rm_live_gyro') gyro: Vec3View | null = null;
  @StorageLink('rm_live_rotvec') rotvec: QuatView | null = null;
  @StorageLink('rm_live_orient') orient: OrientView | null = null;
  @StorageLink('rm_live_light') light: number = -1;
  @StorageLink('rm_live_proximity') proximity: number = -1;
  @StorageLink('rm_live_humidity') humidity: number = -1;
  @StorageLink('rm_live_ambtemp') ambTemp: number = -999;
  @StorageLink('rm_live_hall') hall: number = -1;
  @StorageLink('rm_live_pedometer') pedometer: number = -1;
  @StorageLink('rm_live_has_accel') hasAccel: boolean = false;
  @StorageLink('rm_live_has_linear') hasLinear: boolean = false;
  @StorageLink('rm_live_has_gravity') hasGravity: boolean = false;
  @StorageLink('rm_live_has_gyro') hasGyro: boolean = false;
  @StorageLink('rm_live_has_rotvec') hasRotVec: boolean = false;
  @StorageLink('rm_live_has_orient') hasOrient: boolean = false;
  @StorageLink('rm_live_has_light') hasLight: boolean = false;
  @StorageLink('rm_live_has_proximity') hasProximity: boolean = false;
  @StorageLink('rm_live_has_humidity') hasHumidity: boolean = false;
  @StorageLink('rm_live_has_ambtemp') hasAmbTemp: boolean = false;
  @StorageLink('rm_live_has_hall') hasHall: boolean = false;
  @StorageLink('rm_live_has_pedometer') hasPedometer: boolean = false;

  @State pressureAnchor: number = -1;
  /** 本地心跳：每 100ms 自增，驱动 ForEach 按 key 重建卡片树（等价于自动"重新进入页面"） */
  @State heartbeat: number = 0;
  private hbTimer: number = -1;

  /** 传感器回调：仅用于气压锚点等本地逻辑（显示刷新由心跳重建驱动） */
  private liveListener: LiveListener = {
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

  build() {
    Column() {
      Row() {
        Button('‹ 返回').fontSize(14).onClick(() => {
          this.onBack();
        })
        Text('实时传感器').fontSize(18).fontWeight(FontWeight.Medium).margin({ left: 12 })
        Blank()
        Text(this.tickMs > 0 ? `更新 ${fmtTime(this.tickMs)}` : '等待数据')
          .fontSize(12)
          .fontColor('#99000000')
      }.width('100%').padding({ left: 8, right: 12, top: 10, bottom: 10 })
      Divider()

      Scroll() {
        Column() {
          // 以 heartbeat 为 key：每 0.5s 键变化 → 整个卡片列销毁重建 →
          // @StorageLink 重新初始化读取 AppStorage 最新值（等价于自动"重新进入页面"）
          ForEach([this.heartbeat], (h: number) => {
            Column({ space: 12 }) {
              this.LocationCard()
              this.PressureCard()
              this.MagneticCard()
              this.MotionCard()
              this.EnvCard()
              this.WifiCard()
              this.SensorListCard()
            }.padding(16).width('100%')
          }, (h: number) => `${h}`)
        }
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%')
  }

  @Builder
  LocationCard() {
    Column({ space: 8 }) {
      Text('定位 / GPS').fontSize(16).fontWeight(FontWeight.Medium).width('100%')
      this.LocationBody()
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFF7F7F7')
    .borderRadius(12)
  }

  @Builder
  PressureCard() {
    Column({ space: 8 }) {
      Text('气压计').fontSize(16).fontWeight(FontWeight.Medium).width('100%')
      this.PressureBody()
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFF7F7F7')
    .borderRadius(12)
  }

  @Builder
  MagneticCard() {
    Column({ space: 8 }) {
      Text('地磁 / 磁力计').fontSize(16).fontWeight(FontWeight.Medium).width('100%')
      this.MagneticBody()
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFF7F7F7')
    .borderRadius(12)
  }

  @Builder
  MotionCard() {
    Column({ space: 8 }) {
      Text('运动传感器').fontSize(16).fontWeight(FontWeight.Medium).width('100%')
      this.Vec3Row('加速度计', this.hasAccel, this.accel, 'm/s²')
      this.Vec3Row('线性加速度', this.hasLinear, this.linear, 'm/s²')
      this.Vec3Row('重力', this.hasGravity, this.gravity, 'm/s²')
      this.Vec3Row('陀螺仪', this.hasGyro, this.gyro, 'rad/s')
      this.QuatRow('旋转矢量', this.hasRotVec, this.rotvec)
      this.OrientRow('方向', this.hasOrient, this.orient)
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFF7F7F7')
    .borderRadius(12)
  }

  @Builder
  EnvCard() {
    Column({ space: 8 }) {
      Text('环境与状态传感器').fontSize(16).fontWeight(FontWeight.Medium).width('100%')
      this.ScalarRow('环境光', this.hasLight, this.light, `${this.light.toFixed(0)} lux`)
      this.ScalarRow('接近', this.hasProximity, this.proximity, `${this.proximity.toFixed(1)} cm`)
      this.ScalarRow('湿度', this.hasHumidity, this.humidity, `${this.humidity.toFixed(1)} %`)
      this.ScalarRow('环境温度', this.hasAmbTemp, this.ambTemp,
        this.ambTemp > -900 ? `${this.ambTemp.toFixed(1)} °C` : '')
      this.ScalarRow('霍尔', this.hasHall, this.hall, `状态 ${this.hall}`)
      this.ScalarRow('计步器', this.hasPedometer, this.pedometer, `${this.pedometer} 步`)
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFF7F7F7')
    .borderRadius(12)
  }

  @Builder
  WifiCard() {
    Column({ space: 8 }) {
      Text(`WiFi 指纹（${this.wifi.length} 个 AP）`)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .width('100%')
      this.WifiBody()
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFF7F7F7')
    .borderRadius(12)
  }

  @Builder
  SensorListCard() {
    Column({ space: 8 }) {
      Text(`设备传感器清单（${this.sensorList.length} 个）`)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .width('100%')
      if (this.sensorList.length === 0) {
        Text('无法读取传感器列表').fontSize(14).fontColor('#99000000').width('100%')
      } else {
        ForEach(this.sensorList, (s: SensorInfoView) => {
          Row() {
            Column({ space: 2 }) {
              Text(s.label).fontSize(14)
              Text(`${s.name} · ${s.vendor}`)
                .fontSize(11)
                .fontColor('#99000000')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }.layoutWeight(1)
            Text(`id ${s.id}`).fontSize(11).fontColor('#99000000')
          }.width('100%').padding({ top: 6, bottom: 6 })
        }, (s: SensorInfoView) => s.id + '')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFF7F7F7')
    .borderRadius(12)
  }

  @Builder
  Vec3Row(label: string, has: boolean, v: Vec3View | null, unit: string) {
    Row() {
      Text(label).fontSize(13).fontColor('#99000000').width(88)
      if (!has) {
        Text('此设备无该传感器').fontSize(13).fontColor('#99000000')
      } else if (v === null) {
        Text('等待读数…').fontSize(13).fontColor('#99000000')
      } else {
        Text(`X ${v.x.toFixed(2)} · Y ${v.y.toFixed(2)} · Z ${v.z.toFixed(2)} · 模 ${v.m.toFixed(2)} ${unit}`)
          .fontSize(12)
      }
    }.width('100%').padding({ top: 4, bottom: 4 })
  }

  @Builder
  QuatRow(label: string, has: boolean, v: QuatView | null) {
    Row() {
      Text(label).fontSize(13).fontColor('#99000000').width(88)
      if (!has) {
        Text('此设备无该传感器').fontSize(13).fontColor('#99000000')
      } else if (v === null) {
        Text('等待读数…').fontSize(13).fontColor('#99000000')
      } else {
        Text(`X ${v.x.toFixed(3)} · Y ${v.y.toFixed(3)} · Z ${v.z.toFixed(3)} · W ${v.w.toFixed(3)}`)
          .fontSize(12)
      }
    }.width('100%').padding({ top: 4, bottom: 4 })
  }

  @Builder
  OrientRow(label: string, has: boolean, v: OrientView | null) {
    Row() {
      Text(label).fontSize(13).fontColor('#99000000').width(88)
      if (!has) {
        Text('此设备无该传感器').fontSize(13).fontColor('#99000000')
      } else if (v === null) {
        Text('等待读数…').fontSize(13).fontColor('#99000000')
      } else {
        Text(`α ${v.alpha.toFixed(0)}° · β ${v.beta.toFixed(0)}° · γ ${v.gamma.toFixed(0)}°`)
          .fontSize(12)
      }
    }.width('100%').padding({ top: 4, bottom: 4 })
  }

  @Builder
  ScalarRow(label: string, has: boolean, v: number, text: string) {
    Row() {
      Text(label).fontSize(13).fontColor('#99000000').width(88)
      if (!has) {
        Text('此设备无该传感器').fontSize(13).fontColor('#99000000')
      } else if (v < 0 || text.length === 0) {
        Text('等待读数…').fontSize(13).fontColor('#99000000')
      } else {
        Text(text).fontSize(12)
      }
    }.width('100%').padding({ top: 4, bottom: 4 })
  }

  @Builder
  LocationBody() {
    if (this.loc === null) {
      Text('等待定位中…（室内可能长时间无定位信号）').fontSize(14).width('100%')
    } else {
      this.InfoRow('纬度', this.loc.lat.toFixed(6))
      this.InfoRow('经度', this.loc.lng.toFixed(6))
      this.InfoRow('海拔', `${this.loc.alt.toFixed(1)} m`)
      this.InfoRow('精度', this.loc.acc !== undefined ? `±${this.loc.acc.toFixed(1)} m` : '未知')
      this.InfoRow('速度', this.loc.spd !== undefined ? `${this.loc.spd.toFixed(2)} m/s` : '未知')
      this.InfoRow('方位', this.loc.brg !== undefined ? `${((this.loc.brg + 360) % 360).toFixed(0)}°` : '未知')
      this.InfoRow('更新', fmtTime(this.loc.timeMs))
      if (this.tickMs > 0) {
        this.InfoRow('距上次定位', this.locAgoText())
      }
    }
  }

  @Builder
  PressureBody() {
    if (!this.hasPressure) {
      Text('此设备无气压计传感器').fontSize(14).width('100%')
    } else if (this.pressure === null) {
      Text('等待读数…').fontSize(14).width('100%')
    } else {
      this.InfoRow('气压', `${this.pressure.hpa.toFixed(3)} hPa`)
      this.InfoRow('相对变化', this.pressureAnchor >= 0
        ? `${(this.pressure.hpa - this.pressureAnchor).toFixed(3)} hPa（进出页面时归零）` : '—')
      this.InfoRow('推算海拔', `${this.pressure.alt.toFixed(1)} m（相对海平面，楼层判断约 3m/层）`)
      this.InfoRow('更新', this.pressureMs > 0 ? fmtTime(this.pressureMs) : '—')
    }
  }

  @Builder
  MagneticBody() {
    if (!this.hasMagnetic) {
      Text('此设备无磁力计传感器').fontSize(14).width('100%')
    } else if (this.mag === null) {
      Text('等待读数…').fontSize(14).width('100%')
    } else {
      this.InfoRow('X / Y / Z', `${this.mag.x.toFixed(2)} / ${this.mag.y.toFixed(2)} / ${this.mag.z.toFixed(2)} µT`)
      this.InfoRow('总场强', `${this.mag.mag.toFixed(2)} µT（地磁基准约 45-55）`)
      this.InfoRow('方位角', this.mag.az !== undefined ? `${this.mag.az.toFixed(0)}°` : '不可用')
      this.InfoRow('更新', this.magMs > 0 ? fmtTime(this.magMs) : '—')
    }
  }

  @Builder
  WifiBody() {
    if (this.lastScanMs === 0) {
      Text('尚未完成扫描').fontSize(12).fontColor('#99000000').width('100%')
    } else {
      Text(`最近扫描：${fmtTime(this.lastScanMs)}`)
        .fontSize(12)
        .fontColor('#99000000')
        .width('100%')
    }
    if (this.wifi.length === 0) {
      Text('暂无 WiFi 扫描结果 —— 需授权位置权限并打开系统定位开关；扫描受系统节流（约 30 秒一次）')
        .fontSize(12)
        .fontColor('#99000000')
        .width('100%')
    } else {
      ForEach(this.wifi, (ap: WifiView) => {
        Column({ space: 2 }) {
          Text(`${ap.ssid.length > 0 ? ap.ssid : '(隐藏网络)'}  ${ap.bssid}`)
            .fontSize(14)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${ap.rssi} dBm · ${ap.freq} MHz`)
            .fontSize(12)
            .fontColor('#99000000')
            .width('100%')
        }.width('100%').padding({ top: 6, bottom: 6 })
      }, (ap: WifiView) => ap.bssid)
    }
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor('#99000000').width(72)
      Text(value).fontSize(14)
    }.width('100%')
  }

  /** 「距上次定位」文案：随 tick 实时变化，证明定位卡片在等 GPS 修正 */
  private locAgoText(): string {
    if (this.tickMs <= 0 || this.loc === null) {
      return '';
    }
    const ago = Math.max(0, Math.floor((this.tickMs - this.loc.timeMs) / 1000));
    return ago < 60 ? `${ago} 秒前` : `${Math.floor(ago / 60)} 分钟前（室内 GPS 信号弱属正常）`;
  }
}
