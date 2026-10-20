import SwiftUI
import RackyCore

@MainActor struct HumanRequestBadge: View {
    @ObservedObject var center = HumanRequestCenter.shared
    let sessionID: UUID?
    let terminalID: UUID?

    init(sessionID: UUID? = nil, terminalID: UUID? = nil) {
        self.sessionID = sessionID
        self.terminalID = terminalID
    }

    var body: some View {
        let count = center.snapshot.pendingCount(sessionID: sessionID, terminalID: terminalID)
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 17, minHeight: 17)
                .background(Color.orange.opacity(0.8), in: Capsule())
                .accessibilityLabel("\(count) pedido\(count == 1 ? "" : "s") aguardando você")
        }
    }
}

@MainActor struct HumanRequestsView: View {
    @ObservedObject var center = HumanRequestCenter.shared
    @State private var navigationError: String?
    let onOpenTarget: (HumanRequestTarget) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Precisam de você").font(.system(size: 15, weight: .medium))
            if let error = center.errorText {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
            }
            if let navigationError {
                Text(navigationError).font(.system(size: 12)).foregroundStyle(.red)
            }
            let pending = center.snapshot.requests
                .filter { $0.state != .resolved }
                .sorted { $0.createdAt < $1.createdAt }
            if pending.isEmpty {
                Text("Nenhum pedido pendente.").foregroundStyle(.secondary)
            } else {
                List(pending) { request in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(request.summary).font(.system(size: 13))
                        Text("\(request.kind.rawValue) · \(request.createdAt.formatted())")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        HStack {
                            Button("Abrir terminal") {
                                if !onOpenTarget(request.target) {
                                    navigationError = "A sessão ou o terminal deste pedido não está mais disponível. O pedido foi preservado."
                                }
                            }
                            Spacer()
                            Text(request.target.computerID.uuidString).font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .font(.system(size: 13))
        .padding(16)
        .frame(minWidth: 460, minHeight: 340)
    }
}
