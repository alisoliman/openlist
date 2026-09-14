import AppKit
import SwiftUI

struct MCPSettingsTab: View {
    @Environment(AppEnvironment.self) private var env
    @State private var format = MCPIntegration.ClientFormat.stdio
    @State private var port = ""
    @State private var confirmsTokenReset = false

    var body: some View {
        Form {
            Section("Local AI agent access") {
                Toggle("Enable MCP server", isOn: Binding(
                    get: { env.settings.mcpEnabled },
                    set: { env.mcp.setEnabled($0) }
                ))
                Toggle("Allow changes", isOn: Binding(
                    get: { env.settings.mcpAllowsWrites },
                    set: { env.mcp.setAllowsWrites($0) }
                ))
                .disabled(!env.settings.mcpEnabled)
                Text("Agents can read all tasks and lists. Allow changes lets them edit without asking.")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.secondaryText)
                LabeledContent("Status", value: env.mcp.statusText)
                if case .failed(let error) = env.mcp.status {
                    Text(error)
                        .font(Theme.Font.metadata)
                        .foregroundStyle(.red)
                    Button("Retry") { env.mcp.restart() }
                }
            }

            if env.settings.mcpEnabled {
                Section("Connect an AI client") {
                    Text("Keep Openlist open. Connections stay on this Mac and require a private token.")
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.secondaryText)
                    LabeledContent("Endpoint") {
                        Text(env.mcp.url)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Picker("Client configuration", selection: $format) {
                        ForEach(MCPIntegration.ClientFormat.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    HStack {
                        Button("Copy configuration") {
                            copy { try env.mcp.configuration(for: format) }
                        }
                        Button("Copy token") {
                            copy { try env.mcp.accessToken() }
                        }
                    }
                    .disabled(!env.mcp.isRunning)
                    Text("Merge into your client's MCP settings and reconnect. This includes a private token: never share or commit it.")
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.secondaryText)
                    if let notice = env.mcp.notice {
                        Text(notice)
                            .font(Theme.Font.metadata)
                            .accessibilityLabel(notice)
                    }
                }

                DisclosureGroup("Connection options") {
                    HStack {
                        TextField("Port", text: $port)
                            .onSubmit { env.mcp.setPort(port) }
                        Button("Apply") { env.mcp.setPort(port) }
                            .disabled(Int(port) == env.settings.mcpPort)
                    }
                    Button("Reset access token...", role: .destructive) {
                        confirmsTokenReset = true
                    }
                    .disabled(!env.settings.mcpEnabled || env.mcp.status == .starting)
                    Text("Update client configurations after changing the port or token. HTTP clients need custom Authorization headers. Turning MCP off disconnects every agent.")
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { port = String(env.settings.mcpPort) }
        .onChange(of: env.settings.mcpPort) { _, value in port = String(value) }
        .confirmationDialog("Reset the MCP access token?", isPresented: $confirmsTokenReset) {
            Button("Reset access token", role: .destructive) { env.mcp.restart(rotatingToken: true) }
        } message: {
            Text("Existing client configurations will stop working. Copy a new configuration for every client you still want to allow.")
        }
    }

    private func copy(_ value: () throws -> String) {
        do {
            let text = try value()
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(text, forType: .string) else {
                env.mcp.notice = "The connection details could not be copied. Try again."
                return
            }
            env.mcp.notice = "Copied. The clipboard now contains your private MCP access token."
        } catch {
            env.mcp.notice = error.localizedDescription
        }
    }
}
