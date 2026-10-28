import Foundation

struct TabGroup: Equatable {
    var id: UUID
    var name: String
    var members: [UUID]
}

final class TabGroupStore {
    private(set) var groups: [TabGroup] = []

    @discardableResult
    func create(name: String, member: UUID? = nil) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? uniqueName("分组") : uniqueName(trimmed)
        let id = UUID()
        groups.append(TabGroup(id: id, name: resolved, members: []))
        if let member {
            add(member, to: id)
        }
        return id
    }

    @discardableResult
    func rename(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = groups.firstIndex(where: { $0.id == id }) else {
            return false
        }
        groups[index].name = trimmed
        return true
    }

    func delete(_ id: UUID) {
        groups.removeAll { $0.id == id }
    }

    func move(_ id: UUID, to index: Int) {
        guard let from = groups.firstIndex(where: { $0.id == id }) else { return }
        let item = groups.remove(at: from)
        groups.insert(item, at: min(max(0, index), groups.count))
    }

    func add(_ session: UUID, to group: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == group }) else { return }
        remove(session)
        guard let index = groups.firstIndex(where: { $0.id == group }) else { return }
        if groups[index].members.contains(session) == false {
            groups[index].members.append(session)
        }
    }

    func remove(_ session: UUID) {
        for index in groups.indices where groups[index].members.contains(session) {
            groups[index].members.removeAll { $0 == session }
        }
    }

    func groupID(of session: UUID) -> UUID? {
        groups.first { $0.members.contains(session) }?.id
    }

    func uniqueName(_ base: String) -> String {
        let taken = Set(groups.map(\.name))
        if taken.contains(base) == false {
            return base
        }
        var n = 2
        while taken.contains("\(base) \(n)") {
            n += 1
        }
        return "\(base) \(n)"
    }
}
