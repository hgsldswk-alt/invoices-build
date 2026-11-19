import SwiftUI
import PDFKit

struct PreviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var document: Document
    @State private var send: SendPayload?
    private var pdf: Data { PDFRenderer.render(document: DocumentRecord(document), business: BusinessRecord(model.business), entitlement: model.entitlement) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(ShareCode.templates, id: \.self) { template in
                            Button(L.t(template)) { model.require(model.entitlement.canUseTemplate(template)) { model.business.settings.template = template; model.save() } }
                                .font(.caption).padding(.horizontal, 13).padding(.vertical, 8).background(model.business.settings.template == template ? Color.white : Color.white.opacity(0.1), in: Capsule()).foregroundStyle(model.business.settings.template == template ? .black : .white).accessibilityIdentifier("template." + template)
                        }
                    }.padding(.horizontal, 18)
                }
                HStack(spacing: 12) {
                    ForEach(Design.colors, id: \.self) { hex in Button { model.business.settings.accentColorHex = hex; model.save() } label: { Circle().fill(Color(uiColor: PDFRenderer.color(hex))).frame(width: 25, height: 25).padding(4).overlay(Circle().stroke(.white.opacity(model.business.settings.accentColorHex == hex ? 1 : 0), lineWidth: 2)) }.accessibilityLabel(hex).accessibilityIdentifier("accent." + hex) }
                }
                PDFCanvas(bytes: pdf).padding(.horizontal, 16).accessibilityIdentifier("pdf.canvas")
                HStack {
                    Button(L.t("Print")) { send = SendPayload.make(document, model: model, method: "print") }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("preview.print")
                    Button(L.t("Send")) { send = SendPayload.make(document, model: model, method: model.business.settings.sendMethod) }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("preview.send")
                }.padding(.horizontal, 20).padding(.bottom, 12)
            }.padding(.top, 8).background(Color(uiColor: .darkGray)).navigationTitle(L.t("Preview")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("Edit")) { dismiss() }.foregroundStyle(.white).accessibilityIdentifier("preview.close") }; ToolbarItem(placement: .topBarTrailing) { if document.kind == "invoice" && document.totals.balance > 0 { Button(L.t("Mark paid")) { model.markPaid(document) }.foregroundStyle(.white).accessibilityIdentifier("preview.paid") } } }
                .sheet(item: $send) { payload in SendSheet(payload: payload) { success in if success { model.sent(document) } } }
        }
    }
}
struct PDFCanvas: UIViewRepresentable {
    var bytes: Data
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.backgroundColor = .darkGray; view.minScaleFactor = 0.2; view.maxScaleFactor = 8; return view }
    func updateUIView(_ uiView: PDFView, context: Context) { if context.coordinator.bytes != bytes { uiView.document = PDFDocument(data: bytes); context.coordinator.bytes = bytes } }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var bytes: Data? }
}
