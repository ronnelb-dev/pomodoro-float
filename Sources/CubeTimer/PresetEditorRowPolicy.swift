import Foundation

struct PresetEditorRowPolicy {
    struct State: Equatable {
        let isSaveEnabled: Bool
        let isUseNextTimeEnabled: Bool
        let showsImmediateAction: Bool
    }

    static func state(durationChanged: Bool,
                      metadataChanged: Bool,
                      canAffectActiveSession: Bool) -> State {
        State(isSaveEnabled: durationChanged || metadataChanged,
              isUseNextTimeEnabled: durationChanged,
              showsImmediateAction: durationChanged && canAffectActiveSession)
    }

    static func duplicateNames(for seconds: Int,
                               editingIndex: Int,
                               presetSeconds: [Int],
                               presetNames: [String]) -> [String] {
        presetSeconds.indices
            .filter {
                $0 != editingIndex && presetNames.indices.contains($0) &&
                    presetSeconds[$0] == seconds
            }
            .map { presetNames[$0] }
    }
}
