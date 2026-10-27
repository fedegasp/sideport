import Foundation

enum IPAContents {

    /// Costruisce l'albero a partire dall'elenco piatto delle voci.
    ///
    /// Gli zip elencano le cartelle solo quando sono state archiviate
    /// esplicitamente, quindi i livelli intermedi si ricavano dai percorsi.
    static func tree(from entries: [IPAEntry]) -> [IPANode] {
        let root = Builder(name: "", path: "")
        for entry in entries {
            let components = entry.path.split(separator: "/").map(String.init)
            guard !components.isEmpty else { continue }
            var node = root
            for (index, component) in components.enumerated() {
                node = node.child(named: component)
                let isLeaf = index == components.count - 1
                if !isLeaf || entry.isDirectory {
                    node.isDirectory = true
                } else {
                    node.size = entry.size
                }
            }
        }
        return root.node().children ?? []
    }

    /// Percorsi da espandere all'apertura: la catena fino al bundle `.app`.
    static func defaultExpansion(in nodes: [IPANode]) -> Set<String> {
        var expanded = Set<String>()
        func visit(_ node: IPANode, ancestors: [String]) {
            guard node.isDirectory else { return }
            let chain = ancestors + [node.id]
            if node.name.hasSuffix(".app") {
                expanded.formUnion(chain)
                return
            }
            for child in node.children ?? [] { visit(child, ancestors: chain) }
        }
        for node in nodes { visit(node, ancestors: []) }
        return expanded
    }

    /// Mappa percorso → nodo, per risolvere una selezione senza riattraversare l'albero.
    static func index(_ nodes: [IPANode]) -> [String: IPANode] {
        var result: [String: IPANode] = [:]
        func visit(_ node: IPANode) {
            result[node.id] = node
            for child in node.children ?? [] { visit(child) }
        }
        for node in nodes { visit(node) }
        return result
    }

    // MARK: - Costruzione

    private final class Builder {
        let name: String
        let path: String
        var size: Int64 = 0
        var isDirectory = false
        private var children: [String: Builder] = [:]
        private var order: [String] = []

        init(name: String, path: String) {
            self.name = name
            self.path = path
        }

        func child(named component: String) -> Builder {
            if let existing = children[component] { return existing }
            let child = Builder(name: component, path: path.isEmpty ? component : path + "/" + component)
            children[component] = child
            order.append(component)
            return child
        }

        func node() -> IPANode {
            guard isDirectory || !order.isEmpty else {
                return IPANode(id: path, name: name, isDirectory: false, size: size, children: nil)
            }
            let kids = order.compactMap { children[$0]?.node() }.sorted(by: Builder.ordering)
            return IPANode(
                id: path,
                name: name,
                isDirectory: true,
                size: kids.reduce(0) { $0 + $1.size },
                children: kids
            )
        }

        /// Prima le cartelle, poi i file, entrambi in ordine naturale.
        private static func ordering(_ lhs: IPANode, _ rhs: IPANode) -> Bool {
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
