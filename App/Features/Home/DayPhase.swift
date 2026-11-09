import HueKit
import SwiftUI

enum DayPhase {
    case morning, day, evening, night

    static var now: DayPhase {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<10: .morning
        case 10..<17: .day
        case 17..<22: .evening
        default: .night
        }
    }

    var greeting: String {
        switch self {
        case .morning: String(localized: "Guten Morgen")
        case .day: String(localized: "Hallo")
        case .evening: String(localized: "Guten Abend")
        case .night: String(localized: "Gute Nacht")
        }
    }

    var icon: String {
        switch self {
        case .morning: "sunrise.fill"
        case .day: "sun.max.fill"
        case .evening: "sunset.fill"
        case .night: "moon.stars.fill"
        }
    }

    /// Hue's standard scene names (German and English) that fit this time of day, best first.
    var sceneKeywords: [String] {
        switch self {
        case .morning: ["Energie tanken", "Energize", "Hell", "Bright", "Konzentrieren", "Concentrate"]
        case .day: ["Konzentrieren", "Concentrate", "Lesen", "Read", "Hell", "Bright"]
        case .evening: ["Entspannen", "Relax", "Sonnenuntergang", "Sunset", "Lesen", "Read"]
        case .night: ["Nachtlicht", "Nightlight", "Entspannen", "Relax"]
        }
    }
}

extension HueStore {
    /// A scene that fits the time of day, preferring rooms that are in use right now.
    func suggestion(for phase: DayPhase) -> (scene: HueScene, group: HueGroup)? {
        let rooms = sortedRooms
        let ordered = rooms.filter { groupedLight(for: $0)?.isOn == true } + rooms.filter { groupedLight(for: $0)?.isOn != true }
        for keyword in phase.sceneKeywords {
            for room in ordered {
                let isOn = groupedLight(for: room)?.isOn == true
                if let scene = scenes(in: room).first(where: {
                    $0.name.localizedCaseInsensitiveContains(keyword) && !($0.isActive && isOn)
                }) {
                    return (scene, room)
                }
            }
        }
        return nil
    }
}
