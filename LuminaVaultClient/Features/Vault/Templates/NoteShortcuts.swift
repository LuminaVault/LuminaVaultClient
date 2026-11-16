// LuminaVaultClient/LuminaVaultClient/Features/Vault/Templates/NoteShortcuts.swift
// Backlog E6.4: a "New note" toolbar menu with "Today's note" and "New from
// template", used on Home and in a Space's file list. Either one opens the
// note in the editable reader.
import LuminaVaultShared
import SwiftUI

struct NewFromTemplateSheet: View {
    @Bindable var vm: NoteShortcutsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if vm.loadingTemplates {
                        ProgressView()
                    } else if vm.templates.isEmpty {
                        Text("No templates yet.").foregroundStyle(.secondary)
                    } else {
                        Picker("Template", selection: $vm.selectedTemplate) {
                            ForEach(vm.templates) { template in
                                Text(NoteShortcutsViewModel.label(template.path))
                                    .tag(Optional(template.path))
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                } header: {
                    Text("Template")
                } footer: {
                    Text("Templates are notes in your Templates space. Edit them there to change what new notes start with.")
                }

                Section("Title") {
                    TextField("Weekly sync", text: $vm.title)
                        .submitLabel(.done)
                        .onSubmit { Task { await create() } }
                }

                if let error = vm.error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New from template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.working {
                        ProgressView()
                    } else {
                        Button("Create") { Task { await create() } }
                            .disabled(!vm.canCreate)
                    }
                }
            }
            .task { await vm.loadTemplates() }
        }
    }

    private func create() async {
        if await vm.create() { dismiss() }
    }
}

private struct NoteShortcutsModifier: ViewModifier {
    @State private var vm: NoteShortcutsViewModel
    @State private var showingTemplates = false
    let vaultClient: VaultClientProtocol
    let memoryClient: MemoryClientProtocol
    let uploadClient: any VaultUploadClientProtocol

    init(vaultClient: VaultClientProtocol, memoryClient: MemoryClientProtocol, uploadClient: any VaultUploadClientProtocol) {
        self._vm = State(wrappedValue: NoteShortcutsViewModel(client: vaultClient))
        self.vaultClient = vaultClient
        self.memoryClient = memoryClient
        self.uploadClient = uploadClient
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Today's note", systemImage: "calendar") {
                            Task { await vm.openToday() }
                        }
                        Button("New from template", systemImage: "doc.badge.plus") {
                            vm.error = nil
                            showingTemplates = true
                        }
                    } label: {
                        Label("New note", systemImage: "square.and.pencil")
                    }
                    .disabled(vm.working)
                }
            }
            .sheet(isPresented: $showingTemplates) {
                NewFromTemplateSheet(vm: vm)
            }
            .navigationDestination(isPresented: Binding(
                get: { vm.openedNote != nil && !showingTemplates },
                set: { if !$0 { vm.openedNote = nil } }
            )) {
                if let note = vm.openedNote {
                    MarkdownReaderView(
                        file: note,
                        vaultClient: vaultClient,
                        memoryClient: memoryClient,
                        uploadClient: uploadClient
                    )
                }
            }
            // The sheet shows its own errors; this is for "Today's note".
            .alert(
                "Couldn't open the note",
                isPresented: Binding(
                    get: { vm.error != nil && !showingTemplates },
                    set: { if !$0 { vm.error = nil } }
                )
            ) {
                Button("OK", role: .cancel) { vm.error = nil }
            } message: {
                Text(vm.error ?? "")
            }
    }
}

extension View {
    /// Backlog E6.4: adds the "New note" menu (Today's note, New from template).
    func noteShortcuts(
        vaultClient: VaultClientProtocol,
        memoryClient: MemoryClientProtocol,
        uploadClient: any VaultUploadClientProtocol
    ) -> some View {
        modifier(NoteShortcutsModifier(vaultClient: vaultClient, memoryClient: memoryClient, uploadClient: uploadClient))
    }
}
