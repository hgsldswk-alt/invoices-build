import SwiftUI

enum Design {
    static func adaptive(_ light: String, _ dark: String) -> Color {
        Color(uiColor: UIColor { trait in PDFRenderer.color(trait.userInterfaceStyle == .dark ? dark : light) })
    }
    static let accent = adaptive("1F5B4A", "5FA88E")
    static let soft = adaptive("E4EEEA", "233B33")
    static let red = adaptive("B4432F", "DB8A78")
    static let redSoft = adaptive("F6E6E2", "422822")
    static let background = adaptive("F7F6F3", "141615")
    static let card = adaptive("FFFFFF", "1E2120")
    static let line = adaptive("E6E4DF", "343936")
    static let ink = adaptive("16181A", "F0F1EF")
    static let muted = adaptive("8A8D90", "A1A5A2")
    static let colors = ["1F5B4A","23466B","292929","8C4B35","655977"]
}
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).frame(minHeight: 50)
            .background(Design.accent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 14))
    }
}
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: 0) { content }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Design.card, in: RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).stroke(Design.line, lineWidth: 0.5)) }
}
struct AmountRow: View {
    var title: String
    var amount: String
    var bold = false
    var body: some View { HStack(alignment: .firstTextBaseline) { Text(title).foregroundStyle(bold ? Design.ink : Design.muted); Spacer(minLength: 8); Text(amount).monospacedDigit().foregroundStyle(Design.ink) }.font(bold ? .headline : .subheadline).padding(.vertical, 7) }
}
struct StatusBadge: View {
    var status: String
    var label: String? = nil
    var color: Color { status == "overdue" ? Design.red : status == "draft" ? Design.muted : Design.accent }
    var body: some View {
        Text(label ?? L.status(status)).font(.caption2.weight(.semibold)).foregroundStyle(color).padding(.horizontal, 8).padding(.vertical, 3)
            .background(status == "paid" ? Design.soft : status == "overdue" ? Design.redSoft : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(color.opacity(status == "sent" || status == "partial" ? 0.4 : 0), style: StrokeStyle(lineWidth: 0.7, dash: status == "partial" ? [2,2] : [])))
    }
}
struct DecimalField: View {
    var title: String
    @Binding var value: Decimal
    var body: some View { TextField(title, value: $value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit() }
}
extension View {
    func pageBackground() -> some View { scrollContentBackground(.hidden).background(Design.background).tint(Design.accent) }
}
