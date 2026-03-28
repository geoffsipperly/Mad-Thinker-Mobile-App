//
//  OpsTicketDetailView.swift
//  SkeenaSystem
//
//  Editable detail form for an existing operational ticket.
//  Loads owners for the picker, saves changes via update_ticket.
//

import SwiftUI

struct OpsTicketDetailView: View {
    let ticket: OpsTicket
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    // Editable state (seeded from ticket)
    @State private var taskName: String = ""
    @State private var descriptionText: String = ""
    @State private var selectedOwnerId: String = ""
    @State private var dueDate: Date = Date()
    @State private var hasDueDate: Bool = false
    @State private var stage: String = "todo"
    @State private var notes: String = ""

    // Owners
    @State private var owners: [TicketOwner] = []

    // Save state
    @State private var isSaving = false
    @State private var errorText: String?

    private let stages = ["todo", "doing", "done"]

    var body: some View {
        List {
            Section {
                TextField("Task name", text: $taskName)
                    .foregroundColor(.white)

                TextField("Description", text: $descriptionText, axis: .vertical)
                    .foregroundColor(.white)
                    .lineLimit(3...6)
            } header: {
                Text("Details").foregroundColor(.white)
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section {
                Picker("Owner", selection: $selectedOwnerId) {
                    Text("Unassigned").tag("")
                    ForEach(owners) { owner in
                        Text(owner.name).tag(owner.userId)
                    }
                }
                .foregroundColor(.white)

                Picker("Stage", selection: $stage) {
                    Text("To Do").tag("todo")
                    Text("In Progress").tag("doing")
                    Text("Done").tag("done")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Assignment").foregroundColor(.white)
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section {
                Toggle("Has due date", isOn: $hasDueDate)
                    .foregroundColor(.white)

                if hasDueDate {
                    DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                        .foregroundColor(.white)
                }
            } header: {
                Text("Schedule").foregroundColor(.white)
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section {
                TextField("Notes", text: $notes, axis: .vertical)
                    .foregroundColor(.white)
                    .lineLimit(3...8)
            } header: {
                Text("Notes").foregroundColor(.white)
            }
            .listRowBackground(Color.white.opacity(0.06))
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Edit Ticket")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text("Save")
                            .foregroundColor(taskName.isEmpty ? .gray : .blue)
                    }
                }
                .disabled(taskName.isEmpty || isSaving)
            }
        }
        .alert("Error", isPresented: .constant(errorText != nil)) {
            Button("OK") { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
        .task {
            await loadOwners()
            await MainActor.run { seedFromTicket() }
        }
    }

    // MARK: - Seed

    private func seedFromTicket() {
        taskName = ticket.taskName
        descriptionText = ticket.description ?? ""
        selectedOwnerId = ticket.ownerUserId ?? ""
        stage = ticket.stage
        notes = ticket.notes ?? ""

        if let due = ticket.dueDate, !due.isEmpty {
            hasDueDate = true
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            dueDate = fmt.date(from: due) ?? Date()
        }
    }

    // MARK: - Load owners

    private func loadOwners() async {
        AppLogging.log("[OpsTicketDetail] Loading owners... ticket.ownerUserId=\(ticket.ownerUserId ?? "nil")", level: .debug, category: .auth)
        do {
            let fetched = try await OpsTicketsAPI.getOwners()
            await MainActor.run {
                owners = fetched
                AppLogging.log("[OpsTicketDetail] Loaded \(fetched.count) owner(s), will seed form now", level: .debug, category: .auth)
            }
        } catch {
            AppLogging.log("[OpsTicketDetail] Failed to load owners: \(error)", level: .error, category: .auth)
        }
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dueDateString = hasDueDate ? fmt.string(from: dueDate) : nil

        do {
            _ = try await OpsTicketsAPI.updateTicket(
                ticketId: ticket.id,
                taskName: taskName,
                description: descriptionText,
                ownerUserId: selectedOwnerId.isEmpty ? nil : selectedOwnerId,
                dueDate: dueDateString,
                notes: notes,
                stage: stage
            )
            await MainActor.run {
                onSaved?()
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
            }
        }
    }
}
