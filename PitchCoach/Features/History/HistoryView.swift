import MusicTheory
import PracticeEngine
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \PracticeSessionRecord.startedAt, order: .reverse) private var records: [PracticeSessionRecord]
    @State private var showsReport = false

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView("還沒有練習紀錄", systemImage: "chart.bar",
                                           description: Text("完成長音或音階練習後，這裡會顯示近 30 天的趨勢。"))
                } else {
                    List {
                        Section("近 30 天") {
                            TrendCharts(summaries: records.map(\.summary))
                                .padding(.vertical, 8)
                        }
                        Section("練習紀錄") {
                            ForEach(records.prefix(100)) { record in
                                NavigationLink {
                                    RecordDetailView(record: record)
                                } label: {
                                    RecordRow(record: record)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("紀錄")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsReport = true
                    } label: {
                        Label("週報", systemImage: "doc.richtext")
                    }
                    .accessibilityIdentifier("history.report")
                }
            }
            .sheet(isPresented: $showsReport) {
                ReportView()
            }
        }
    }
}

extension PracticeSessionRecord {
    var title: String {
        switch kind {
        case .longTone:
            "長音 \(targetNote?.name() ?? "")"
        case .scale:
            "\(scaleKey?.displayName ?? "音階") \(direction == .ascendingDescending ? "上下行" : "上行")"
        case .freePractice:
            "自由練習"
        }
    }

    var scoreText: String {
        switch kind {
        case .longTone: inToleranceRatio.map { String(format: "%.0f%%", $0 * 100) } ?? "—"
        case .scale: "到位 \(reachedSteps ?? 0)/\(totalSteps ?? 0)"
        case .freePractice: formatPracticeDuration(activeDuration)
        }
    }

    var reference: TuningReference { TuningReference(clamping: referenceA4) }
}

extension PracticeKind {
    var symbolName: String {
        switch self {
        case .longTone: "waveform.path"
        case .scale: "stairs"
        case .freePractice: "tuningfork"
        }
    }
}

private struct RecordRow: View {
    let record: PracticeSessionRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.kind.symbolName)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.title).font(.body.weight(.medium))
                    if record.status == .interrupted {
                        Text("中斷").font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text(record.kind == .freePractice
                     ? record.startedAt.formatted(date: .abbreviated, time: .shortened)
                     : "\(record.startedAt.formatted(date: .abbreviated, time: .shortened))・\(formatPracticeDuration(record.activeDuration))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(record.scoreText).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

struct RecordDetailView: View {
    let record: PracticeSessionRecord

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text(record.title).font(.title2.weight(.semibold))
                Text(record.startedAt.formatted(date: .long, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                if let reason = record.interruptionReason {
                    InterruptedBadge(reason: reason.displayName)
                }
                switch record.kind {
                case .longTone: longTone
                case .scale: scale
                case .freePractice:
                    StatTile(title: "演奏時間（開著調音器）", value: formatPracticeDuration(record.activeDuration), emphasized: true)
                }
                Text("A4 = \(Int(record.referenceA4)) Hz").font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var longTone: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                StatTile(title: "±10¢ 以內", value: record.scoreText, emphasized: true)
                StatTile(title: "平均偏差", value: formattedCents(record.meanCents))
                StatTile(title: "穩定度（標準差）", value: record.standardDeviationCents.map { String(format: "%.1f ¢", $0) } ?? "—")
            }
            DeviationCurveChart(curve: record.curve).frame(height: 220)
        }
    }

    private var scale: some View {
        // 紀錄建立時已用同一基準驗證過範圍；萬一失敗就退回升記號音名，不影響數值顯示
        let majorScale = record.scaleKey.flatMap { key in
            try? MajorScale(key: key, startOctave: record.startOctave ?? 4, direction: record.direction ?? .ascending,
                            reference: record.reference)
        }
        return VStack(spacing: 0) {
            ForEach(record.sortedNoteStats, id: \.persistentModelID) { stat in
                HStack {
                    Image(systemName: stat.reached ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(stat.reached ? TunerPalette.inTune : .secondary)
                    Text(majorScale?.displayName(of: Note(midi: stat.midi)) ?? Note(midi: stat.midi).name())
                    Spacer()
                    Text(formattedCents(stat.meanCents)).monospacedDigit()
                }
                .padding(.vertical, 10)
                Divider()
            }
        }
        .padding(.horizontal)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}
