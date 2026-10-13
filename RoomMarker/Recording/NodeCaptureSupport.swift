import Foundation
import UIKit

nonisolated enum NodeJPEGValidation {
    static func isReadable(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xD8]) && data.suffix(2).elementsEqual([0xFF, 0xD9]) &&
            UIImage(data: data) != nil
    }
}

@MainActor
enum NodeCameraAccess {
    static func authorize(_ camera: any CameraServicing) async throws {
        let authorization = camera.authorizationState == .notDetermined
            ? await camera.requestAuthorization() : camera.authorizationState
        guard authorization == .authorized else {
            throw TrackMediaError.captureFailed("相机权限不可用，请在系统设置中检查。未创建节点或照片。")
        }
        guard camera.isCameraAvailable else {
            throw TrackMediaError.captureFailed("此设备没有可用相机。未创建节点或照片。")
        }
    }
}

// In-memory only. Frozen when the camera returns, before notes/location edits.
struct CapturedTrackPhoto: Equatable, Sendable {
    let id: UUID
    let trackID: UUID
    let jpegData: Data
    let capturedAt: Int64
    let metadata: TrackCaptureMetadata
}

enum NodeCaptureError: LocalizedError, Equatable {
    case invalidImage
    case changedSession
    case alreadySaved
    case invalidAssociation
    case nodePhotoRequiresNodeDeletion
    case compensationPending
    case areaUnavailable
    case invalidSensorMetadata

    var errorDescription: String? {
        switch self {
        case .invalidImage: "相机返回的图像不可读取，未创建节点或照片。"
        case .changedSession: "原轨迹已经结束或切换，请重新拍照。"
        case .alreadySaved: "这次拍摄已经保存，请勿重复保存。"
        case .invalidAssociation: "节点照片关系不完整或不属于同一轨迹，操作已停止。"
        case .nodePhotoRequiresNodeDeletion: "节点照片不能单独删除，请删除整个节点及其照片。"
        case .compensationPending: "保存失败，临时照片清理尚未完成。请点“重试照片清理”或重新打开应用后检查。"
        case .areaUnavailable: "所选区域已不可用，请重新选择区域或明确选择“未分区”。不会自动改存到其他区域。"
        case .invalidSensorMetadata: "采集精度或气压值无效，未保存。请重新采集。"
        }
    }
}

@MainActor
protocol TrackNodePersisting: AnyObject {
    func createNode(
        id: UUID, tag: TrackTagDraft, photo: TrackPhotoDraft, for track: Track
    ) throws -> TrackTag
    func deleteNode(_ tag: TrackTag) throws
}

enum NodePhotoAssociation {
    static func isOwnedFilePath(_ path: String, trackID: UUID) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0] == "photos" &&
            parts[1] == trackID.uuidString.lowercased() &&
            !parts[2].isEmpty && parts[2] != "." && parts[2] != ".." &&
            !path.contains("\\") && parts[2].hasSuffix(".jpg")
    }

    @MainActor
    static func photo(for tag: TrackTag) throws -> TrackPhoto {
        guard tag.isNode, let track = tag.track else {
            throw NodeCaptureError.invalidAssociation
        }
        let linked = track.photos.filter { $0.tagID == tag.id }
        guard linked.count == 1, let photo = linked.first,
              photo.isNodePhoto, photo.track?.id == track.id,
              isOwnedFilePath(photo.filePath, trackID: track.id) else {
            throw NodeCaptureError.invalidAssociation
        }
        return photo
    }
}
