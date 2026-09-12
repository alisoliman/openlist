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
                Text("Configured agents can read every list and task. Allow changes also permits creating, editing, completing, moving and archiving, without a confirmation for each action.")
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

            Section("Connect an AI client") {
                Text("Keep Openlist running. The server listens only on this Mac and requires a private token. No account, cloud service or extra runtime is needed.")
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
                Text("Merge the configuration into your client's MCP settings, then reconnect. It contains your private token: do not share it or commit it to a repository. HTTP clients must support custom Authorization headers.")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.secondaryText)
                if let notice = env.mcp.notice {
                    Text(notice)
                        .font(Theme.Font.metadata)
                        .accessibilityLabel(notice)
                }
            }

            Section("Connection controls") {
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
                Text("Changing the port or resetting the token requires updating client configurations. Turning MCP off disconnects every agent immediately.")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.secondaryText)
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
