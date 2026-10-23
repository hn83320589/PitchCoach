/// 內建旋律，皆為公有領域（傳統民謠，或作曲者過世逾百年）。只含旋律，不含歌詞。
public struct Song: Identifiable, Sendable {
    public let id: String
    public let title: String
    /// 原曲與年代。
    public let origin: String
    public let sourceURL: String
    public let beatsPerMinute: Int
    let notation: String

    public func melody() throws(MelodyParseError) -> Melody {
        try MelodyParser.parse(notation)
    }
}

public enum Songbook {
    public static let songs: [Song] = [
        Song(id: "twinkle", title: "小星星",
             origin: "法國民謠〈Ah! vous dirai-je, maman〉，1761 年已有出版紀錄",
             sourceURL: "https://en.wikipedia.org/wiki/Ah!_vous_dirai-je,_maman", beatsPerMinute: 100,
             notation: """
             C4:1 C4:1 G4:1 G4:1 A4:1 A4:1 G4:2 F4:1 F4:1 E4:1 E4:1 D4:1 D4:1 C4:2
             G4:1 G4:1 F4:1 F4:1 E4:1 E4:1 D4:2 G4:1 G4:1 F4:1 F4:1 E4:1 E4:1 D4:2
             C4:1 C4:1 G4:1 G4:1 A4:1 A4:1 G4:2 F4:1 F4:1 E4:1 E4:1 D4:1 D4:1 C4:2
             """),
        Song(id: "frere-jacques", title: "兩隻老虎",
             origin: "法國民謠〈Frère Jacques〉，18 世紀",
             sourceURL: "https://en.wikipedia.org/wiki/Fr%C3%A8re_Jacques", beatsPerMinute: 108,
             notation: """
             C4:1 D4:1 E4:1 C4:1 C4:1 D4:1 E4:1 C4:1 E4:1 F4:1 G4:2 E4:1 F4:1 G4:2
             G4:0.5 A4:0.5 G4:0.5 F4:0.5 E4:1 C4:1 G4:0.5 A4:0.5 G4:0.5 F4:0.5 E4:1 C4:1
             C4:1 G3:1 C4:2 C4:1 G3:1 C4:2
             """),
        Song(id: "hanschen-klein", title: "小蜜蜂",
             origin: "德國民謠〈Hänschen klein〉，19 世紀",
             sourceURL: "https://en.wikipedia.org/wiki/H%C3%A4nschen_klein", beatsPerMinute: 112,
             notation: """
             G4:1 E4:1 E4:2 F4:1 D4:1 D4:2 C4:1 D4:1 E4:1 F4:1 G4:1 G4:1 G4:2
             G4:1 E4:1 E4:2 F4:1 D4:1 D4:2 C4:1 E4:1 G4:1 G4:1 E4:4
             D4:1 D4:1 D4:1 D4:1 D4:1 E4:1 F4:2 E4:1 E4:1 E4:1 E4:1 E4:1 F4:1 G4:2
             G4:1 E4:1 E4:2 F4:1 D4:1 D4:2 C4:1 E4:1 G4:1 G4:1 C4:4
             """),
        Song(id: "mary-had-a-little-lamb", title: "瑪莉有隻小綿羊",
             origin: "美國童謠〈Mary Had a Little Lamb〉，旋律 1830 年代（Lowell Mason）",
             sourceURL: "https://en.wikipedia.org/wiki/Mary_Had_a_Little_Lamb", beatsPerMinute: 112,
             notation: """
             E4:1 D4:1 C4:1 D4:1 E4:1 E4:1 E4:2 D4:1 D4:1 D4:2 E4:1 G4:1 G4:2
             E4:1 D4:1 C4:1 D4:1 E4:1 E4:1 E4:1 E4:1 D4:1 D4:1 E4:1 D4:1 C4:4
             """),
        Song(id: "london-bridge", title: "倫敦鐵橋",
             origin: "英國傳統童謠〈London Bridge Is Falling Down〉，17 世紀以前",
             sourceURL: "https://en.wikipedia.org/wiki/London_Bridge_Is_Falling_Down", beatsPerMinute: 112,
             notation: """
             G4:1.5 A4:0.5 G4:1 F4:1 E4:1 F4:1 G4:2 D4:1 E4:1 F4:2 E4:1 F4:1 G4:2
             G4:1.5 A4:0.5 G4:1 F4:1 E4:1 F4:1 G4:2 D4:2 G4:2 E4:1 C4:3
             """),
        Song(id: "ode-to-joy", title: "歡樂頌",
             origin: "貝多芬第九號交響曲第四樂章主題，1824 年",
             sourceURL: "https://en.wikipedia.org/wiki/Ode_to_Joy", beatsPerMinute: 100,
             notation: """
             E4:1 E4:1 F4:1 G4:1 G4:1 F4:1 E4:1 D4:1 C4:1 C4:1 D4:1 E4:1 E4:1.5 D4:0.5 D4:2
             E4:1 E4:1 F4:1 G4:1 G4:1 F4:1 E4:1 D4:1 C4:1 C4:1 D4:1 E4:1 D4:1.5 C4:0.5 C4:2
             """),
    ]
}
