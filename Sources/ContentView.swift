import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

private struct ImportSelection: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    @Bindable var store: StudioStore
    @Environment(\.openSettings) private var openSettings
    @State private var route: SidebarRoute = .overview
    @State private var showImporter = false
    @State private var showClientSheet = false
    @State private var pendingImport: ImportSelection?
    @State private var importError: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store, route: $route, onAddRecording: { showImporter = true }, onAddClient: { showClientSheet = true })
                .navigationSplitViewColumnWidth(min: 232, ideal: 258, max: 290)
        } detail: {
            ZStack {
                StudioColor.canvas.ignoresSafeArea()
                destination
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showImporter = true }) {
                        Label("Add recording", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioColor.forest)
                    .help("Import a session audio recording")
                }
                ToolbarItem {
                    Button(action: { openSettings() }) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Configure GPT analysis")
                }
            }
        }
        .frame(minWidth: 1120, minHeight: 720)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { pendingImport = ImportSelection(url: url) }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .sheet(item: $pendingImport) { selection in
            ImportRecordingSheet(url: selection.url, store: store) { sessionID in
                route = .session(sessionID)
            }
        }
        .sheet(isPresented: $showClientSheet) {
            AddClientSheet(store: store)
        }
        .alert("Couldn’t import recording", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch route {
        case .overview:
            OverviewView(store: store, route: $route, onAddRecording: { showImporter = true })
        case .clients:
            ClientsView(store: store, route: $route, onAddClient: { showClientSheet = true })
        case .client(let id):
            if let client = store.client(for: id) {
                ClientDetailView(store: store, clientID: id, clientName: client.name, route: $route)
            } else {
                OverviewView(store: store, route: $route, onAddRecording: { showImporter = true })
            }
        case .session(let id):
            if let session = store.session(for: id), let client = store.client(for: session.clientID) {
                SessionDetailView(store: store, sessionID: id, clientName: client.name)
            } else {
                OverviewView(store: store, route: $route, onAddRecording: { showImporter = true })
            }
        }
    }
}

private struct SidebarView: View {
    @Bindable var store: StudioStore
    @Binding var route: SidebarRoute
    var onAddRecording: () -> Void
    var onAddClient: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(StudioColor.forest).frame(width: 38, height: 38)
                    Image(systemName: "waveform.path").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Coachfolio").font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(StudioColor.ink)
                    Text("COACHING JOURNAL").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.5).foregroundStyle(StudioColor.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 20)

            List(selection: $route) {
                Section("WORKSPACE") {
                    Label("Overview", systemImage: "square.grid.2x2")
                        .tag(SidebarRoute.overview)
                    Label("Clients", systemImage: "person.2")
                        .tag(SidebarRoute.clients)
                }
                Section("RECENT SESSIONS") {
                    if store.sortedSessions.isEmpty {
                        Text("Your sessions will appear here")
                            .font(.system(size: 14))
                            .foregroundStyle(StudioColor.muted)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(store.sortedSessions.prefix(8)) { session in
                            if let client = store.client(for: session.clientID) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(client.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                    Text(session.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: 12)).foregroundStyle(StudioColor.muted)
                                }
                                .tag(SidebarRoute.session(session.id))
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(StudioColor.forest)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Private by design").font(.system(size: 13, weight: .semibold)).foregroundStyle(StudioColor.ink)
                        Text("Saved on this Mac").font(.system(size: 12)).foregroundStyle(StudioColor.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(11)
                .background(StudioColor.mint.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 8) {
                    Button(action: onAddRecording) {
                        Label("Recording", systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioColor.forest)
                    Button(action: onAddClient) {
                        Image(systemName: "person.badge.plus").frame(width: 30)
                    }
                    .buttonStyle(.bordered)
                    .help("Add a client record")
                }
            }
            .padding(13)
        }
        .background(StudioColor.white.opacity(0.95))
    }
}

private struct OverviewView: View {
    @Bindable var store: StudioStore
    @Binding var route: SidebarRoute
    var onAddRecording: () -> Void

    private var totalDuration: TimeInterval { store.sessions.reduce(0) { $0 + $1.duration } }
    private var reviewedCount: Int { store.sessions.filter { $0.review != nil }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("YOUR PRACTICE STUDIO").font(.system(size: 12, weight: .bold)).tracking(1.8).foregroundStyle(StudioColor.muted)
                        Text("A little more insight,\none session at a time.")
                            .font(.system(size: 31, weight: .semibold, design: .rounded)).tracking(-0.7).foregroundStyle(StudioColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Keep client conversations close. Notice your patterns. Choose what to practice next.")
                            .font(.system(size: 14)).foregroundStyle(StudioColor.muted).lineSpacing(3).frame(maxWidth: 480, alignment: .leading)
                        Button(action: onAddRecording) {
                            Label("Bring in a recording", systemImage: "arrow.down.doc")
                        }
                        .buttonStyle(.borderedProminent).tint(StudioColor.forest).padding(.top, 6)
                    }
                    Spacer(minLength: 20)
                    ZStack {
                        Circle().fill(StudioColor.mint).frame(width: 178, height: 178)
                        Circle().stroke(StudioColor.forest.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 5])).frame(width: 145, height: 145)
                        Image(systemName: "leaf.fill").font(.system(size: 45, weight: .light)).foregroundStyle(StudioColor.forest)
                            .rotationEffect(.degrees(-20))
                        Image(systemName: "sparkle").font(.system(size: 21)).foregroundStyle(StudioColor.forest.opacity(0.8)).offset(x: 51, y: -48)
                    }
                    .frame(width: 230, height: 190)
                    .accessibilityHidden(true)
                }
                .padding(25)
                .background(StudioColor.white, in: RoundedRectangle(cornerRadius: 20))

                HStack(spacing: 14) {
                    MetricCard(label: "Clients", value: "\(store.clients.count)", detail: "in your library", icon: "person.2", tint: StudioColor.blue)
                    MetricCard(label: "Sessions", value: "\(store.sessions.count)", detail: "recordings saved", icon: "waveform", tint: StudioColor.mint)
                    MetricCard(label: "Practice reviews", value: "\(reviewedCount)", detail: "reflections created", icon: "sparkles", tint: StudioColor.peach)
                    MetricCard(label: "Audio reviewed", value: totalDuration > 0 ? formatHours(totalDuration) : "—", detail: "transcribed locally", icon: "clock", tint: Color(red: 0.92, green: 0.89, blue: 0.96))
                }

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Recent sessions").font(.system(size: 19, weight: .semibold, design: .rounded)).foregroundStyle(StudioColor.ink)
                                Text("A private record of your coaching work").font(.system(size: 14)).foregroundStyle(StudioColor.muted)
                            }
                            Spacer()
                            if !store.sessions.isEmpty {
                                Button("View all") { route = .clients }.buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).foregroundStyle(StudioColor.forest)
                            }
                        }
                        if store.sortedSessions.isEmpty {
                            EmptySessionsCard(onAddRecording: onAddRecording)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(store.sortedSessions.prefix(5).enumerated()), id: \.element.id) { index, session in
                                    if let client = store.client(for: session.clientID) {
                                        SessionListRow(session: session, clientName: client.name) { route = .session(session.id) }
                                        if index < min(store.sortedSessions.count, 5) - 1 { Divider().overlay(StudioColor.line).padding(.leading, 55) }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .background(StudioColor.white, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 13) {
                        Text("A useful reminder").font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(StudioColor.ink)
                        Text("Transcript patterns can spark reflection, but they cannot capture tone, pauses, safety, or what the client experienced.")
                            .font(.system(size: 14)).foregroundStyle(StudioColor.muted).lineSpacing(4)
                        Link(destination: StandardsLinks.coreCompetencies) {
                            HStack(spacing: 5) { Text("Explore ICF competencies"); Image(systemName: "arrow.up.right") }
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(StudioColor.forest)
                        }
                        .padding(.top, 2)
                        Spacer(minLength: 0)
                        HStack(spacing: 7) {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(StudioColor.forest)
                            Text("Practice feedback, not a credential verdict").font(.system(size: 12, weight: .medium)).foregroundStyle(StudioColor.muted)
                        }
                    }
                    .padding(18)
                    .frame(width: 260).frame(minHeight: 188, alignment: .topLeading)
                    .background(StudioColor.mint.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
                }
                if let error = store.storageError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 14)).foregroundStyle(.red).padding(12)
                }
            }
            .padding(28)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func formatHours(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

private struct MetricCard: View {
    let label: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(StudioColor.muted)
                Spacer()
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(StudioColor.forest).frame(width: 28, height: 28).background(tint, in: Circle())
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(StudioColor.ink)
                Text(detail).font(.system(size: 12)).foregroundStyle(StudioColor.muted).lineLimit(1)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudioColor.white, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct EmptySessionsCard: View {
    var onAddRecording: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.badge.plus").font(.system(size: 21)).foregroundStyle(StudioColor.forest).frame(width: 42, height: 42).background(StudioColor.mint, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text("Start with a session recording").font(.system(size: 14, weight: .semibold)).foregroundStyle(StudioColor.ink)
                Text("Add an audio file to create a private client record.").font(.system(size: 13)).foregroundStyle(StudioColor.muted)
            }
            Spacer()
            Button("Import") { onAddRecording() }.buttonStyle(.bordered).tint(StudioColor.forest)
        }
        .padding(16)
        .background(StudioColor.white, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SessionListRow: View {
    let session: CoachingSession
    let clientName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: session.hasTranscript ? "text.quote" : "waveform")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(StudioColor.forest)
                    .frame(width: 38, height: 38).background(StudioColor.mint.opacity(0.7), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    Text(clientName).font(.system(size: 14, weight: .semibold)).foregroundStyle(StudioColor.ink)
                    Text(session.title).font(.system(size: 13)).foregroundStyle(StudioColor.muted).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(session.date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 12, weight: .medium)).foregroundStyle(StudioColor.ink)
                    Text(session.review == nil ? (session.hasTranscript ? "Transcript ready" : "Needs transcript") : "Practice review")
                        .font(.system(size: 12)).foregroundStyle(StudioColor.muted)
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(StudioColor.muted).padding(.leading, 4)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ClientsView: View {
    @Bindable var store: StudioStore
    @Binding var route: SidebarRoute
    var onAddClient: () -> Void
    @State private var search = ""

    private var filtered: [CoachClient] {
        guard !search.isEmpty else { return store.clients.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
        return store.clients.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "RELATIONSHIPS")
                        Text("Client records").font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(StudioColor.ink)
                        Text("A calm, private home for the people you coach.").font(.system(size: 14)).foregroundStyle(StudioColor.muted)
                    }
                    Spacer()
                    Button(action: onAddClient) { Label("Add client", systemImage: "person.badge.plus") }.buttonStyle(.borderedProminent).tint(StudioColor.forest)
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(StudioColor.muted)
                    TextField("Find a client", text: $search).textFieldStyle(.plain)
                }
                .padding(11).background(StudioColor.white, in: RoundedRectangle(cornerRadius: 11)).frame(maxWidth: 420)

                if filtered.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.2.crop.square.stack").font(.system(size: 29)).foregroundStyle(StudioColor.forest)
                        Text(store.clients.isEmpty ? "Your client list starts here" : "No matching clients")
                            .font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(StudioColor.ink)
                        Text(store.clients.isEmpty ? "Add a client record or import a recording to create one." : "Try another name.")
                            .font(.system(size: 14)).foregroundStyle(StudioColor.muted)
                        if store.clients.isEmpty { Button("Add a client", action: onAddClient).buttonStyle(.borderedProminent).tint(StudioColor.forest).padding(.top, 4) }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 90).background(StudioColor.white, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 14)], spacing: 14) {
                        ForEach(filtered) { client in
                            ClientCard(client: client, sessionCount: store.sessions(for: client.id).count) { route = .client(client.id) }
                        }
                    }
                }
            }
            .padding(30).frame(maxWidth: 1080, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct ClientCard: View {
    let client: CoachClient
    let sessionCount: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    ClientAvatar(name: client.name, size: 43)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(StudioColor.muted)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(client.name).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(StudioColor.ink)
                    Text("\(sessionCount) \(sessionCount == 1 ? "session" : "sessions")")
                        .font(.system(size: 13)).foregroundStyle(StudioColor.muted)
                }
                if !client.notes.isEmpty {
                    Text(client.notes).font(.system(size: 13)).foregroundStyle(StudioColor.muted).lineLimit(2).multilineTextAlignment(.leading)
                } else {
                    Text("Created \(client.createdAt.formatted(date: .abbreviated, time: .omitted))").font(.system(size: 12)).foregroundStyle(StudioColor.muted)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(StudioColor.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(StudioColor.line.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct ClientDetailView: View {
    @Bindable var store: StudioStore
    let clientID: UUID
    let clientName: String
    @Binding var route: SidebarRoute
    @State private var notes = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 15) {
                    ClientAvatar(name: clientName, size: 60)
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "CLIENT RECORD")
                        Text(clientName).font(.system(size: 29, weight: .semibold, design: .rounded)).foregroundStyle(StudioColor.ink)
                        Text("\(store.sessions(for: clientID).count) recorded sessions").font(.system(size: 14)).foregroundStyle(StudioColor.muted)
                    }
                    Spacer()
                    Button { route = .clients } label: { Label("All clients", systemImage: "chevron.left") }.buttonStyle(.bordered)
                }
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("Coach notes").font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(StudioColor.ink)
                        Text("Private context for your work together.").font(.system(size: 13)).foregroundStyle(StudioColor.muted)
                        TextEditor(text: $notes).font(.system(size: 14)).scrollContentBackground(.hidden).frame(minHeight: 150)
                            .padding(8).background(StudioColor.white, in: RoundedRectangle(cornerRadius: 12))
                            .onChange(of: notes) { _, value in store.updateClientNotes(clientID: clientID, notes: value) }
                    }
                    .padding(17).frame(width: 285, alignment: .leading).background(StudioColor.mint.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Session history").font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(StudioColor.ink)
                        let clientSessions = store.sessions(for: clientID)
                        if clientSessions.isEmpty {
                            Text("Import a recording to add the first session.").font(.system(size: 14)).foregroundStyle(StudioColor.muted).padding(18)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(clientSessions.enumerated()), id: \.element.id) { index, session in
                                    SessionListRow(session: session, clientName: clientName) { route = .session(session.id) }
                                    if index < clientSessions.count - 1 { Divider().overlay(StudioColor.line) }
                                }
                            }.padding(.horizontal, 16).background(StudioColor.white, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(30).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear { notes = store.client(for: clientID)?.notes ?? "" }
    }
}

private struct AddClientSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: StudioStore
    @State private var name = ""
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: "NEW RELATIONSHIP")
                Text("Add a client").font(.system(size: 25, weight: .semibold, design: .rounded)).foregroundStyle(StudioColor.ink)
                Text("Client details stay in this Mac’s local library.").font(.system(size: 14)).foregroundStyle(StudioColor.muted)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Client name").font(.system(size: 13, weight: .semibold)).foregroundStyle(StudioColor.ink)
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Private notes").font(.system(size: 13, weight: .semibold)).foregroundStyle(StudioColor.ink)
                TextEditor(text: $notes).frame(height: 100).padding(5).background(StudioColor.white, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(StudioColor.line))
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save client") { store.addClient(name: name, notes: notes); dismiss() }
                    .buttonStyle(.borderedProminent).tint(StudioColor.forest).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 440)
    }
}

private struct ImportRecordingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @Bindable var store: StudioStore
    var onImported: (UUID) -> Void
    @State private var clientName: String
    @State private var title: String
    @State private var date: Date
    @State private var language: ImportLanguage
    @State private var consentConfirmed = false
    @State private var openAIConsentConfirmed = false
    @State private var error: String?

    init(url: URL, store: StudioStore, onImported: @escaping (UUID) -> Void) {
        self.url = url
        self.store = store
        self.onImported = onImported
        _clientName = State(initialValue: FilenameHints.clientName(from: url.lastPathComponent))
        _title = State(initialValue: "Coaching session")
        _date = State(initialValue: FilenameHints.date(from: url.lastPathComponent) ?? Date())
        _language = State(initialValue: ImportLanguage.guess(from: url.lastPathComponent))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: "ADD TO YOUR LIBRARY")
                Text("Import a session").font(.system(size: 25, weight: .semibold, design: .rounded)).foregroundStyle(StudioColor.ink)
                Text("The audio will be copied into your private local library.").font(.system(size: 14)).foregroundStyle(StudioColor.muted)
            }
            HStack(spacing: 10) {
                Image(systemName: "waveform").foregroundStyle(StudioColor.forest).frame(width: 36, height: 36).background(StudioColor.mint, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(url.lastPathComponent).font(.system(size: 13, weight: .medium)).foregroundStyle(StudioColor.ink).lineLimit(1)
                    Text("Audio stays on this Mac").font(.system(size: 12)).foregroundStyle(StudioColor.muted)
                }
                Spacer(minLength: 0)
            }.padding(10).background(StudioColor.white, in: RoundedRectangle(cornerRadius: 11))
            HStack(spacing: 12) {
                field("Client", placeholder: "Client name", text: $clientName)
                field("Session title", placeholder: "Coaching session", text: $title)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Session date").font(.system(size: 12, weight: .semibold)).foregroundStyle(StudioColor.ink)
                    DatePicker("", selection: $date, displayedComponents: .date).labelsHidden().datePickerStyle(.field)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recording language").font(.system(size: 12, weight: .semibold)).foregroundStyle(StudioColor.ink)
                    Picker("", selection: $language) {
                        ForEach(ImportLanguage.allCases) { language in Text(language.rawValue).tag(language) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }
            }
            Toggle(isOn: $consentConfirmed) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("I have the client’s written permission to use this recording for practice review.")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(StudioColor.ink)
                    Text("Required before transcription or analysis. You can import the file without confirming yet.")
                        .font(.system(size: 12)).foregroundStyle(StudioColor.muted)
                }
            }
            .toggleStyle(.checkbox)
            Toggle(isOn: $openAIConsentConfirmed) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("I have permission to send transcript text to OpenAI for GPT analysis.")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(StudioColor.ink)
                    Text("Only needed for GPT reviews. The audio stays on this Mac; transcript text may contain identifying details.")
                        .font(.system(size: 12)).foregroundStyle(StudioColor.muted)
                }
            }
            .toggleStyle(.checkbox)
            if let error { Text(error).font(.system(size: 13)).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Import recording") { importFile() }
                    .buttonStyle(.borderedProminent).tint(StudioColor.forest)
                    .disabled(clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 540).background(StudioColor.canvas)
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(StudioColor.ink)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }.frame(maxWidth: .infinity)
    }

    private func importFile() {
        do {
            let id = try store.importRecording(from: url, clientName: clientName, title: title, date: date, language: language, consentConfirmed: consentConfirmed, openAIConsentConfirmed: openAIConsentConfirmed)
            dismiss()
            onImported(id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct SessionDetailView: View {
    @Bindable var store: StudioStore
    let sessionID: UUID
    let clientName: String
    @AppStorage(OpenAIReviewSettings.providerPreferenceKey) private var reviewProvider = OpenAIReviewSettings.defaultProvider.rawValue
    @State private var focusedTurnID: Int?
    @State private var isTranscribing = false
    @State private var transcriptionProgress: String?
    @State private var transcriptionError: String?
    @State private var speakerWarning: String?
    @State private var isAnalyzing = false
    @State private var analysisError: String?
    @State private var targetLevel: CredentialLevel = .acc
    @State private var showRetranscribeConfirmation = false
    @State private var sessionColumnHeight: CGFloat = 0

    private var session: CoachingSession { store.session(for: sessionID)! }
    private var language: ImportLanguage { ImportLanguage(rawValue: session.language) ?? .english }
    private var currentReviewProvider: ReviewProvider { ReviewProvider(rawValue: reviewProvider) ?? OpenAIReviewSettings.defaultProvider }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 13) {
                    ClientAvatar(name: clientName, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "SESSION REVIEW")
                        Text(clientName).font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(StudioColor.ink)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(session.date.formatted(date: .long, time: .omitted)).font(.system(size: 14, weight: .medium)).foregroundStyle(StudioColor.ink)
                        Text(session.title).font(.system(size: 13)).foregroundStyle(StudioColor.muted)
                    }
                }

                if !session.consentConfirmed {
                    consentNotice
                } else if currentReviewProvider == .openAI && session.openAIConsentConfirmed != true {
                    openAIConsentNotice
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 15) {
                        audioCard
                        TranscriptPanel(store: store, sessionID: sessionID, utterances: session.transcript, focusedTurnID: $focusedTurnID, isTranscribing: isTranscribing, progressText: transcriptionProgress, speakerWarning: speakerWarning, canTranscribe: session.consentConfirmed) {
                            if session.hasTranscript { showRetranscribeConfirmation = true }
                            else { Task { await transcribe() } }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: SessionColumnHeightPreferenceKey.self, value: geometry.size.height)
                        }
                    }
                    PracticeReviewPanel(
                        session: session,
                        provider: currentReviewProvider,
                        targetLevel: $targetLevel,
                        focusedTurnID: $focusedTurnID,
                        isAnalyzing: isAnalyzing,
                        error: analysisError
                    ) { Task { await analyze() } }
                    .frame(width: 405)
                    .frame(height: sessionColumnHeight > 0 ? sessionColumnHeight : nil, alignment: .top)
                }
                .onPreferenceChange(SessionColumnHeightPreferenceKey.self) { height in
                    sessionColumnHeight = height
                }
                if let transcriptionError {
                    Label(transcriptionError, systemImage: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(.red).padding(12).background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(24).frame(maxWidth: 1500, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onChange(of: session.transcript) { _, _ in analysisError = nil }
        .confirmationDialog("Replace this transcript?", isPresented: $showRetranscribeConfirmation, titleVisibility: .visible) {
            Button("Replace transcript", role: .destructive) { Task { await transcribe() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("A new transcription will replace your corrected wording and speaker labels.")
        }
    }

    private var consentNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill").foregroundStyle(StudioColor.forest)
            VStack(alignment: .leading, spacing: 3) {
                Text("Confirm written permission before review").font(.system(size: 14, weight: .semibold)).foregroundStyle(StudioColor.ink)
                Text("Transcription and analysis are paused until you confirm the client agreed to recording and practice review.")
                    .font(.system(size: 12)).foregroundStyle(StudioColor.muted).lineSpacing(2)
            }
            Spacer(minLength: 5)
            Button("I have permission") { store.updateConsent(sessionID: sessionID, confirmed: true) }
                .buttonStyle(.bordered).tint(StudioColor.forest)
        }
        .padding(12).background(StudioColor.peach.opacity(0.68), in: RoundedRectangle(cornerRadius: 12))
    }

    private var openAIConsentNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "cloud.fill").foregroundStyle(StudioColor.forest)
            VStack(alignment: .leading, spacing: 3) {
                Text("Confirm permission for GPT analysis").font(.system(size: 14, weight: .semibold)).foregroundStyle(StudioColor.ink)
                Text("This sends transcript text to OpenAI. The audio remains on this Mac.")
                    .font(.system(size: 12)).foregroundStyle(StudioColor.muted).lineSpacing(2)
            }
            Spacer(minLength: 5)
            Button("I have permission") { store.updateOpenAIConsent(sessionID: sessionID, confirmed: true) }
                .buttonStyle(.bordered).tint(StudioColor.forest)
        }
        .padding(12).background(StudioColor.peach.opacity(0.68), in: RoundedRectangle(cornerRadius: 12))
    }

    private var audioCard: some View {
        HStack(spacing: 12) {
            AudioPlaybackButton(url: store.audioURL(for: session), isEnabled: session.consentConfirmed)
            VStack(alignment: .leading, spacing: 4) {
                Text("Session recording").font(.system(size: 14, weight: .semibold)).foregroundStyle(StudioColor.ink)
                HStack(spacing: 8) {
                    Text(session.formattedDuration).font(.system(size: 12, weight: .medium, design: .monospaced))
                    Circle().fill(StudioColor.line).frame(width: 3, height: 3)
                    Text(language.rawValue).font(.system(size: 12))
                    Circle().fill(StudioColor.line).frame(width: 3, height: 3)
                    Text("Stored locally").font(.system(size: 12))
                }.foregroundStyle(StudioColor.muted)
            }
            Spacer()
            if session.consentConfirmed {
                Menu {
                    Button(role: .destructive) {
                        store.updateConsent(sessionID: sessionID, confirmed: false)
                    } label: {
                        Label("Remove permission confirmation", systemImage: "hand.raised")
                    }
                    if session.openAIConsentConfirmed == true {
                        Button(role: .destructive) {
                            store.updateOpenAIConsent(sessionID: sessionID, confirmed: false)
                        } label: {
                            Label("Remove OpenAI sharing permission", systemImage: "cloud")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 14)).foregroundStyle(StudioColor.muted)
                }
                .menuStyle(.borderlessButton)
                .help("Manage permission confirmation")
            }
            Menu {
                ForEach(ImportLanguage.allCases) { item in
                    Button {
                        store.updateSessionLanguage(sessionID: sessionID, language: item.rawValue)
                    } label: {
                        if item == language { Label(item.rawValue, systemImage: "checkmark") }
                        else { Text(item.rawValue) }
                    }
                }
            } label: { Label("Language", systemImage: "globe").font(.system(size: 12, weight: .medium)) }
                .menuStyle(.borderlessButton).help("Choose the recording language")
        }
        .padding(13).background(StudioColor.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private func transcribe() async {
        guard session.consentConfirmed else { return }
        isTranscribing = true
        transcriptionProgress = "Preparing audio…"
        transcriptionError = nil
        speakerWarning = nil
        defer {
            isTranscribing = false
            transcriptionProgress = nil
        }
        do {
            let url = store.audioURL(for: session)
            let duration = await TranscriptionService.duration(of: url)
            let output = try await TranscriptionService.transcribe(url: url, language: language) { message in
                transcriptionProgress = message
            }
            store.updateTranscript(sessionID: sessionID, utterances: output.utterances, duration: duration)
            speakerWarning = output.speakerWarning
        } catch {
            transcriptionError = error.localizedDescription
        }
    }

    private func analyze() async {
        guard session.consentConfirmed else { return }
        if currentReviewProvider == .openAI && session.openAIConsentConfirmed != true { return }
        isAnalyzing = true
        analysisError = nil
        defer { isAnalyzing = false }
        do {
            let result = try await PracticeReviewService.analyze(session, target: targetLevel)
            store.saveReview(sessionID: sessionID, review: result)
        } catch {
            analysisError = error.localizedDescription
        }
    }
}

private struct AudioPlaybackButton: View {
    let url: URL
    let isEnabled: Bool
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var error: String?

    var body: some View {
        Button {
            if isPlaying {
                player?.pause()
                isPlaying = false
            } else {
                do {
                    if player == nil { player = try AVAudioPlayer(contentsOf: url) }
                    player?.play()
                    isPlaying = true
                } catch let playerError { error = playerError.localizedDescription }
            }
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 40, height: 40).background(StudioColor.forest, in: Circle())
        }
        .buttonStyle(.plain).disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .help(isPlaying ? "Pause recording" : "Play recording")
        .alert("Couldn’t play recording", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
}

private struct SessionColumnHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TranscriptPanel: View {
    @Bindable var store: StudioStore
    let sessionID: UUID
    let utterances: [TranscriptUtterance]
    @Binding var focusedTurnID: Int?
    let isTranscribing: Bool
    let progressText: String?
    let speakerWarning: String?
    let canTranscribe: Bool
    var onTranscribe: () -> Void

    var body: some View {
        let visibleUtterances = utterances.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transcript").font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(StudioColor.ink)
                    Text(isTranscribing ? (progressText ?? "Speech recognition stays on this Mac") : (visibleUtterances.isEmpty ? "Speech recognition stays on this Mac" : "Edit the words and label the speakers"))
                        .font(.system(size: 12)).foregroundStyle(StudioColor.muted)
                    if let speakerWarning, !visibleUtterances.isEmpty {
                        Text(speakerWarning).font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
                    } else if !visibleUtterances.isEmpty {
                        Text("Speaker labels are estimated; confirm Coach / Client before analysis.")
                            .font(.system(size: 11)).foregroundStyle(StudioColor.muted)
                    }
                }
                Spacer(minLength: 5)
                if visibleUtterances.isEmpty {
                    Button(action: onTranscribe) {
                        if isTranscribing { ProgressView().controlSize(.small).padding(.horizontal, 6) }
                        else { Label("Transcribe", systemImage: "waveform") }
                    }
                    .buttonStyle(.borderedProminent).tint(StudioColor.forest).disabled(isTranscribing || !canTranscribe)
                } else {
                    Button(action: onTranscribe) {
                        if isTranscribing { ProgressView().controlSize(.small).padding(.horizontal, 6) }
                        else { Label("Re-transcribe", systemImage: "arrow.clockwise") }
                    }
                    .buttonStyle(.bordered).tint(StudioColor.forest).disabled(isTranscribing || !canTranscribe)
                }
            }
            if visibleUtterances.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.quote").font(.system(size: 24)).foregroundStyle(StudioColor.forest.opacity(0.8))
                    Text(isTranscribing ? "Listening to the recording…" : "No transcript yet")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(StudioColor.ink)
                    Text(isTranscribing ? (progressText ?? "This can take a few minutes for a longer session.") : "Create an on-device transcript, then correct words and label turns before reviewing.")
                        .font(.system(size: 12)).foregroundStyle(StudioColor.muted).multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 300)
                    if !canTranscribe { Text("Confirm written client permission to begin.").font(.system(size: 12, weight: .medium)).foregroundStyle(StudioColor.muted) }
                    if !isTranscribing && canTranscribe {
                        Button("Create transcript", action: onTranscribe).buttonStyle(.bordered).tint(StudioColor.forest).padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 42).padding(.horizontal, 16)
            } else {
                HStack(spacing: 9) {
                    speakerLegend(.coach)
                    speakerLegend(.client)
                    speakerLegend(.unknown)
                    Spacer()
                    Text("\(visibleUtterances.count) turns").font(.system(size: 12)).foregroundStyle(StudioColor.muted)
                }.padding(.vertical, 3)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(visibleUtterances) { line in
                                TranscriptLineRow(store: store, sessionID: sessionID, line: line)
                                    .id(line.id)
                            }
                        }
                    }
                    .frame(minHeight: 350, maxHeight: 720)
                    .onChange(of: focusedTurnID) { _, id in
                        if let id { withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }
        }
        .padding(15).frame(maxWidth: .infinity, alignment: .leading).background(StudioColor.white, in: RoundedRectangle(cornerRadius: 15))
    }

    private func speakerLegend(_ speaker: Speaker) -> some View {
        HStack(spacing: 4) {
            Circle().fill(speakerColor(speaker)).frame(width: 6, height: 6)
            Text(speaker.rawValue).font(.system(size: 11)).foregroundStyle(StudioColor.muted)
        }
    }
}

private struct TranscriptLineRow: View {
    @Bindable var store: StudioStore
    let sessionID: UUID
    let line: TranscriptUtterance
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text(line.timestamp).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(StudioColor.muted).padding(.top, 6).frame(width: 42, alignment: .leading)
            Menu {
                ForEach(Speaker.allCases) { speaker in
                    Button {
                        store.setSpeaker(sessionID: sessionID, utteranceID: line.id, speaker: speaker)
                    } label: {
                        if speaker == line.speaker { Label(speaker.rawValue, systemImage: "checkmark") }
                        else { Text(speaker.rawValue) }
                    }
                }
                if let speakerID = line.speakerID {
                    Divider()
                    ForEach(Speaker.allCases) { speaker in
                        Button("Apply \(speaker.rawValue) to all these turns") {
                            store.setSpeaker(sessionID: sessionID, speakerID: speakerID, speaker: speaker)
                        }
                    }
                }
            } label: {
                Text(line.speaker == .unknown ? "Label" : line.speaker.rawValue)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(speakerColor(line.speaker))
                    .padding(.horizontal, 7).padding(.vertical, 4).background(speakerColor(line.speaker).opacity(0.10), in: Capsule())
            }.menuStyle(.borderlessButton).frame(width: 55, alignment: .leading).padding(.top, 1)
            TextField("Transcript line", text: Binding(
                get: { store.session(for: sessionID)?.transcript.first(where: { $0.id == line.id })?.text ?? line.text },
                set: { store.updateUtteranceText(sessionID: sessionID, utteranceID: line.id, text: $0) }
            ), axis: .vertical)
            .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(StudioColor.ink).lineLimit(1...5)
        }
        .padding(.horizontal, 8).padding(.vertical, 8).background(StudioColor.canvas.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(speakerColor(line.speaker)).frame(width: 2).padding(.vertical, 7) }
    }
}

private struct PracticeReviewPanel: View {
    let session: CoachingSession
    let provider: ReviewProvider
    @Binding var targetLevel: CredentialLevel
    @Binding var focusedTurnID: Int?
    let isAnalyzing: Bool
    let error: String?
    var onAnalyze: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider == .openAI ? "GPT practice review" : "Offline practice review").font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(StudioColor.ink)
                    Text(provider == .openAI ? "Transcript analysis with OpenAI" : "Analysis stays on this Mac").font(.system(size: 12)).foregroundStyle(StudioColor.muted)
                }
                Spacer()
                Image(systemName: "sparkles").font(.system(size: 15)).foregroundStyle(StudioColor.forest).frame(width: 30, height: 30).background(StudioColor.mint, in: Circle())
            }
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Review lens").font(.system(size: 12, weight: .medium)).foregroundStyle(StudioColor.muted)
                    Picker("Review lens", selection: $targetLevel) {
                        ForEach(CredentialLevel.allCases) { level in Text(level.rawValue).tag(level) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 128)
                }
                Spacer(minLength: 4)
                Button {
                    onAnalyze()
                } label: {
                    if isAnalyzing { ProgressView().controlSize(.small) }
                    else { Label(session.review == nil ? "Review" : "Refresh", systemImage: "sparkles") }
                }
                .buttonStyle(.borderedProminent).tint(StudioColor.forest).disabled(isAnalyzing || !session.consentConfirmed || (provider == .openAI && session.openAIConsentConfirmed != true) || !session.hasTranscript)
                .help(provider == .openAI ? "Send transcript text to OpenAI for a GPT practice review" : "Create an on-device or offline practice review")
            }
            if !session.consentConfirmed {
                ReviewEmptyState(icon: "lock.fill", title: "Review is paused", detail: "Confirm written client permission above before analyzing this session.")
            } else if provider == .openAI && session.openAIConsentConfirmed != true {
                ReviewEmptyState(icon: "cloud.fill", title: "GPT review needs permission", detail: "Confirm that the client agreed to send transcript text to OpenAI.")
            } else if !session.hasTranscript {
                ReviewEmptyState(icon: "text.quote", title: "Transcript first", detail: "Once the transcript is ready, review strengths, growth edges, and competency evidence.")
            } else if let review = session.review {
                ScrollView(.vertical) {
                    reviewContent(review)
                        .padding(.trailing, 4)
                }
                .frame(maxHeight: .infinity)
                .scrollIndicators(.automatic)
            } else if isAnalyzing {
                ReviewEmptyState(icon: "sparkles", title: "Reflecting on the transcript", detail: "Evidence is being matched to the selected practice lens.")
            } else {
                ReviewEmptyState(icon: provider == .openAI ? "sparkles" : "leaf", title: provider == .openAI ? "Ready for a GPT review" : "Ready for an offline review", detail: provider == .openAI ? "Add an OpenAI API key in Settings, then choose ACC or PCC and review the transcript." : "Choose ACC or PCC and review the transcript locally.")
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(15).background(StudioColor.white, in: RoundedRectangle(cornerRadius: 15))
    }

    @ViewBuilder
    private func reviewContent(_ review: PracticeReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(StudioColor.forest)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated coaching level · \(review.alignment)").font(.system(size: 14, weight: .semibold)).foregroundStyle(StudioColor.ink)
                    Text("\(review.targetLevel.rawValue) practice lens · \(review.method)").font(.system(size: 11)).foregroundStyle(StudioColor.muted)
                }
            }
            Text(review.summary).font(.system(size: 13)).foregroundStyle(StudioColor.ink).lineSpacing(3).fixedSize(horizontal: false, vertical: true)

            if let accReadiness = review.accReadiness {
                VStack(alignment: .leading, spacing: 5) {
                    Text("ACC PERFORMANCE · AI PRACTICE ESTIMATE").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(StudioColor.muted)
                    Text(accReadiness).font(.system(size: 13, weight: .semibold)).foregroundStyle(StudioColor.ink)
                    if let rationale = review.accReadinessRationale {
                        Text(rationale).font(.system(size: 12)).foregroundStyle(StudioColor.ink).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(11).background(StudioColor.peach.opacity(0.48), in: RoundedRectangle(cornerRadius: 10))
            }

            if !review.strengths.isEmpty {
                reviewSectionTitle("What may be working", icon: "sun.max.fill", color: StudioColor.forest)
                ForEach(review.strengths) { note in ReviewNoteCard(note: note, kind: .strength, focusedTurnID: $focusedTurnID, transcript: session.transcript) }
            }
            if !review.growthAreas.isEmpty {
                reviewSectionTitle("Places to explore", icon: "arrow.up.right.circle.fill", color: Color(red: 0.66, green: 0.42, blue: 0.18))
                ForEach(review.growthAreas) { note in ReviewNoteCard(note: note, kind: .growth, focusedTurnID: $focusedTurnID, transcript: session.transcript) }
            }
            HStack {
                Text("COMPETENCY EVIDENCE").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(StudioColor.muted)
                Spacer()
                Text("\(review.findings.count) areas").font(.system(size: 11)).foregroundStyle(StudioColor.muted)
            }.padding(.top, 2)
            VStack(spacing: 0) {
                ForEach(Array(review.findings.enumerated()), id: \.element.id) { index, finding in
                    FindingRow(finding: finding, focusedTurnID: $focusedTurnID, transcript: session.transcript)
                    if index < review.findings.count - 1 { Divider().overlay(StudioColor.line).padding(.leading, 4) }
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("TRY NEXT").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(StudioColor.muted)
                Text(review.nextPractice).font(.system(size: 12)).foregroundStyle(StudioColor.ink).lineSpacing(3)
            }.padding(11).background(StudioColor.mint.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
            Text(review.limitations).font(.system(size: 11)).foregroundStyle(StudioColor.muted).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Link("ACC criteria", destination: StandardsLinks.accCriteria)
                Link("PCC criteria", destination: StandardsLinks.pccCriteria)
                Link("Core competencies", destination: StandardsLinks.coreCompetencies)
            }.font(.system(size: 11, weight: .medium)).foregroundStyle(StudioColor.forest)
        }
    }

    private func reviewSectionTitle(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color)
            Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(StudioColor.ink)
        }.padding(.top, 3)
    }
}

private struct ReviewNoteCard: View {
    enum Kind { case strength, growth }
    let note: EvidenceNote
    let kind: Kind
    @Binding var focusedTurnID: Int?
    let transcript: [TranscriptUtterance]

    private var color: Color { kind == .strength ? StudioColor.forest : Color(red: 0.66, green: 0.42, blue: 0.18) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(note.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(StudioColor.ink)
            Text(note.detail).font(.system(size: 12)).foregroundStyle(StudioColor.muted).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            evidenceButtons
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var evidenceButtons: some View {
        let available = note.turnIDs.compactMap { id in transcript.first(where: { $0.id == id }) }
        if !available.isEmpty {
            HStack(spacing: 5) {
                ForEach(available) { turn in
                    Button("Turn \(turn.id) · \(turn.timestamp)") { focusedTurnID = turn.id }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
                        .padding(.horizontal, 7).padding(.vertical, 4).background(color.opacity(0.09), in: Capsule())
                }
            }.padding(.top, 1)
        }
    }
}

private struct FindingRow: View {
    let finding: CompetencyFinding
    @Binding var focusedTurnID: Int?
    let transcript: [TranscriptUtterance]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(finding.competency).font(.system(size: 12, weight: .semibold)).foregroundStyle(StudioColor.ink).frame(maxWidth: .infinity, alignment: .leading)
                Text(finding.status.rawValue.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(statusColor(finding.status))
            }
            Text(finding.note).font(.system(size: 11)).foregroundStyle(StudioColor.muted).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            if !finding.turnIDs.isEmpty {
                HStack(spacing: 4) {
                    ForEach(finding.turnIDs, id: \.self) { id in
                        if let turn = transcript.first(where: { $0.id == id }) {
                            Button("Turn \(turn.id) · \(turn.timestamp)") { focusedTurnID = id }
                                .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(StudioColor.forest)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 9)
    }
}

private struct ReviewEmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 21)).foregroundStyle(StudioColor.forest).padding(.bottom, 2)
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(StudioColor.ink)
            Text(detail).font(.system(size: 12)).foregroundStyle(StudioColor.muted).multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 10)
    }
}

private struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(StudioColor.muted)
    }
}

private struct ClientAvatar: View {
    let name: String
    let size: CGFloat
    private var initials: String {
        name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
    var body: some View {
        Text(initials.isEmpty ? "•" : initials).font(.system(size: size * 0.29, weight: .semibold, design: .rounded)).foregroundStyle(StudioColor.forest)
            .frame(width: size, height: size).background(StudioColor.mint, in: Circle())
    }
}

private func speakerColor(_ speaker: Speaker) -> Color {
    switch speaker {
    case .coach: StudioColor.forest
    case .client: Color(red: 0.22, green: 0.43, blue: 0.57)
    case .unknown: StudioColor.muted
    }
}

private func statusColor(_ status: FindingStatus) -> Color {
    switch status {
    case .evidence: StudioColor.forest
    case .mixed: Color(red: 0.67, green: 0.46, blue: 0.15)
    case .notObserved: Color(red: 0.66, green: 0.35, blue: 0.29)
    case .reviewNeeded: StudioColor.muted
    }
}
