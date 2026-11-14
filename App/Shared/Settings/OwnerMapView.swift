import SwiftUI
import MergeableCore

struct OwnerMapView: View {
    @EnvironmentObject var store: AccountStore
    @State private var newOwner = ""

    var body: some View {
        List {
            if !store.ambiguousOwners.isEmpty {
                Section {
                    ForEach(store.ambiguousOwners) { row($0) }
                } header: { Text("Assign these") } footer: { Text("Two accounts claim these owners. Writes there are refused until you choose one.") }
            }
            Section("Owners") {
                ForEach(store.ownerClaims.filter { !$0.isAmbiguous }) { row($0) }
            }
            Section("Add an owner by hand") {
                HStack {
                    TextField("Organization or user", text: $newOwner)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    Button("Add") { if let first = store.accounts.first { store.assign(owner: newOwner, to: first.id); newOwner = "" } }
                        .disabled(newOwner.isEmpty || store.accounts.isEmpty)
                }
            }
        }
        .navigationTitle("Owner map")
    }

    private func row(_ c: OwnerClaim) -> some View {
        HStack {
            Text(c.owner)
            if c.isAmbiguous { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Primer.attention) }
            Spacer()
            Picker("Account", selection: Binding(get: { c.assigned }, set: { store.assign(owner: c.owner, to: $0) })) {
                Text(c.claimedBy.count == 1 ? "Automatic" : "Choose…").tag(AccountID?.none)
                ForEach(store.accounts) { a in Text(a.label).tag(AccountID?.some(a.id)) }
            }
            .labelsHidden()
        }
    }
}
