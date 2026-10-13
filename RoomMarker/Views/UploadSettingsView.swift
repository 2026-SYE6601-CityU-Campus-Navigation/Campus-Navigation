import SwiftUI

struct UploadSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var endpoint: String
    @State private var token: String
    @State private var fieldName: String
    @State private var errorMessage: String?

    init() {
        let value = ZIPUploadSettings.load()
        _endpoint = State(initialValue: value.endpoint)
        _token = State(initialValue: value.token)
        _fieldName = State(initialValue: value.fieldName)
    }

    var body: some View {
        Form {
            Section("接收端") {
                TextField("https://…/upload", text: $endpoint)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("上传令牌（可选）", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("文件字段名", text: $fieldName)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section {
                Text("令牌保存在本机钥匙串，不写入数据库、JSON、ZIP 或仓库。优先使用 HTTPS 和私有接收端；ZIP 含真实轨迹与现场照片。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("局域网 HTTP 仅用于受控测试环境，首次连接可能出现系统本地网络权限提示。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("上传设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    do {
                        try ZIPUploadSettings.save(.init(endpoint: endpoint, token: token, fieldName: fieldName))
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }
            }
        }
        .persistenceErrorAlert($errorMessage)
    }
}
