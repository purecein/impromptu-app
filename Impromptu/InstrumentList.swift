import Foundation

struct Instrument: Identifiable {
    let id: Int          // GM program number (0–127)
    let name: String
    let category: String
}

enum InstrumentList {
    static let all: [Instrument] = [
        // Piano
        .init(id: 0,   name: "Acoustic Grand Piano",  category: "Piano"),
        .init(id: 1,   name: "Bright Acoustic Piano",  category: "Piano"),
        .init(id: 2,   name: "Electric Grand Piano",   category: "Piano"),
        .init(id: 3,   name: "Honky-tonk Piano",       category: "Piano"),
        .init(id: 4,   name: "Electric Piano 1",       category: "Piano"),
        .init(id: 5,   name: "Electric Piano 2",       category: "Piano"),
        .init(id: 6,   name: "Harpsichord",            category: "Piano"),
        .init(id: 7,   name: "Clavinet",               category: "Piano"),
        // Chromatic Perc
        .init(id: 8,   name: "Celesta",                category: "Chromatic Perc"),
        .init(id: 9,   name: "Glockenspiel",           category: "Chromatic Perc"),
        .init(id: 10,  name: "Music Box",              category: "Chromatic Perc"),
        .init(id: 11,  name: "Vibraphone",             category: "Chromatic Perc"),
        .init(id: 12,  name: "Marimba",                category: "Chromatic Perc"),
        .init(id: 13,  name: "Xylophone",              category: "Chromatic Perc"),
        .init(id: 14,  name: "Tubular Bells",          category: "Chromatic Perc"),
        .init(id: 15,  name: "Dulcimer",               category: "Chromatic Perc"),
        // Organ
        .init(id: 16,  name: "Drawbar Organ",          category: "Organ"),
        .init(id: 17,  name: "Percussive Organ",       category: "Organ"),
        .init(id: 18,  name: "Rock Organ",             category: "Organ"),
        .init(id: 19,  name: "Church Organ",           category: "Organ"),
        .init(id: 20,  name: "Reed Organ",             category: "Organ"),
        .init(id: 21,  name: "Accordion",              category: "Organ"),
        .init(id: 22,  name: "Harmonica",              category: "Organ"),
        .init(id: 23,  name: "Tango Accordion",        category: "Organ"),
        // Guitar
        .init(id: 24,  name: "Nylon String Guitar",    category: "Guitar"),
        .init(id: 25,  name: "Steel String Guitar",    category: "Guitar"),
        .init(id: 26,  name: "Jazz Electric Guitar",   category: "Guitar"),
        .init(id: 27,  name: "Clean Electric Guitar",  category: "Guitar"),
        .init(id: 28,  name: "Muted Electric Guitar",  category: "Guitar"),
        .init(id: 29,  name: "Overdriven Guitar",      category: "Guitar"),
        .init(id: 30,  name: "Distortion Guitar",      category: "Guitar"),
        .init(id: 31,  name: "Guitar Harmonics",       category: "Guitar"),
        // Bass
        .init(id: 32,  name: "Acoustic Bass",          category: "Bass"),
        .init(id: 33,  name: "Electric Bass (Finger)", category: "Bass"),
        .init(id: 34,  name: "Electric Bass (Pick)",   category: "Bass"),
        .init(id: 35,  name: "Fretless Bass",          category: "Bass"),
        .init(id: 36,  name: "Slap Bass 1",            category: "Bass"),
        .init(id: 37,  name: "Slap Bass 2",            category: "Bass"),
        .init(id: 38,  name: "Synth Bass 1",           category: "Bass"),
        .init(id: 39,  name: "Synth Bass 2",           category: "Bass"),
        // Strings
        .init(id: 40,  name: "Violin",                 category: "Strings"),
        .init(id: 41,  name: "Viola",                  category: "Strings"),
        .init(id: 42,  name: "Cello",                  category: "Strings"),
        .init(id: 43,  name: "Contrabass",             category: "Strings"),
        .init(id: 44,  name: "Tremolo Strings",        category: "Strings"),
        .init(id: 45,  name: "Pizzicato Strings",      category: "Strings"),
        .init(id: 46,  name: "Orchestral Harp",        category: "Strings"),
        .init(id: 47,  name: "Timpani",                category: "Strings"),
        // Ensemble
        .init(id: 48,  name: "String Ensemble 1",      category: "Ensemble"),
        .init(id: 49,  name: "String Ensemble 2",      category: "Ensemble"),
        .init(id: 50,  name: "SynthStrings 1",         category: "Ensemble"),
        .init(id: 51,  name: "SynthStrings 2",         category: "Ensemble"),
        .init(id: 52,  name: "Choir Aahs",             category: "Ensemble"),
        .init(id: 53,  name: "Voice Oohs",             category: "Ensemble"),
        .init(id: 54,  name: "Synth Voice",            category: "Ensemble"),
        .init(id: 55,  name: "Orchestra Hit",          category: "Ensemble"),
        // Brass
        .init(id: 56,  name: "Trumpet",                category: "Brass"),
        .init(id: 57,  name: "Trombone",               category: "Brass"),
        .init(id: 58,  name: "Tuba",                   category: "Brass"),
        .init(id: 59,  name: "Muted Trumpet",          category: "Brass"),
        .init(id: 60,  name: "French Horn",            category: "Brass"),
        .init(id: 61,  name: "Brass Section",          category: "Brass"),
        .init(id: 62,  name: "SynthBrass 1",           category: "Brass"),
        .init(id: 63,  name: "SynthBrass 2",           category: "Brass"),
        // Reed
        .init(id: 64,  name: "Soprano Sax",            category: "Reed"),
        .init(id: 65,  name: "Alto Sax",               category: "Reed"),
        .init(id: 66,  name: "Tenor Sax",              category: "Reed"),
        .init(id: 67,  name: "Baritone Sax",           category: "Reed"),
        .init(id: 68,  name: "Oboe",                   category: "Reed"),
        .init(id: 69,  name: "English Horn",           category: "Reed"),
        .init(id: 70,  name: "Bassoon",                category: "Reed"),
        .init(id: 71,  name: "Clarinet",               category: "Reed"),
        // Pipe
        .init(id: 72,  name: "Piccolo",                category: "Pipe"),
        .init(id: 73,  name: "Flute",                  category: "Pipe"),
        .init(id: 74,  name: "Recorder",               category: "Pipe"),
        .init(id: 75,  name: "Pan Flute",              category: "Pipe"),
        .init(id: 76,  name: "Blown Bottle",           category: "Pipe"),
        .init(id: 77,  name: "Shakuhachi",             category: "Pipe"),
        .init(id: 78,  name: "Whistle",                category: "Pipe"),
        .init(id: 79,  name: "Ocarina",                category: "Pipe"),
        // Synth Lead
        .init(id: 80,  name: "Lead 1 (square)",        category: "Synth Lead"),
        .init(id: 81,  name: "Lead 2 (sawtooth)",      category: "Synth Lead"),
        .init(id: 82,  name: "Lead 3 (calliope)",      category: "Synth Lead"),
        .init(id: 83,  name: "Lead 4 (chiff)",         category: "Synth Lead"),
        .init(id: 84,  name: "Lead 5 (charang)",       category: "Synth Lead"),
        .init(id: 85,  name: "Lead 6 (voice)",         category: "Synth Lead"),
        .init(id: 86,  name: "Lead 7 (fifths)",        category: "Synth Lead"),
        .init(id: 87,  name: "Lead 8 (bass+lead)",     category: "Synth Lead"),
        // Synth Pad
        .init(id: 88,  name: "Pad 1 (new age)",        category: "Synth Pad"),
        .init(id: 89,  name: "Pad 2 (warm)",           category: "Synth Pad"),
        .init(id: 90,  name: "Pad 3 (polysynth)",      category: "Synth Pad"),
        .init(id: 91,  name: "Pad 4 (choir)",          category: "Synth Pad"),
        .init(id: 92,  name: "Pad 5 (bowed)",          category: "Synth Pad"),
        .init(id: 93,  name: "Pad 6 (metallic)",       category: "Synth Pad"),
        .init(id: 94,  name: "Pad 7 (halo)",           category: "Synth Pad"),
        .init(id: 95,  name: "Pad 8 (sweep)",          category: "Synth Pad"),
        // Synth FX
        .init(id: 96,  name: "FX 1 (rain)",            category: "Synth FX"),
        .init(id: 97,  name: "FX 2 (soundtrack)",      category: "Synth FX"),
        .init(id: 98,  name: "FX 3 (crystal)",         category: "Synth FX"),
        .init(id: 99,  name: "FX 4 (atmosphere)",      category: "Synth FX"),
        .init(id: 100, name: "FX 5 (brightness)",      category: "Synth FX"),
        .init(id: 101, name: "FX 6 (goblins)",         category: "Synth FX"),
        .init(id: 102, name: "FX 7 (echoes)",          category: "Synth FX"),
        .init(id: 103, name: "FX 8 (sci-fi)",          category: "Synth FX"),
        // Ethnic
        .init(id: 104, name: "Sitar",                  category: "Ethnic"),
        .init(id: 105, name: "Banjo",                  category: "Ethnic"),
        .init(id: 106, name: "Shamisen",               category: "Ethnic"),
        .init(id: 107, name: "Koto",                   category: "Ethnic"),
        .init(id: 108, name: "Kalimba",                category: "Ethnic"),
        .init(id: 109, name: "Bag Pipe",               category: "Ethnic"),
        .init(id: 110, name: "Fiddle",                 category: "Ethnic"),
        .init(id: 111, name: "Shanai",                 category: "Ethnic"),
        // Percussive
        .init(id: 112, name: "Tinkle Bell",            category: "Percussive"),
        .init(id: 113, name: "Agogo",                  category: "Percussive"),
        .init(id: 114, name: "Steel Drums",            category: "Percussive"),
        .init(id: 115, name: "Woodblock",              category: "Percussive"),
        .init(id: 116, name: "Taiko Drum",             category: "Percussive"),
        .init(id: 117, name: "Melodic Tom",            category: "Percussive"),
        .init(id: 118, name: "Synth Drum",             category: "Percussive"),
        .init(id: 119, name: "Reverse Cymbal",         category: "Percussive"),
        // Sound Effects
        .init(id: 120, name: "Guitar Fret Noise",      category: "Sound Effects"),
        .init(id: 121, name: "Breath Noise",           category: "Sound Effects"),
        .init(id: 122, name: "Seashore",               category: "Sound Effects"),
        .init(id: 123, name: "Bird Tweet",             category: "Sound Effects"),
        .init(id: 124, name: "Telephone Ring",         category: "Sound Effects"),
        .init(id: 125, name: "Helicopter",             category: "Sound Effects"),
        .init(id: 126, name: "Applause",               category: "Sound Effects"),
        .init(id: 127, name: "Gunshot",                category: "Sound Effects"),
    ]

    /// 카테고리 목록 (삽입 순서 유지)
    static let categories: [String] = {
        var seen = Set<String>()
        return all.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }()

    static func instruments(in category: String) -> [Instrument] {
        all.filter { $0.category == category }
    }

    /// 카테고리 영문 이름을 현재 로케일에 맞게 반환.
    /// 키: instrument.category.Piano, instrument.category.Synth_Lead 등 (공백 → _)
    static func localizedCategory(_ category: String) -> String {
        let key = "instrument.category.\(category.replacingOccurrences(of: " ", with: "_"))"
        return NSLocalizedString(key, comment: "")
    }
}
