import { AbilityConstant, UIAbility, Want, abilityAccessCtrl } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Ctx } from '../common/Utils';
import { Store } from '../data/Store';
import { TrackRecorder } from '../sensors/TrackRecorder';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Ctx.ui = this.context;
    Store.init(this.context);

    AppStorage.setOrCreate('rm_recording', false);
    AppStorage.setOrCreate('rm_elapsed', 0);
    AppStorage.setOrCreate('rm_rec_track_name', '');

    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    atManager.requestPermissionsFromUser(this.context, [
      'ohos.permission.LOCATION',
      'ohos.permission.APPROXIMATELY_LOCATION',
      'ohos.permission.LOCATION_IN_BACKGROUND',
      'ohos.permission.ACCELEROMETER',
      'ohos.permission.ACTIVITY_MOTION'
    ]).then(() => {
      hilog.info(0x0000, 'RoomMarker', 'location permission granted');
    }).catch((err: Object) => {
      hilog.error(0x0000, 'RoomMarker', 'permission request failed: %{public}s', JSON.stringify(err));
    });
  }

  onDestroy(): void {
    // 应用退出时若仍在记录，收尾保存（对应 Android 版 RecordingService.onDestroy）
    TrackRecorder.get().stop().catch(() => {
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'RoomMarker', 'loadContent failed: %{public}s', JSON.stringify(err));
      }
    });
  }
}
