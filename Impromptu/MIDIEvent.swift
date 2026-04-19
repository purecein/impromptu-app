import Foundation

enum MIDIEvent {
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case noteOff(channel: UInt8, note: UInt8)
    case controlChange(channel: UInt8, controller: UInt8, value: UInt8)
    case pitchBend(channel: UInt8, value: UInt16)
    case aftertouch(channel: UInt8, pressure: UInt8)
    case programChange(channel: UInt8, program: UInt8)
}

extension MIDIEvent {
    var debugDescription: String {
        switch self {
        case .noteOn(_, let note, let velocity):
            return "Note On  \(midiNoteName(note))  vel \(velocity)"
        case .noteOff(_, let note):
            return "Note Off \(midiNoteName(note))"
        case .controlChange(_, let cc, let value):
            return "CC \(cc) = \(value)"
        case .pitchBend(_, let value):
            return "Pitch Bend \(Int(value) - 8192)"
        case .aftertouch(_, let pressure):
            return "Aftertouch \(pressure)"
        case .programChange(_, let prog):
            return "Program Change \(prog)"
        }
    }
}

private func midiNoteName(_ note: UInt8) -> String {
    let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
    let octave = Int(note) / 12 - 1
    return "\(names[Int(note) % 12])\(octave)"
}
