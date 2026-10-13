import Foundation
import SwiftData
import Testing
@testable import RoomMarker

@Suite("Offline batch 3 catalog and idempotent import", .serialized)
@MainActor
struct OfflineBatch3CatalogTests {
    @Test("Parser preserves empty fields and rejects ambiguous formats", arguments: [",", "|", "\t", "、"])
    func parser(_ delimiter: String) {
        let valid = [" AC2 ", "1503", "Synthetic classroom", "", "1F"].joined(separator: delimiter)
        let result = ClassroomImportParser.parse("# comment\n\(valid)\nAC1,,Missing code\nAC1 LT-1 Guess\n\"AC1\",X,Quoted\n")
        #expect(result.rows == [.init(building: "AC2", code: "1503", name: "Synthetic classroom", floor: "1/F")])
        #expect(result.errors.count == 3)
        #expect(ClassroomImportParser.parse("\(valid)\r\nbad").errors.first?.hasPrefix("第 2 行") == true)
    }

    @Test("Conservative floor normalization", arguments: [
        [" 1F ", "1/F"], ["2/f", "2/F"], ["GF", "G/F"], ["lg/f", "LG/F"],
        ["B1", "B1"], ["M", "M"], ["", ""], ["3楼", "3楼"],
    ])
    func floors(_ pair: [String]) { #expect(CampusCatalog.floor(pair[0]) == pair[1]) }

    @Test("Reference catalog is bounded and candidates explicitly marked unverified")
    func references() {
        #expect(CampusCatalog.buildings.count == 11 && Set(CampusCatalog.buildings.map(\.id)).count == 11)
        #expect(CampusCatalog.candidateClassrooms.count == 19)
        #expect(CampusCatalog.candidateClassrooms.allSatisfy { $0.note.contains("候选") && $0.note.contains("现场核对") })
        #expect(CampusCatalog.building("YEUNG")?.id == "ac1")
        #expect(CampusCatalog.building("AC1 三楼") == nil) // No broad prefix matching.
        #expect(ClassroomImportParser.parse(String(repeating: "x", count: 500_001)).rows.isEmpty)
    }

    @Test("Preview is read-only; repeated import retains IDs and adds nothing")
    func idempotent() throws {
        let c = try RoomMarkerModelContainer.make(inMemory: true)
        let store = CatalogImportStore(context: c.mainContext)
        let plan = try store.preview(text: "", includeBuildings: true, includeCandidates: true)
        #expect(plan.newAreas.count == 11 && plan.newRooms.count == 19 && plan.conflicts.isEmpty)
        #expect(try c.mainContext.fetch(FetchDescriptor<Area>()).isEmpty && !c.mainContext.hasChanges)
        #expect(try store.apply(plan, createdAt: 1000) == 30)
        let before = try store.state()
        let repeated = try store.preview(text: "", includeBuildings: true, includeCandidates: true)
        #expect(!repeated.canApply && repeated.conflicts.isEmpty && repeated.skipped.count == 19)
        #expect(try store.apply(repeated) == 0)
        #expect(try store.state() == before)
        #expect(try c.mainContext.fetch(FetchDescriptor<Room>()).allSatisfy { $0.latitude == nil && $0.markers.isEmpty })
    }

    @Test("Import keys survive user renames without overwriting metadata or sensors")
    func renamedImportedData() throws {
        let c = try RoomMarkerModelContainer.make(inMemory: true)
        let store = CatalogImportStore(context: c.mainContext)
        let row = ClassroomImportRow(building: "AC2", code: "1503", name: "Synthetic", floor: "1/F")
        try store.apply(store.preview(rows: [row]))
        let room = try #require(c.mainContext.fetch(FetchDescriptor<Room>()).first)
        let area = try #require(room.area)
        area.name = "User building"; area.category = "测试集"
        room.code = "Custom"; room.name = "User room"; room.note = "Preserve"; room.pressureHpa = 1008
        try c.mainContext.save()
        let before = try store.state()
        let again = try store.preview(rows: [row])
        #expect(again.skipped.count == 1 && !again.canApply && again.conflicts.isEmpty)
        try store.apply(again)
        #expect(try store.state() == before && room.pressureHpa == 1008)
    }

    @Test("Same code in different buildings is valid; normalized aliases within one building deduplicate")
    func localUniqueness() throws {
        let c = try RoomMarkerModelContainer.make(inMemory: true)
        let store = CatalogImportStore(context: c.mainContext)
        let rows: [ClassroomImportRow] = [.init(building: "AC1", code: "R1", name: "One"),
            .init(building: " YEUNG ", code: "r 1", name: " One "),
            .init(building: "AC2", code: "R1", name: "One")]
        let plan = try store.preview(rows: rows)
        #expect(plan.newAreas.count == 2 && plan.newRooms.count == 2 && plan.skipped.count == 1)
        try store.apply(plan)
        #expect(Set(try c.mainContext.fetch(FetchDescriptor<Room>()).compactMap { $0.area?.id }).count == 2)
    }

    @Test("Ambiguous duplicate areas block import without merging UUIDs")
    func duplicateAreas() throws {
        let c = try RoomMarkerModelContainer.make(inMemory: true)
        for name in ["AC1", "AC1 楊建文學術樓"] { c.mainContext.insert(Area(name: name, createdAt: 1)) }
        try c.mainContext.save()
        let store = CatalogImportStore(context: c.mainContext)
        let before = try store.state()
        let plan = try store.preview(rows: [.init(building: "AC1", code: "X", name: "Synthetic")])
        #expect(!plan.canApply && !plan.conflicts.isEmpty)
        #expect(throws: CatalogImportError.conflicts) { try store.apply(plan) }
        #expect(try store.state() == before)
    }

    @Test("Contradictory rows and bad lines block entire batch", arguments: ["code", "name", "invalid"])
    func conflicts(_ kind: String) throws {
        let c = try RoomMarkerModelContainer.make(inMemory: true)
        let store = CatalogImportStore(context: c.mainContext)
        let second = kind == "code" ? "AC1,X,Changed" : kind == "name" ? "AC1,Y,Same" : "bad"
        let plan = try store.preview(text: "AC1,X,Same\n\(second)", includeBuildings: false, includeCandidates: false)
        #expect(!plan.canApply && !plan.conflicts.isEmpty)
        #expect(throws: CatalogImportError.conflicts) { try store.apply(plan) }
        #expect(try c.mainContext.fetch(FetchDescriptor<Area>()).isEmpty)
    }

    @Test("Legacy same-name room is not overwritten or assigned an inferred code/category")
    func legacyConflict() throws {
        let c = try RoomMarkerModelContainer.make(inMemory: true)
        let data = Phase2DataStore(context: c.mainContext)
        let a = try data.createArea(name: "AC1", note: "Historical")
        let r = try data.createRoom(name: "Same", note: "Historical", area: a)
        r.latitude = 0; r.pressureHpa = 1008
        let marker = try data.createMarker(room: r, name: "Old door", markerType: .frontDoor)
        let store = CatalogImportStore(context: c.mainContext)
        let before = try store.state()
        let plan = try store.preview(rows: [.init(building: "AC1", code: "X", name: "Same")])
        #expect(plan.conflicts.count == 1 && plan.newRooms.isEmpty)
        #expect(try store.state() == before && a.category.isEmpty && a.catalogKey == nil)
        #expect(r.code.isEmpty && r.latitude == 0 && r.pressureHpa == 1008 && r.markers.first?.id == marker.id)
    }

    @Test("Stale preview cannot import against changed catalog")
    func stalePreview() throws {
        let c = try RoomMarkerModelContainer.make(inMemory: true)
        let store = CatalogImportStore(context: c.mainContext)
        let plan = try store.preview(rows: [.init(building: "AC1", code: "X", name: "Synthetic")])
        _ = try Phase2DataStore(context: c.mainContext).createArea(name: "AC1", note: "Created after preview")
        #expect(throws: CatalogImportError.stalePreview) { try store.apply(plan) }
        #expect(try c.mainContext.fetch(FetchDescriptor<Room>()).isEmpty)
    }

    @Test("Failure rolls back new building, room and inverse arrays; retry stays idempotent")
    func rollback() throws {
        let c = try RoomMarkerModelContainer.make(inMemory: true)
        let area = try Phase2DataStore(context: c.mainContext).createArea(name: "AC1", note: "Keep")
        let failure = Stage4SaveFailure(); failure.enabled = true
        let store = CatalogImportStore(context: c.mainContext) {
            if failure.enabled { throw Stage4Failure.save }; try $0.save()
        }
        let plan = try store.preview(rows: [.init(building: "AC1", code: "X", name: "Synthetic A"),
                                            .init(building: "AC2", code: "Y", name: "Synthetic B")])
        #expect(throws: Stage4Failure.save) { try store.apply(plan) }
        #expect(area.rooms.isEmpty && !c.mainContext.hasChanges)
        #expect(try store.state() == plan.baseline)
        failure.enabled = false
        try store.apply(plan)
        #expect(area.rooms.count == 1 && area.category.isEmpty && area.catalogKey == nil)
    }

    @Test("Import refuses unrelated unsaved changes")
    func pendingEdits() throws {
        let c = try RoomMarkerModelContainer.make(inMemory: true)
        let store = CatalogImportStore(context: c.mainContext)
        let plan = try store.preview(rows: [], includeBuildings: true)
        c.mainContext.insert(Area(name: "Unsaved", createdAt: 1))
        #expect(throws: CatalogImportError.pendingChanges) { try store.apply(plan) }
        #expect(c.mainContext.hasChanges)
    }
}
