//
//  NextSettingsAgents.swift
//  openlist
//
//  Settings' AI Agents group: the local MCP server and how clients connect.
//

import AppKit
import SwiftUI

struct NXAgentSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var format = MCPIntegration.ClientFormat.stdio
    @State private var port = ""
    @State private var confirmsTokenReset = false

    var body: some View {
        let settings = env.settings
        let mcp = env.mcp
        NXSettingsGroup(title: "AI Agents",
                        footer: settings.mcpEnabled
                            ? "Update client configurations after changing the port or token. HTTP clients need custom Authorization headers. Turning MCP off disconnects every agent."
                            : nil) {
            NXSettingToggle(label: "Enable MCP server", hint: "Local AI agents can read all tasks and lists",
                            isOn: Binding(get: { settings.mcpEnabled }, set: { mcp.setEnabled($0) }))
            NXSettingToggle(label: "Allow changes", hint: "Lets agents edit without asking",
                            isOn: Binding(get: { settings.mcpAllowsWrites }, set: { mcp.setAllowsWrites($0) }))
                .disabled(!settings.mcpEnabled)
            if case .failed(let error) = mcp.status {
                NXSettingRow(label: "Status", hint: error, hintColor: NX.redText, selectable: true) {
                    HStack(spacing: 6) {
                        NXValuePill(text: mcp.statusText)
                        Button("Retry") { mcp.restart() }
                    }
                }
            } else {
                NXSettingRow(label: "Status",
                             hint: settings.mcpEnabled
                                 ? "Keep Openlist open. Connections stay on this Mac and require a private token."
                                 : "Agents can connect while the server is on") {
                    NXValuePill(text: mcp.statusText)
                }
            }

            if settings.mcpEnabled {
                NXSettingRow(label: "Endpoint", hint: "Where clients reach Openlist on this Mac") {
                    Text(mcp.url)
                        .font(NX.mono(11, weight: .regular))
                        .foregroundStyle(NX.ink(0.7))
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 9)
                        .background(NX.ink(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                NXSettingMenu(label: "Client configuration", hint: "Merge it into your client’s MCP settings and reconnect",
                              value: format.title,
                              entries: nxChoices(MCPIntegration.ClientFormat.allCases, selection: $format, title: \.title))
                NXSettingRow(label: "Connection details",
                             hint: mcp.notice ?? "This includes a private token: never share or commit it.") {
                    HStack(spacing: 6) {
                        Button("Copy configuration") {
                            copy { try mcp.configuration(for: format) }
                        }
                        Button("Copy token") {
                            copy { try mcp.accessToken() }
                        }
                    }
                    .disabled(!mcp.isRunning)
                }
                NXSettingRow(label: "Port", hint: "From 1024 to 65535") {
                    HStack(spacing: 6) {
                        NXSettingField(placeholder: "Port", text: $port, width: 72, monospaced: true) { mcp.setPort(port) }
                        Button("Apply") { mcp.setPort(port) }
                            .disabled(Int(port) == settings.mcpPort)
                    }
                }
                NXSettingRow(label: "Access token", hint: "Resetting stops every existing client configuration") {
                    Button("Reset access token…", role: .destructive) {
                        confirmsTokenReset = true
                    }
                    .disabled(!settings.mcpEnabled || mcp.status == .starting)
                }
            }
        }
        .onAppear { port = String(settings.mcpPort) }
        .onChange(of: settings.mcpPort) { _, value in port = String(value) }
        .sheet(isPresented: $confirmsTokenReset) {
            NXConfirmationSheet(title: "Reset the MCP access token?",
                                message: "Existing client configurations will stop working. Copy a new configuration for every client you still want to allow.",
                                confirm: "Reset access token") { mcp.restart(rotatingToken: true) }
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
