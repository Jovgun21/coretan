import SwiftUI

/// App root: library with search, study and settings entry points.
struct ContentView: View {
    @State private var showSearch = false
    @State private var showStudy = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            LibraryView(onSearch: { showSearch = true },
                        onStudy: { showStudy = true },
                        onSettings: { showSettings = true })
        }
        .sheet(isPresented: $showSearch) { SearchView() }
        .sheet(isPresented: $showStudy) { StudyView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}