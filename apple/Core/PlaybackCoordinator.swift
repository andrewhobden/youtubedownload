import Foundation

/// A player that can be silenced when another player takes over audio output.
@MainActor
protocol ExclusivePlayer: AnyObject {
    /// Stop (or pause) so another player can play. Music fully stops and closes
    /// its bar; AV players pause and keep their position.
    func stopForExclusivity()
}

/// Ensures only one media player is audible at a time. Every player registers
/// itself and calls `stopOthers(except:)` when it starts playing; the
/// coordinator then silences all other registered players.
///
/// This is what makes starting a video automatically stop a playing audio
/// track (music or audiobook), and vice-versa.
@MainActor
final class PlaybackCoordinator {

    static let shared = PlaybackCoordinator()
    private init() {}

    private struct WeakPlayer { weak var player: (any ExclusivePlayer)? }
    private var players: [WeakPlayer] = []

    /// Register a player so it participates in exclusive playback. Safe to call
    /// repeatedly for the same instance.
    func register(_ player: any ExclusivePlayer) {
        let id = ObjectIdentifier(player)
        players.removeAll { $0.player == nil || $0.player.map(ObjectIdentifier.init) == id }
        players.append(WeakPlayer(player: player))
    }

    /// Silence every registered player except the one that's starting.
    func stopOthers(except active: any ExclusivePlayer) {
        let activeID = ObjectIdentifier(active)
        for entry in players {
            guard let player = entry.player else { continue }
            if ObjectIdentifier(player) != activeID {
                player.stopForExclusivity()
            }
        }
        players.removeAll { $0.player == nil }
    }
}
