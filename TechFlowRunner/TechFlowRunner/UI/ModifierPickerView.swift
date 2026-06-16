//
//  ModifierPickerView.swift
//  Tech Flow Runner
//
//  Run modifier selection. The chosen modifier is captured when a run starts,
//  so it always categorizes the resulting score correctly.
//

import SwiftUI

struct ModifierPickerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Modifier.allCases) { modifier in
                        modifierCard(modifier)
                    }
                }
                .padding()
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Modifier")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func modifierCard(_ modifier: Modifier) -> some View {
        let selected = app.selectedModifier == modifier
        return Button {
            app.selectModifier(modifier)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(modifier.label).font(.headline).foregroundStyle(Theme.text)
                    Text(modifier.blurb).font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f×", modifier.scoreMult))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.gold)
                    if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.cyan)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel.opacity(0.85)))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? Theme.cyan : Theme.cyan.opacity(0.2),
                                  lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(modifier.label), score multiplier \(String(format: "%.2f", modifier.scoreMult))")
    }
}
