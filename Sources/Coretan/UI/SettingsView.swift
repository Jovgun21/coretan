import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var config = Settings.shared.ai
    @State private var apiKey = Keychain.get("coretan.ai.key") ?? ""
    @State private var meter = UsageMeter.shared
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server AI (OpenAI-compatible)") {
                    TextField("Base URL", text: $config.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Model chat", text: $config.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Model transkripsi", text: $config.transcriptionModel)
                        .textInputAutocapitalization(.never)
                    TextField("Model gambar", text: $config.imageModel)
                        .textInputAutocapitalization(.never)
                    SecureField("API key", text: $apiKey)
                }
                Section("Kuota AI") {
                    Stepper("Batas bulanan: \(config.monthlyCreditLimit)", value: $config.monthlyCreditLimit, in: 50...20000, step: 50)
                    HStack { Text("Terpakai"); Spacer(); Text("\(meter.used)") }
                    HStack { Text("Sisa"); Spacer(); Text("\(meter.remaining)") }
                    ForEach(meter.byFeature.sorted(by: { $0.value > $1.value }), id: \.key) { k, v in
                        HStack { Text(k).font(.caption).foregroundStyle(.secondary); Spacer(); Text("\(v)").font(.caption) }
                    }
                    Button("Reset pemakaian", role: .destructive) { UsageMeter.shared.reset() }
                }
                Section("Privasi") {
                    Text("Semua catatan, tinta, audio dan PDF disimpan lokal di perangkat. Hanya permintaan AI yang keluar, dan hanya saat kamu menekan tombol.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Hapus semua data", role: .destructive) { wipe() }
                }
                if saved {
                    Section { Label("Tersimpan", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            .navigationTitle("Pengaturan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Simpan") { save() } }
            }
        }
    }

    private func save() {
        Settings.shared.ai = config
        Keychain.set(apiKey, for: "coretan.ai.key")
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { saved = false }
    }

    private func wipe() {
        let fm = FileManager.default
        try? fm.removeItem(at: DocumentStore.shared.rootURL)
        Keychain.delete("coretan.ai.key")
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
    }
}
