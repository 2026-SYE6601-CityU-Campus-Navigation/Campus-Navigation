import Foundation

// Local reference catalog, aligned with Harmony Campus/Classrooms at a54f5cb.
// Not an official complete campus inventory. Imports require user confirmation.
struct CampusBuilding: Equatable, Identifiable {
    let id: String
    let name: String
    let note: String
}

enum CampusCatalog {
    static let buildings: [CampusBuilding] = [
        .init(id: "ac1", name: "AC1 楊建文學術樓", note: "Yeung Kin Man Academic Building · 邵逸夫圖書館在此樓"),
        .init(id: "ac2", name: "AC2 李達三葉耀珍學術樓", note: "Li Dak Sum Yip Yio Chin Academic Building"),
        .init(id: "ac3", name: "AC3 劉鳴煒學術樓", note: "Lau Ming Wai Academic Building"),
        .init(id: "boc", name: "BOC 中國銀行（香港）綜合樓", note: "Bank of China (Hong Kong) Complex"),
        .init(id: "mmw", name: "MMW 蒙民偉樓", note: "Mong Man Wai Building"),
        .init(id: "fyw", name: "FYW 方潤華樓", note: "Fong Yun Wah Building"),
        .init(id: "cmc", name: "CMC 邵逸夫創意媒體中心", note: "Run Run Shaw Creative Media Centre"),
        .init(id: "cyc", name: "鄭翼之樓", note: "Cheng Yick-chi Building"),
        .init(id: "aeb", name: "學術交流大樓", note: "Academic Exchange Building"),
        .init(id: "tyb", name: "桃源樓", note: "To Yuen Building"),
        .init(id: "jcoh", name: "賽馬會健康一體化大樓", note: "Jockey Club One Health Tower"),
    ]
    static let categories = ["", "城市大学", "测试集"]
    static let floors = ["LG/F", "G/F"] + (1...8).map { "\($0)/F" }

    static func key(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.filter { !$0.isWhitespace }.lowercased()
    }

    static func building(_ input: String) -> CampusBuilding? {
        let k = key(input)
        let aliases = ["yeung": "ac1", "li": "ac2", "lau": "ac3"]
        return buildings.first { $0.id == (aliases[k] ?? k) || key($0.name) == k }
    }

    static func floor(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let k = key(trimmed).uppercased()
        if ["G", "GF", "G/F"].contains(k) { return "G/F" }
        if ["LG", "LGF", "LG/F"].contains(k) { return "LG/F" }
        if k.range(of: "^[0-9]+/?F$", options: .regularExpression) != nil {
            return k.replacingOccurrences(of: "/", with: "").dropLast() + "/F"
        }
        return trimmed // B1, mezzanine, etc. are not guessed or converted.
    }

    static var candidateClassrooms: [ClassroomImportRow] {
        (1...18).map {
            .init(building: "AC1", code: "LT-\($0)", name: "讲堂 \($0)", floor: "4/F",
                  note: "候选目录，编号由鸿蒙清单推导；须现场核对，不代表已采集")
        } + [.init(building: "BOC", code: "LT401", name: "讲堂 401", floor: "",
                   note: "鸿蒙候选目录；须现场核对，不代表已采集")]
    }
}

struct ClassroomImportRow: Equatable {
    let building: String
    let code: String
    let name: String
    var floor: String = ""
    var note: String = ""
}

struct ClassroomParseResult {
    var rows: [ClassroomImportRow] = []
    var errors: [String] = []
}

enum ClassroomImportParser {
    // Explicit delimiter format (not quoted CSV): building, code, name, note?, floor?.
    // Empty columns are preserved. Reject extra/quoted columns, never silently shift fields.
    static func parse(_ text: String) -> ClassroomParseResult {
        var result = ClassroomParseResult()
        guard text.utf8.count <= 500_000 else {
            result.errors = ["清单过大，请分批导入（最多 500 KB）。"]; return result
        }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for (offset, raw) in lines.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") { continue }
            let delimiter = ["\t", "|", ",", "、"].first { line.contains($0) }
            let fields = delimiter.map { line.components(separatedBy: $0) } ?? []
            let f = fields.map { $0.trimmingCharacters(in: .whitespaces) }
            guard (3...5).contains(f.count), !f[0].isEmpty, !f[1].isEmpty, !f[2].isEmpty,
                  !line.contains("\""), !f.contains(where: { $0.count > 200 }) else {
                result.errors.append("第 \(offset + 1) 行格式无效（建筑、代码、名称必填；不支持引号 CSV）。")
                continue
            }
            result.rows.append(.init(building: f[0], code: f[1], name: f[2],
                                     floor: f.count > 4 ? CampusCatalog.floor(f[4]) : "",
                                     note: f.count > 3 ? f[3] : ""))
        }
        if result.rows.count > 2_000 {
            result.rows = []; result.errors.append("每批最多 2000 个教室。")
        }
        return result
    }
}
