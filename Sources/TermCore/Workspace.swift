import Foundation
import SwiftTerm

public final class Workspace {
    private var order: [Int] = []
    private var members: [Int: [Pane]] = [:]
    private var focusId: [Int: Int] = [:]
    private var nextTab = 1
    private var nextPane = 1
    public private(set) var activeTab: Int?

    public init() {}

    public var tabs: [Int] { order }

    public func openTab() -> Int {
        let id = nextTab
        nextTab += 1
        let pane = makePane()
        members[id] = [pane]
        focusId[id] = pane.id
        order.append(id)
        activeTab = id
        pane.start()
        return id
    }

    public func closeTab(_ id: Int) {
        guard let panes = members.removeValue(forKey: id) else { return }
        focusId[id] = nil
        order.removeAll { $0 == id }
        if activeTab == id { activeTab = order.last }
        panes.forEach { $0.terminate() }
    }

    public func focus(tab: Int) {
        guard members[tab] != nil else { return }
        activeTab = tab
    }

    public func split(_ tab: Int) -> Int? {
        guard members[tab] != nil else { return nil }
        let pane = makePane()
        members[tab, default: []].append(pane)
        focusId[tab] = pane.id
        pane.start()
        return pane.id
    }

    public func panes(in tab: Int) -> [Int] {
        members[tab]?.map(\.id) ?? []
    }

    public func pane(_ id: Int) -> Pane? {
        // ponytail: linear scan, index by pane id if tab count grows
        for panes in members.values {
            if let found = panes.first(where: { $0.id == id }) { return found }
        }
        return nil
    }

    public func send(tab: Int, _ text: String) {
        guard let id = focusId[tab], let pane = pane(id) else { return }
        pane.send(text)
    }

    public func focus(pane paneId: Int) {
        for (tab, panes) in members where panes.contains(where: { $0.id == paneId }) {
            focusId[tab] = paneId
            return
        }
    }

    private func makePane() -> Pane {
        let pane = Pane(id: nextPane)
        nextPane += 1
        return pane
    }
}
