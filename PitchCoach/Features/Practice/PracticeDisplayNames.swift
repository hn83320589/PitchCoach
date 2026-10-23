import PracticeEngine

extension PracticeInterruptionReason {
    var displayName: String {
        switch self {
        case .audioInterruption: "來電或其他 App 使用音訊"
        case .routeChange: "耳機連接或中斷"
        case .appBackgrounded: "App 進入背景"
        case .mediaServicesReset: "音訊服務重置"
        case .engineFailure: "收音失敗"
        }
    }
}
