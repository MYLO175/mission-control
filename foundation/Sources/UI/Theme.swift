import SwiftUI

struct WorkspaceTheme {
    let canvas: Color, sidebar: Color, card: Color, ink: Color, accent: Color, line: Color, user: Color
    static func current(dark: Bool) -> Self {
        let light: [String], night: [String]
        switch AppIdentity.theme {
        case "ocean":
            light = ["EDF3F8","E3EDF5","FFFFFF","20364A","2C678F","D6E2EC","DCECF8"]
            night = ["101C28","142333","1C2D3E","E5EEF6","91C5E8","324B62","2B4C65"]
        case "graphite":
            light = ["F0F1F3","E6E8EC","FFFFFF","292D35","496486","DADDE3","E0E7F1"]
            night = ["181A1F","1D2026","252830","ECEEF3","AEC2DF","3B404C","354359"]
        case "rose":
            light = ["F6F0F1","EFE5E9","FFFBFC","412D39","86516C","E7D7DF","EFDFE8"]
            night = ["241B22","2C202A","342731","F2E8EF","D6A9C2","503C49","503B4D"]
        case "gold":
            light = ["F5EFDF","EAE1C9","FFFCF3","352A18","826017","D9C99E","E8D7AC"]
            night = ["19160F","211C12","2B2418","F6EED9","E0BA63","51422A","4B3B20"]
        default:
            light = ["F4F2EA","EAEDE3","FFFEFA","26332C","456B54","DDE3D8","DCE9DD"]
            night = ["171E1A","1C2620","222D26","E8EFE8","A5CBAA","36483B","334B3A"]
        }
        let values = (dark ? night : light).map(Color.hex)
        return .init(canvas: values[0], sidebar: values[1], card: values[2], ink: values[3], accent: values[4], line: values[5], user: values[6])
    }
}
extension Color {
    static func hex(_ text: String) -> Color {
        let value = UInt32(text, radix: 16) ?? 0
        return Color(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
}
