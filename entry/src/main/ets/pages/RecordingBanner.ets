import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MarkerType, NodeDraft, PhotoKind, TrackPhotoDraft } from '../data/Entities';
import { Store } from '../data/Store';
import { TrackRecorder } from '../sensors/TrackRecorder';
import { captureTrackPhoto, deletePhotoFile, PhotoCapture } from '../sensors/TrackMedia';
import { fmtDuration } from '../common/Utils';
import { Theme } from '../common/Theme';
import { ThickButton } from '../common/Widgets';
import { SceneryDialog, TrackTagDialog } from './CaptureDialogs';

const TAG = 'RoomMarker';

/**
 * 记录中横幅：记录节点 / 风景照 / 停止。
 *
 * 刷新方案：本工程 API 21 + NavDestination 场景下 AppStorage 通知不会触发重渲染，
 * 而 `if (AppStorage.get(...))` 这类条件读的不是可观察状态，只在组件创建时求值一次。
 * 因此这里用 500ms 定时器把录制状态/名称/时长/采样点数同步进页面本地 @State，
 * 显隐判断写在心跳 ForEach 内部（key 变化会重建子树、重新求值条件）。
 *
 * 采集流程（2026-09-28 改）：
 *  - 记录节点：先选类型+备注+楼层（门/门禁还要选房间）→ 再调相机 → 拍成功才落库。
 *  - 风景照：先写备注（可空）→ 调相机 → 只存照片，不参与节点体系。
 *  拍照之后不再弹任何对话框 —— 原来的实现是「拍完再弹备注框」，而每次都在回调里
 *  new CustomDialogController 覆盖旧实例，导致第二张起相机回来后就报「拍照未完成」。
 *
 * 拍照失败要留下原因：toast 两秒就没了，人在楼道里根本来不及看，所以失败原因同时写进
 * AppStorage 并显示在横幅上（下一次拍成功才清掉），并记一条 hilog。
 */
@Component
export struct RecordingBanner {
  @State heartbeat: number = 0;
  /** 录制状态/名称/时长同步到本地 @State，供 build 当作可观察状态使用 */
  @State recording: boolean = false;
  @State trackName: string = '';
  @State elapsedSec: number = 0;
  @State pointCount: number = 0;
  /** 上一次拍照失败的原因（空字符串 = 没有问题） */
  @State photoError: string = '';
  private timer: number = -1;
  private nodeDialog: CustomDialogController | null = null;
  private sceneryDialog: CustomDialogController | null = null;

  private sync(): void {
    const rec = TrackRecorder.get();
    const on = rec.isRunning();
    this.recording = on;
    const err = AppStorage.get<string>('rm_photo_error');
    this.photoError = err === undefined ? '' : err;
    if (on) {
      const n = AppStorage.get<string>('rm_rec_track_name');
      this.trackName = n === undefined ? '' : n;
      const e = AppStorage.get<number>('rm_elapsed');
      this.elapsedSec = e === undefined ? 0 : e;
      this.pointCount = rec.getPointCount();
    }
  }

  /** 记下拍照失败的原因：横幅上一直显示，同时进 hilog */
  private fail(message: string, e: Error): void {
    const text = `${message}：${e.message}`;
    AppStorage.setOrCreate('rm_photo_error', text);
    this.photoError = text;
    hilog.error(0x0000, TAG, 'photo failed: %{public}s', text);
  }

  private clearError(): void {
    AppStorage.setOrCreate('rm_photo_error', '');
    this.photoError = '';
  }

  aboutToAppear(): void {
    this.sync();
    this.timer = setInterval(() => {
      this.heartbeat++;
      this.sync();
    }, 500);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  /**
   * 对话框控制器延迟到点击时创建、并复用同一个实例：
   * 既避开「成员初始化阶段读不到 props」的坑，也避开「每次新建控制器」的复用问题。
   */
  private ensureDialogs(): void {
    if (this.nodeDialog !== null) {
      return;
    }
    this.nodeDialog = new CustomDialogController({
      builder: TrackTagDialog({
        trackIdProvider: (): number => {
          return TrackRecorder.get().getTrackId();
        },
        onSave: (draft: NodeDraft): void => {
          this.saveNode(draft);
        }
      }),
      customStyle: false
    });
    this.sceneryDialog = new CustomDialogController({
      builder: SceneryDialog({
        onSave: (note: string): void => {
          this.saveScenery(note);
        }
      }),
      customStyle: false
    });
  }

  private requireRunningTrack(): number {
    const rec = TrackRecorder.get();
    if (!rec.isRunning()) {
      promptAction.showToast({ message: '当前没有进行中的轨迹' });
      return -1;
    }
    return rec.getTrackId();
  }

  /** 拍照并把照片挂到节点上（拍照必填：相机取消或失败则不产生节点） */
  private saveNode(draft: NodeDraft): void {
    const rec = TrackRecorder.get();
    const trackId = this.requireRunningTrack();
    if (trackId < 0) {
      return;
    }
    captureTrackPhoto(trackId).then((cap: PhotoCapture | undefined) => {
      if (cap === undefined) {
        // 相机取消：按普通提示处理，不当成错误（否则会跟真正的失败混在一起）
        promptAction.showToast({ message: '没有拍照（已取消）' });
        return;
      }
      // 拍照期间用户可能已停止记录，此时丢弃照片与节点
      if (!rec.isRunning() || rec.getTrackId() !== trackId) {
        deletePhotoFile(cap.absPath);
        promptAction.showToast({ message: '轨迹已停止，节点未记录' });
        return;
      }
      const snap = rec.getSnapshot();
      let tagId = -1;
      let markerFail = '';
      Store.insertTrackTag(trackId, cap.timeMs, draft.tagType, draft.note, draft.floor,
        snap.latitude, snap.longitude, snap.altitude, snap.headingDeg)
        .then((id: number) => {
          tagId = id;
          const photo: TrackPhotoDraft = {
            trackId: trackId,
            kind: PhotoKind.NODE,
            tagId: id,
            timeMs: cap.timeMs,
            filePath: cap.relPath,
            note: draft.note,
            latitude: snap.latitude,
            longitude: snap.longitude,
            altitude: snap.altitude,
            headingDeg: snap.headingDeg
          };
          return Store.insertTrackPhoto(photo);
        })
        .then(() => {
          // 门 / 门禁：往所选房间写一条「前门 / 后门」标记（备注里带「后」算后门）。
          // 标记失败不回滚节点 —— 节点与照片本身是有效的，只是没绑上房间，如实告知即可。
          if (draft.roomId <= 0) {
            return Promise.resolve();
          }
          const markerType: string = draft.note.indexOf('后') >= 0
            ? MarkerType.BACK_DOOR : MarkerType.FRONT_DOOR;
          const markerName: string = draft.note.length > 0 ? draft.note : draft.tagType;
          return Store.insertMarker(draft.roomId, markerName, markerType,
            snap.latitude, snap.longitude, snap.altitude, undefined, snap.pressureHpa)
            .catch((e: Error) => {
              markerFail = e.message;
            });
        })
        .then(() => {
          this.clearError();
          const where = draft.floor.length > 0 ? `（${draft.floor}）` : '';
          if (draft.roomId <= 0) {
            promptAction.showToast({ message: `已记录节点「${draft.tagType}」${where}` });
          } else if (markerFail.length > 0) {
            promptAction.showToast({ message: `节点已保存，但绑定房间失败：${markerFail}` });
          } else {
            promptAction.showToast({
              message: `已记录节点「${draft.tagType}」${where} · 已绑到「${draft.roomName}」`
            });
          }
        })
        .catch((e: Error) => {
          deletePhotoFile(cap.absPath);
          // 照片没落库就把节点撤掉，避免留下「没有照片的节点」
          if (tagId > 0) {
            Store.deleteTrackTag(tagId).catch(() => {
            });
          }
          this.fail('节点保存失败', e);
          promptAction.showToast({ message: `节点保存失败：${e.message}` });
        });
    }).catch((e: Error) => {
      this.fail('拍照未完成', e);
      promptAction.showToast({ message: `拍照未完成：${e.message}` });
    });
  }

  /** 拍风景照：只存照片，不计入节点 */
  private saveScenery(note: string): void {
    const rec = TrackRecorder.get();
    const trackId = this.requireRunningTrack();
    if (trackId < 0) {
      return;
    }
    captureTrackPhoto(trackId).then((cap: PhotoCapture | undefined) => {
      if (cap === undefined) {
        promptAction.showToast({ message: '没有拍照（已取消）' });
        return;
      }
      if (!rec.isRunning() || rec.getTrackId() !== trackId) {
        deletePhotoFile(cap.absPath);
        promptAction.showToast({ message: '轨迹已停止，照片已丢弃' });
        return;
      }
      const snap = rec.getSnapshot();
      const draft: TrackPhotoDraft = {
        trackId: trackId,
        kind: PhotoKind.SCENERY,
        timeMs: cap.timeMs,
        filePath: cap.relPath,
        note: note,
        latitude: snap.latitude,
        longitude: snap.longitude,
        altitude: snap.altitude,
        headingDeg: snap.headingDeg
      };
      Store.insertTrackPhoto(draft).then(() => {
        this.clearError();
        promptAction.showToast({ message: '风景照已保存' });
      }).catch((e: Error) => {
        deletePhotoFile(cap.absPath);
        this.fail('风景照保存失败', e);
        promptAction.showToast({ message: `风景照保存失败：${e.message}` });
      });
    }).catch((e: Error) => {
      this.fail('拍照未完成', e);
      promptAction.showToast({ message: `拍照未完成：${e.message}` });
    });
  }

  private openNodeDialog(): void {
    if (this.requireRunningTrack() < 0) {
      return;
    }
    this.ensureDialogs();
    this.nodeDialog!.open();
  }

  private openSceneryDialog(): void {
    if (this.requireRunningTrack() < 0) {
      return;
    }
    this.ensureDialogs();
    this.sceneryDialog!.open();
  }

  private stopRecording(): void {
    TrackRecorder.get().stop().then(() => {
      promptAction.showToast({ message: '轨迹已保存' });
    }).catch(() => {
    });
  }

  build() {
    // 根节点必须是容器组件；显隐判断要在心跳 ForEach 内部求值
    // （ForEach 的 key 变化会重建子树、重新求值 if），否则开始/停止录制时横幅不会即时出现/消失
    Column() {
      ForEach([this.heartbeat], (h: number) => {
        if (this.recording) {
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Circle({ width: 10, height: 10 }).fill(Theme.REC)
              Text('正在记录').fontSize(12.5).fontWeight(FontWeight.Bold).fontColor(Theme.ON_RED)
              Blank()
              Text(`${this.pointCount} 点`).fontSize(12).fontColor(Theme.ON_RED_SOFT)
            }.width('100%')

            Text(fmtDuration(this.elapsedSec))
              .fontSize(Theme.F_BIG)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.ON_RED)
              .width('100%')

            Text(`${this.trackName} · 切页面不中断`)
              .fontSize(Theme.F_META)
              .fontColor(Theme.ON_RED_SOFT)
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            // 拍照失败的原因留在横幅上（toast 一闪就过，在楼道里根本来不及看），
            // 下一次拍成功或保存成功才清掉
            if (this.photoError.length > 0) {
              Text(this.photoError)
                .fontSize(11)
                .fontColor(Theme.ON_RED)
                .backgroundColor(Theme.RED_DEEP)
                .borderRadius(10)
                .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                .width('100%')
            }

            Row({ space: 8 }) {
              Column() {
                ThickButton({
                  label: '记录节点',
                  kind: 'onred',
                  compact: true,
                  onTap: (): void => {
                    this.openNodeDialog();
                  }
                })
              }.layoutWeight(1.5)

              Column() {
                ThickButton({
                  label: '风景照',
                  kind: 'onred',
                  compact: true,
                  onTap: (): void => {
                    this.openSceneryDialog();
                  }
                })
              }.layoutWeight(1)

              Column() {
                ThickButton({
                  label: '■ 停止',
                  kind: 'danger',
                  compact: true,
                  onTap: (): void => {
                    this.stopRecording();
                  }
                })
              }.width(84)
            }.width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Theme.RED)
          .borderRadius(Theme.R_HERO)
          .border({ width: { bottom: 5 }, color: { bottom: Theme.RED_DEEP } })
          .margin({ left: Theme.PAD, right: Theme.PAD, top: 4, bottom: 4 })
        }
      }, (h: number) => h + '')
    }.width('100%')
  }
}
