import { promptAction } from '@kit.ArkUI';
import { Store } from '../data/Store';
import { TrackRecorder } from '../sensors/TrackRecorder';
import { captureTrackPhoto, deletePhotoFile } from '../sensors/TrackMedia';
import { fmtDuration } from '../common/Utils';
import { PhotoNoteDialog, TrackTagDialog } from './CaptureDialogs';

/**
 * 记录中横幅：拍照 / 打标签 / 停止。
 * 刷新方案沿用本工程 API 21 验证过的「@State heartbeat + ForEach 重建」：
 * AppStorage→@StorageLink 在 NavDestination 场景下不触发刷新，
 * 这里 500ms 自增心跳强制重建横幅，读取最新记录状态。
 */
@Component
export struct RecordingBanner {
  @State heartbeat: number = 0;
  private timer: number = -1;
  private tagDialog: CustomDialogController | null = null;
  private photoDialog: CustomDialogController | null = null;

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
      builder: TrackTagDialog({
        onSave: (tagType: string, note: string): void => {
          const snap = rec.getSnapshot();
          Store.insertTrackTag(rec.getTrackId(), Date.now(), tagType, note,
            snap.latitude, snap.longitude, snap.altitude, snap.headingDeg)
            .then(() => {
              promptAction.showToast({ message: `已记录「${tagType}」标签` });
            })
            .catch(() => {
              promptAction.showToast({ message: '标签保存失败' });
            });
        }
      }),
      customStyle: false
    });
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
        builder: PhotoNoteDialog({
          absPath: cap.absPath,
          onSave: (note: string): void => {
            const snap = rec.getSnapshot();
            Store.insertTrackPhoto(trackId, cap.timeMs, cap.relPath, note,
              snap.latitude, snap.longitude, snap.altitude, snap.headingDeg)
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
        }),
        customStyle: false
      });
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

  build() {
    if (AppStorage.get<boolean>('rm_recording')) {
      ForEach([this.heartbeat], (h: number) => {
        Column({ space: 8 }) {
          Text(`● 正在记录「${AppStorage.get<string>('rm_rec_track_name')}」  ${fmtDuration(AppStorage.get<number>('rm_elapsed') as number)}（切页面不中断）`)
            .fontSize(14)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 10 }) {
            Button('拍照').fontSize(13).layoutWeight(1).onClick(() => {
              this.takePhoto();
            })
            Button('打标签').fontSize(13).layoutWeight(1).onClick(() => {
              this.openTagDialog();
            })
            Button('■ 停止').fontSize(13).layoutWeight(1)
              .fontColor(Color.White)
              .backgroundColor('#E84026')
              .onClick(() => {
                this.stopRecording();
              })
          }.width('100%')
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#330A59F7')
      }, (h: number) => h + '')
    }
  }
}
