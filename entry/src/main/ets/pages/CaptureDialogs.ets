import { TrackTagType, trackTagOptions } from '../data/Entities';

/** 轨迹途中打标签对话框：类型（厕所/楼梯/门/门禁/电梯/教室）+ 备注 */
@CustomDialog
export struct TrackTagDialog {
  controller?: CustomDialogController;
  onSave?: (tagType: string, note: string) => void;
  @State note: string = '';
  @State tagType: string = TrackTagType.TOILET;
  @State tagIndex: number = 0;

  build() {
    Column({ space: 12 }) {
      Text('打标签').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
      Text('标记当前位置的关键信息，保存时自动关联 定位+朝向 快照')
        .fontSize(12)
        .fontColor('#99000000')
        .width('100%')
      Select(trackTagOptions())
        .selected(this.tagIndex)
        .onSelect((index: number, value: string) => {
          this.tagIndex = index;
          this.tagType = value;
        })
        .width('100%')
      TextInput({ placeholder: '备注（如：3楼男厕，门口右手边）' })
        .onChange((v: string) => {
          this.note = v;
        })
      Row({ space: 12 }) {
        Button('取消').onClick(() => {
          this.controller?.close();
        })
        Button('保存标签').onClick(() => {
          this.controller?.close();
          if (this.onSave) {
            this.onSave(this.tagType, this.note.trim());
          }
        })
      }.width('100%').justifyContent(FlexAlign.End)
    }.padding(16).width('100%')
  }
}

/** 照片备注对话框：预览 + 备注，保存并关联 或 丢弃 */
@CustomDialog
export struct PhotoNoteDialog {
  controller?: CustomDialogController;
  absPath: string = '';
  onSave?: (note: string) => void;
  onDiscard?: () => void;
  @State note: string = '';

  build() {
    Column({ space: 12 }) {
      Text('照片已拍摄').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
      Image('file://' + this.absPath)
        .width('100%')
        .height(220)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
      TextInput({ placeholder: '备注（如：教室门口视角，前方是楼梯）' })
        .onChange((v: string) => {
          this.note = v;
        })
      Row({ space: 12 }) {
        Button('丢弃').fontColor('#E84026').onClick(() => {
          this.controller?.close();
          if (this.onDiscard) {
            this.onDiscard();
          }
        })
        Button('保存并关联').onClick(() => {
          this.controller?.close();
          if (this.onSave) {
            this.onSave(this.note.trim());
          }
        })
      }.width('100%').justifyContent(FlexAlign.End)
    }.padding(16).width('100%')
  }
}
