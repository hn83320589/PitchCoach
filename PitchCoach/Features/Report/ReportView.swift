import PDFKit
import PracticeEngine
import SwiftData
import SwiftUI

/// 選擇日期區間 → 產生 PDF 週報 → 預覽實際的 PDF → 分享（可存到「檔案」）。
struct ReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query(sort: \PracticeSessionRecord.startedAt, order: .reverse) private var records: [PracticeSessionRecord]

    @State private var startDay = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var endDay = Date()
    @State private var pdfURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        DatePicker("開始", selection: $startDay, in: ...endDay, displayedComponents: .date)
                        DatePicker("結束", selection: $endDay, in: startDay...Date(), displayedComponents: .date)
                    } footer: {
                        if let errorMessage {
                            Text(errorMessage).foregroundStyle(.red)
                        }
                    }
                    Section {
                        Button("產生週報", action: generate)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("report.generate")
                    }
                }
                .frame(height: pdfURL == nil ? nil : 230)

                if let pdfURL {
                    PDFPreview(url: pdfURL)
                        .border(Color.secondary.opacity(0.3))
                        .padding(.horizontal)
                    ShareLink(item: pdfURL) {
                        Label("分享／儲存到「檔案」", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                    .accessibilityIdentifier("report.share")
                }
            }
            .navigationTitle("給老師的週報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .onChange(of: startDay) { pdfURL = nil }
            .onChange(of: endDay) { pdfURL = nil }
        }
    }

    private func generate() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDay)
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDay)) else { return }
        let interval = DateInterval(start: start, end: end)
        let report = PracticeAnalytics.weeklyReport(records.map(\.summary), interval: interval, calendar: calendar)
        do {
            let data = try WeeklyReportPDF.render(report, studentName: settings.displayStudentName,
                                                  reference: settings.reference, calendar: calendar)
            pdfURL = try WeeklyReportPDF.write(data, interval: interval, calendar: calendar)
            errorMessage = nil
        } catch {
            errorMessage = "週報產生失敗：\(error.localizedDescription)"
        }
    }
}

private struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.backgroundColor = .secondarySystemBackground
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
