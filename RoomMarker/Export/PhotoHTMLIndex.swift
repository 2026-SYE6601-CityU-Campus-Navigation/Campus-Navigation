import Foundation

nonisolated enum PhotoHTMLIndex {
    static func make(manifest: ExportV3Manifest, tracks: [ExportV3Track]) throws -> Data {
        var html = """
        <!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
        <title>RoomMarker 照片索引</title><style>body{font:16px system-ui;max-width:960px;margin:2rem auto;padding:0 1rem}article{border:1px solid #aaa;padding:1rem;margin:1rem 0;overflow-wrap:anywhere}img{max-width:100%;max-height:420px}small{display:block}a{color:#1765ad}</style></head><body>
        <h1>RoomMarker 照片索引</h1><p>离线查看：请先在电脑解压 ZIP，保持目录结构。此页不访问网络、不执行脚本；JSON 是完整数据依据。照片、备注和原始 EXIF 可能含敏感信息，请谨慎分享。</p>
        """
        html += "<p>范围：\(escape(manifest.scope.name)) · 轨迹 \(tracks.count)</p>"
        for track in tracks {
            html += "<section><h2>\(escape(track.name))</h2><small>Track \(escape(track.id))</small>"
            if track.photos.isEmpty { html += "<p>无照片</p>" }
            for photo in track.photos {
                guard ArchivePathValidator.isSafe(photo.file), photo.file.hasPrefix("photos/\(track.id)/"),
                      photo.file.hasSuffix(".jpg") else { throw ExportV3Error.invalid("HTML photo path") }
                // URL-encode *each* path component, then HTML-escape the attribute.
                // A filename containing %, #, quotes or ? cannot become a URL directive.
                let url = photo.file.split(separator: "/").map {
                    String($0).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
                }.joined(separator: "/")
                let tag = track.tags.first { $0.id == photo.tagId }
                let kind = photo.kind == "node" ? "节点照片" : photo.kind == "scenery" ? "独立风景" : "历史独立照片"
                html += "<article><h3>\(escape(kind)) · \(escape(tag?.tagType ?? ""))</h3>"
                html += "<a href=\"\(escape(url))\"><img loading=\"lazy\" src=\"\(escape(url))\" alt=\"轨迹照片\"></a>"
                html += "<p>\(escape(photo.note))</p><small>Photo \(escape(photo.id)) · UTC ms \(photo.timeMs)</small>"
                if let tag {
                    let area = manifest.areas.first { $0.id == tag.areaId }
                    html += "<p>\(escape(area?.name ?? tag.areaState)) · \(escape(tag.floor)) · \(escape(tag.note))</p>"
                    if let room = tag.roomBinding {
                        html += "<p>\(escape(room.codeSnapshot)) · \(escape(room.nameSnapshot)) · \(escape(room.doorRole ?? "")) · \(escape(room.status))</p>"
                    }
                }
                html += "<small>\(photo.byteCount) bytes · SHA-256 \(escape(photo.sha256))</small></article>"
            }
            html += "</section>"
        }
        html += "</body></html>"
        return Data(html.utf8)
    }

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
