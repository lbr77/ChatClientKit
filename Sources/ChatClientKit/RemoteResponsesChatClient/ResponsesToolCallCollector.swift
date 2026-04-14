//
//  ResponsesToolCallCollector.swift
//  ChatClientKit
//
//  Created by Henri on 2025/12/2.
//

import Foundation

class ResponsesToolCallCollector {
    struct Pending {
        var id: String
        var name: String
        var arguments: String
    }

    var storage: [String: Pending] = [:]
    var order: [String] = []
    var aliases: [String: String] = [:]

    func observe(item: ResponsesOutputItem) {
        guard item.isToolCall else { return }
        let identifier = canonicalIdentifier(itemID: item.id, callID: item.callId)
        if let itemID = item.id {
            aliases[itemID] = identifier
        }
        if let callID = item.callId {
            aliases[callID] = identifier
        }

        var pending = storage[identifier] ?? Pending(id: identifier, name: "", arguments: "")
        if let itemID = item.id, itemID != identifier, let existing = storage.removeValue(forKey: itemID) {
            pending = merge(existing, into: pending)
            order.removeAll { $0 == itemID }
        }
        if let name = item.resolvedToolName {
            pending.name = name
        }
        if let arguments = item.resolvedToolArguments {
            pending.arguments = arguments
        }
        storage[identifier] = pending
        if !order.contains(identifier) {
            order.append(identifier)
        }
    }

    func appendDelta(
        for itemID: String?,
        name: String?,
        delta: String?,
        outputIndex _: Int?
    ) {
        guard let itemID else { return }
        let identifier = canonicalIdentifier(itemID: itemID, callID: nil)
        aliases[itemID] = identifier
        var pending = storage[identifier] ?? Pending(id: identifier, name: name ?? "", arguments: "")
        if let name, pending.name.isEmpty {
            pending.name = name
        }
        if let delta {
            pending.arguments.append(delta)
        }
        storage[identifier] = pending
        if !order.contains(identifier) {
            order.append(identifier)
        }
    }

    func finalize(
        for itemID: String?,
        name: String?,
        arguments: String?,
        outputIndex _: Int?
    ) {
        guard let itemID else { return }
        let identifier = canonicalIdentifier(itemID: itemID, callID: nil)
        aliases[itemID] = identifier
        var pending = storage[identifier] ?? Pending(id: identifier, name: name ?? "", arguments: "")
        if let name {
            pending.name = name
        }
        if let arguments {
            pending.arguments = arguments
        }
        storage[identifier] = pending
        if !order.contains(identifier) {
            order.append(identifier)
        }
    }

    func finalizeRequests() -> [ToolRequest] {
        order.map { id in
            let pending = storage[id] ?? Pending(id: id, name: "", arguments: "")
            return ToolRequest(id: pending.id, name: pending.name, args: pending.arguments)
        }
    }

    var hasPendingRequests: Bool {
        !storage.isEmpty
    }

    func canonicalIdentifier(itemID: String?, callID: String?) -> String {
        if let callID {
            if let alias = aliases[callID] {
                return alias
            }
            return callID
        }
        if let itemID, let alias = aliases[itemID] {
            return alias
        }
        if let itemID {
            return itemID
        }
        return UUID().uuidString
    }

    func merge(_ source: Pending, into destination: Pending) -> Pending {
        Pending(
            id: destination.id,
            name: destination.name.isEmpty ? source.name : destination.name,
            arguments: destination.arguments.isEmpty ? source.arguments : destination.arguments
        )
    }
}
