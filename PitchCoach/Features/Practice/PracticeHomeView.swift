import SwiftUI

struct PracticeHomeView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    LongTonePracticeView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("長音練習").font(.headline)
                            Text("選一個音持續 10 秒，看準確率與穩定度").font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "waveform.path")
                    }
                }
                NavigationLink {
                    ScalePracticeView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("音階練習").font(.headline)
                            Text("大調音階逐音到位，找出最不準的音").font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "stairs")
                    }
                }
            }
            .navigationTitle("練習")
        }
    }
}
