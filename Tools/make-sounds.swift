import Foundation

let sampleRate = 48_000.0
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

struct Random {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    mutating func range(_ low: Double, _ high: Double) -> Double { low + (high - low) * next() }
    mutating func bipolar() -> Double { next() * 2 - 1 }
}

struct Biquad {
    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    enum Kind { case lowpass, highpass, bandpass }

    init(_ kind: Kind, frequency: Double, q: Double = 0.707) { set(kind, frequency: frequency, q: q) }

    mutating func set(_ kind: Kind, frequency: Double, q: Double = 0.707) {
        let w = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let alpha = sin(w) / (2 * q), c = cos(w), a0 = 1 + alpha
        switch kind {
        case .lowpass:
            b0 = (1 - c) / 2; b1 = 1 - c; b2 = (1 - c) / 2
        case .highpass:
            b0 = (1 + c) / 2; b1 = -(1 + c); b2 = (1 + c) / 2
        case .bandpass:
            b0 = alpha; b1 = 0; b2 = -alpha
        }
        b0 /= a0; b1 /= a0; b2 /= a0
        a1 = -2 * c / a0; a2 = (1 - alpha) / a0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

func samples(_ seconds: Double) -> Int { Int(seconds * sampleRate) }

func filtered(_ input: [Double], _ filters: [Biquad]) -> [Double] {
    var chain = filters
    return input.map { x in
        var v = x
        for i in chain.indices { v = chain[i].process(v) }
        return v
    }
}

func noise(_ count: Int, _ random: inout Random) -> [Double] {
    (0..<count).map { _ in random.bipolar() }
}

func addClick(_ buffer: inout [Double], at time: Double, frequency: Double, decay: Double,
              amplitude: Double, wrap: Bool = false, random: inout Random) {
    let start = samples(time), length = samples(decay * 7)
    let phase = random.range(0, 2 * .pi)
    for i in 0..<length {
        var index = start + i
        if wrap { index %= buffer.count } else if index >= buffer.count { break }
        let t = Double(i) / sampleRate
        buffer[index] += amplitude * exp(-t / decay) * sin(2 * .pi * frequency * t + phase)
    }
}

func addThump(_ buffer: inout [Double], at time: Double, from f0: Double, to f1: Double,
              decay: Double, amplitude: Double) {
    let start = samples(time)
    var phase = 0.0
    for i in 0..<samples(decay * 8) where start + i < buffer.count {
        let t = Double(i) / sampleRate
        let f = f1 + (f0 - f1) * exp(-t / (decay * 0.6))
        phase += 2 * .pi * f / sampleRate
        let attack = min(1, t / 0.002)
        buffer[start + i] += amplitude * attack * exp(-t / decay) * sin(phase)
    }
}

func crackle(_ count: Int, perSecond: Double, loudness: Double, wrap: Bool, _ random: inout Random) -> [Double] {
    var buffer = [Double](repeating: 0, count: count)
    let clicks = Int(perSecond * Double(count) / sampleRate)
    for _ in 0..<clicks {
        let time = random.next() * Double(count) / sampleRate
        let size = pow(random.next(), 3.2)
        if size > 0.82 {
            addClick(&buffer, at: time, frequency: random.range(700, 1600), decay: random.range(0.0008, 0.0018),
                     amplitude: loudness * size, wrap: wrap, random: &random)
        } else {
            addClick(&buffer, at: time, frequency: random.range(2200, 8000), decay: random.range(0.00008, 0.00035),
                     amplitude: loudness * size, wrap: wrap, random: &random)
        }
    }
    return buffer
}

func hiss(_ count: Int, level: Double, _ random: inout Random) -> [Double] {
    filtered(noise(count, &random), [Biquad(.highpass, frequency: 900), Biquad(.lowpass, frequency: 7000)])
        .map { $0 * level }
}

func rumble(_ count: Int, level: Double, _ random: inout Random) -> [Double] {
    filtered(noise(count, &random), [Biquad(.lowpass, frequency: 45), Biquad(.lowpass, frequency: 45)])
        .map { $0 * level * 30 }
}

func mix(_ layers: [Double]...) -> [Double] {
    let count = layers.map(\.count).max() ?? 0
    var out = [Double](repeating: 0, count: count)
    for layer in layers { for (i, v) in layer.enumerated() { out[i] += v } }
    return out
}

func seamlessLoop(_ buffer: [Double], fade: Double) -> [Double] {
    let f = samples(fade), length = buffer.count - f
    var out = Array(buffer[0..<length])
    for i in 0..<f {
        let x = Double(i) / Double(f)
        out[i] = buffer[i] * sin(x * .pi / 2) + buffer[length + i] * cos(x * .pi / 2)
    }
    return out
}

func fadeEdges(_ buffer: [Double], fadeIn: Double = 0.001, fadeOut: Double = 0.02) -> [Double] {
    var out = buffer
    let i0 = samples(fadeIn), o0 = samples(fadeOut)
    for i in 0..<min(i0, out.count) { out[i] *= Double(i) / Double(i0) }
    for i in 0..<min(o0, out.count) { out[out.count - 1 - i] *= Double(i) / Double(o0) }
    return out
}

func normalize(_ buffer: [Double], rmsDB: Double, peakDB: Double = -1) -> [Double] {
    let window = samples(0.3)
    var loudest = 0.0, sum = 0.0
    for (i, v) in buffer.enumerated() {
        sum += v * v
        if i >= window { sum -= buffer[i - window] * buffer[i - window] }
        loudest = max(loudest, sum / Double(min(i + 1, window)))
    }
    let rms = loudest.squareRoot(), peak = buffer.map(abs).max() ?? 1
    let gain = min(pow(10, rmsDB / 20) / max(rms, 1e-9), pow(10, peakDB / 20) / max(peak, 1e-9))
    return buffer.map { $0 * gain }
}

func write(_ buffer: [Double], name: String) throws {
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    let bytes = buffer.count * 2
    data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + bytes))
    data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
    append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
    data.append(contentsOf: Array("data".utf8)); append(UInt32(bytes))
    for v in buffer { append(Int16(max(-1, min(1, v)) * 32_767)) }
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    try data.write(to: outputDirectory.appendingPathComponent(name))
    print("wrote \(name): \(String(format: "%.2f", Double(buffer.count) / sampleRate)) s")
}


func pink(_ count: Int, _ random: inout Random) -> [Double] {
    var b0 = 0.0, b1 = 0.0, b2 = 0.0
    let raw = (0..<count).map { _ -> Double in
        let w = random.bipolar()
        b0 = 0.99765 * b0 + w * 0.0990460
        b1 = 0.96300 * b1 + w * 0.2965164
        b2 = 0.57000 * b2 + w * 1.0526913
        return b0 + b1 + b2 + w * 0.1848
    }
    return unitRMS(raw)
}

func unitRMS(_ buffer: [Double]) -> [Double] {
    let rms = (buffer.reduce(0) { $0 + $1 * $1 } / Double(max(buffer.count, 1))).squareRoot()
    return buffer.map { $0 / max(rms, 1e-12) }
}

func gaussian(_ random: inout Random) -> Double {
    (-2 * log(max(random.next(), 1e-12))).squareRoot() * cos(2 * .pi * random.next())
}

func decibels(_ db: Double) -> Double { pow(10, db / 20) }

func addTick(_ buffer: inout [Double], at time: Double, amplitude: Double, width: Double, random: inout Random) {
    let start = samples(time), length = max(2, samples(width * 6))
    let sign = random.next() < 0.5 ? -1.0 : 1.0
    for i in 0..<length where start + i < buffer.count {
        let t = Double(i) / sampleRate
        let body = i == 0 ? sign : random.bipolar() * 0.7
        buffer[start + i] += amplitude * body * exp(-t / width)
    }
}

func crackleBed(_ count: Int, perSecond: Double, medianDB: Double, spreadDB: Double, maxDB: Double,
                envelope: [Double]? = nil, _ random: inout Random) -> [Double] {
    var buffer = [Double](repeating: 0, count: count)
    let total = Int(perSecond * Double(count) / sampleRate)
    for _ in 0..<total {
        let time = random.next() * Double(count) / sampleRate
        let weight = envelope.map { $0[min(samples(time), count - 1)] } ?? 1
        let db = min(maxDB, medianDB + spreadDB * gaussian(&random))
        let pop = random.next() < 0.1
        addTick(&buffer, at: time, amplitude: decibels(db) * weight,
                width: pop ? random.range(0.0006, 0.0016) : random.range(0.00004, 0.00025), random: &random)
    }
    return filtered(buffer, [Biquad(.highpass, frequency: 300), Biquad(.lowpass, frequency: 11_000)])
}

func bursts(_ count: Int, rate: Double, depth: Double, _ random: inout Random) -> [Double] {
    let slow = unitRMS(filtered(noise(count, &random), [Biquad(.lowpass, frequency: rate), Biquad(.lowpass, frequency: rate)]))
    let env = slow.map { exp(depth * $0) }
    let mean = env.reduce(0, +) / Double(count)
    return env.map { $0 / mean }
}

func addSubThump(_ buffer: inout [Double], at time: Double, frequency: Double, decay: Double, amplitude: Double,
                 knock: Double = 0, random: inout Random) {
    addThump(&buffer, at: time, from: frequency * 1.4, to: frequency, decay: decay, amplitude: amplitude)
    guard knock > 0 else { return }
    let start = samples(time), length = samples(decay * 3)
    var band = Biquad(.bandpass, frequency: random.range(220, 380), q: 1.4)
    for i in 0..<length where start + i < buffer.count {
        let t = Double(i) / sampleRate
        buffer[start + i] += band.process(random.bipolar()) * knock * exp(-t / (decay * 0.4))
    }
}

func level(_ buffer: [Double], rmsDB: Double, peakDB: Double = -2) -> [Double] {
    let rms = (buffer.reduce(0) { $0 + $1 * $1 } / Double(max(buffer.count, 1))).squareRoot()
    let peak = buffer.map(abs).max() ?? 1
    let gain = min(decibels(rmsDB) / max(rms, 1e-12), decibels(peakDB) / max(peak, 1e-12))
    return buffer.map { $0 * gain }
}

func ambience() -> [Double] {
    var random = Random(seed: 11)
    let total = samples(3.6 + 0.25)
    let bed = filtered(pink(total, &random), [Biquad(.highpass, frequency: 40), Biquad(.lowpass, frequency: 14_000)])
        .map { $0 * decibels(-40) }
    let clicks = crackleBed(total, perSecond: 32, medianDB: -18, spreadDB: 6, maxDB: -4, &random)
    let hum = rumble(total, level: 0.004, &random)
    return level(seamlessLoop(mix(bed, clicks, hum), fade: 0.25), rmsDB: -34)
}

func scratch() -> [Double] {
    var random = Random(seed: 12)
    let total = samples(2.0 + 0.25)
    let env = bursts(total, rate: 8, depth: 0.9, &random)
    let rub = filtered(pink(total, &random), [Biquad(.highpass, frequency: 900), Biquad(.highpass, frequency: 900),
                                              Biquad(.lowpass, frequency: 6000)])
    let rubbing = zip(unitRMS(rub), env).map { $0 * $1 * decibels(-35) }
    let clicks = crackleBed(total, perSecond: 110, medianDB: -10, spreadDB: 4, maxDB: -3, envelope: env, &random)
    var thumps = [Double](repeating: 0, count: total)
    var t = random.range(0.05, 0.3)
    while t < 2.2 {
        addSubThump(&thumps, at: t, frequency: random.range(26, 36), decay: random.range(0.05, 0.11),
                    amplitude: decibels(random.range(-24, -16)), random: &random)
        t += random.range(0.2, 0.5)
    }
    return level(seamlessLoop(mix(rubbing, clicks, thumps), fade: 0.25), rmsDB: -27.5)
}

func start() -> [Double] {
    var random = Random(seed: 13)
    let total = samples(2.4), touch = 0.05
    var out = [Double](repeating: 0, count: total)
    addTick(&out, at: touch, amplitude: 0.9, width: 0.004, random: &random)
    addTick(&out, at: touch + 0.0009, amplitude: 0.45, width: 0.0002, random: &random)
    addTick(&out, at: touch + 0.021, amplitude: 0.22, width: 0.00015, random: &random)
    let scrape = filtered(noise(total, &random), [Biquad(.bandpass, frequency: 2800, q: 0.9)])
    for i in samples(touch)..<samples(touch + 0.06) {
        out[i] += scrape[i] * 0.6 * exp(-(Double(i) / sampleRate - touch) / 0.02)
    }
    addSubThump(&out, at: touch, frequency: 70, decay: 0.025, amplitude: 0.06, random: &random)
    let impact = filtered(noise(total, &random), [Biquad(.highpass, frequency: 300), Biquad(.lowpass, frequency: 9000)])
    for i in samples(touch)..<samples(touch + 0.08) {
        out[i] += impact[i] * 0.45 * exp(-(Double(i) / sampleRate - touch) / 0.009)
    }

    let groove = filtered(pink(total, &random), [Biquad(.highpass, frequency: 250), Biquad(.highpass, frequency: 250),
                                                  Biquad(.lowpass, frequency: 10_000)])
    let clicks = crackleBed(total, perSecond: 3, medianDB: -26, spreadDB: 4, maxDB: -16, &random)
    for i in 0..<total {
        let t = Double(i) / sampleRate
        let envelope = min(1, max(0, (t - touch - 0.004) / 0.03)) * (t > 1.6 ? max(0, 1 - (t - 1.6) / 0.8) : 1)
        out[i] += (groove[i] * decibels(-31) + clicks[i]) * envelope
    }
    return level(out, rmsDB: -30, peakDB: -2)
}

func stop() -> [Double] {
    var random = Random(seed: 14)
    let total = samples(2.2), duration = 2.2
    let source = noise(total, &random)
    var highpass = Biquad(.highpass, frequency: 900)
    var lowpass = Biquad(.lowpass, frequency: 7000)
    var out = [Double](repeating: 0, count: total)
    var rotation = 0.0
    for i in 0..<total {
        let t = Double(i) / sampleRate, x = t / duration
        lowpass.set(.lowpass, frequency: 7000 - 4200 * x)
        rotation += 2 * .pi * (10 - 3 * x) / sampleRate
        let wobble = decibels(3 * sin(rotation))
        let fall = decibels(-16 * x) * min(1, t / 0.01)
        out[i] = lowpass.process(highpass.process(source[i])) * wobble * fall * decibels(-19)
    }
    let fade = (0..<total).map { i -> Double in decibels(-16 * Double(i) / Double(total)) }
    let clicks = crackleBed(total, perSecond: 22, medianDB: -10, spreadDB: 4, maxDB: -3, envelope: fade, &random)
    return level(fadeEdges(mix(out, clicks), fadeIn: 0.003, fadeOut: 0.25), rmsDB: -22, peakDB: -2)
}

func swap() -> [Double] {
    var random = Random(seed: 15)
    let total = samples(1.9)
    let handling = bursts(total, rate: 3, depth: 1.1, &random)
    let rustle = filtered(noise(total, &random), [Biquad(.bandpass, frequency: 1050, q: 0.9), Biquad(.highpass, frequency: 500),
                                                  Biquad(.lowpass, frequency: 2200), Biquad(.lowpass, frequency: 2200)])
    var out = zip(unitRMS(rustle), handling).map { $0 * $1 * decibels(-38) }
    let events: [(Double, Double, Double)] = [(0.45, -20, 0.35), (1.15, -32, 0.18), (1.27, -28, 0.2), (1.78, -25, 0.28)]
    for (time, db, knock) in events {
        addSubThump(&out, at: time, frequency: random.range(25, 30), decay: random.range(0.07, 0.11),
                    amplitude: decibels(db), knock: knock, random: &random)
        addTick(&out, at: time + 0.002, amplitude: decibels(db - 12), width: 0.0003, random: &random)
    }
    let clicks = crackleBed(total, perSecond: 2, medianDB: -32, spreadDB: 3, maxDB: -25, &random)
    return level(fadeEdges(mix(out, clicks), fadeIn: 0.005, fadeOut: 0.08), rmsDB: -32, peakDB: -2)
}

do {
    try write(start(), name: "start.wav")
    try write(stop(), name: "stop.wav")
    try write(swap(), name: "swap.wav")
    try write(ambience(), name: "ambience.wav")
    try write(scratch(), name: "scratch.wav")
} catch {
    FileHandle.standardError.write(Data("make-sounds: \(error)\n".utf8))
    exit(1)
}
