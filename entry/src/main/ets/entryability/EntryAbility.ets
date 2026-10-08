import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Ctx } from '../common/Utils';
import { PERM_MISSING_KEY, requestAndReport } from '../common/Permissions';
import { Store } from '../data/Store';
import { TrackRecorder } from '../sensors/TrackRecorder';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Ctx.ui = this.context;
    Store.init(this.context);

    AppStorage.setOrCreate('rm_recording', false);
    AppStorage.setOrCreate('rm_elapsed', 0);
    AppStorage.setOrCreate('rm_rec_track_name', '');
    // 权限自查的结果（首页靠它显示提示条）。先给空数组，申请完再如实覆盖。
    AppStorage.setOrCreate(PERM_MISSING_KEY, [] as string[]);

    // ⚠️ 2026-10-06 改：原来这里是 `.then(() => hilog.info('location permission granted'))`
    // —— **那是错的**。`requestPermissionsFromUser` 在用户点「拒绝」时同样 resolve，
    // 真正的结果在返回值的 `authResults` 里（0=允许，-1=拒绝）。所以那句日志是**无条件**打的，
    // 拒绝与批准写出一模一样的记录，App 界面上也毫无提示。
    // 后果：2026-10-05 用户带机去城大采集，新包名（hk.edu.cityu.campusnav）被系统当成新 App、
    // 旧授权不继承，全程没有 GPS，白跑一趟。现在改成用返回值，并把缺失项落进 AppStorage 由首页显示。
    requestAndReport(this.context).then((missing: string[]) => {
      AppStorage.setOrCreate(PERM_MISSING_KEY, missing);
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
