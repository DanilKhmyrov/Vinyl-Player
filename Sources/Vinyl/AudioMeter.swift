import Accelerate
import CoreAudio
import AudioToolbox
import Foundation

final class AudioMeter {

    private(set) var left: Float = 0
    private(set) var right: Float = 0

    static let bandCount = 10

    enum Status: Equatable {
        case stopped
        case unsupported
        case failed(String)
        case waiting
        case receiving
    }
    private(set) var status: Status = .stopped

    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioDeviceID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var running = false

    private let attack: Float = 0.6
    private let decay: Float = 0.12


    private static let fftSize = 2048
    private static let log2n = vDSP_Length(11)
    private static let sampleRate: Float = 48_000

    private let fftSetup: FFTSetup?
    private let window: UnsafeMutablePointer<Float>
    private let ring: UnsafeMutablePointer<Float>
    private var ringFill = 0
    private let windowed: UnsafeMutablePointer<Float>
    private let realp: UnsafeMutablePointer<Float>
    private let imagp: UnsafeMutablePointer<Float>
    private let magnitudes: UnsafeMutablePointer<Float>
    private let bands: UnsafeMutablePointer<Float>
    private let bandBins: UnsafeMutablePointer<Int32>

    init() {
        let n = Self.fftSize
        let half = n / 2
        fftSetup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2))
        window = .allocate(capacity: n)
        ring = .allocate(capacity: n)
        windowed = .allocate(capacity: n)
        realp = .allocate(capacity: half)
        imagp = .allocate(capacity: half)
        magnitudes = .allocate(capacity: half)
        bands = .allocate(capacity: Self.bandCount)
        bandBins = .allocate(capacity: Self.bandCount * 2)

        ring.initialize(repeating: 0, count: n)
        windowed.initialize(repeating: 0, count: n)
        realp.initialize(repeating: 0, count: half)
        imagp.initialize(repeating: 0, count: half)
        magnitudes.initialize(repeating: 0, count: half)
        bands.initialize(repeating: 0, count: Self.bandCount)

        vDSP_hann_window(window, vDSP_Length(n), Int32(vDSP_HANN_NORM))

        let low: Float = 40, high: Float = 16_000
        let binHz = Self.sampleRate / Float(n)
        for i in 0..<Self.bandCount {
            let f0 = low * powf(high / low, Float(i) / Float(Self.bandCount))
            let f1 = low * powf(high / low, Float(i + 1) / Float(Self.bandCount))
            let b0 = max(1, Int32((f0 / binHz).rounded()))
            let b1 = min(Int32(half - 1), max(b0, Int32((f1 / binHz).rounded())))
            bandBins[i * 2] = b0
            bandBins[i * 2 + 1] = b1
        }
    }

    deinit {
        if let fftSetup { vDSP_destroy_fftsetup(fftSetup) }
        window.deallocate(); ring.deallocate(); windowed.deallocate()
        realp.deallocate(); imagp.deallocate(); magnitudes.deallocate()
        bands.deallocate(); bandBins.deallocate()
    }

    func band(at index: Int) -> Float {
        guard index >= 0, index < Self.bandCount else { return 0 }
        return bands[index]
    }


    func start() {
        guard !running else { return }
        guard #available(macOS 14.4, *) else { status = .unsupported; return }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTapID: AudioObjectID = 0
        var status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr else {
            self.status = .failed("AudioHardwareCreateProcessTap \(status)")
            return
        }
        tapID = newTapID

        guard let tapUID = description.uuid.uuidString as String? else {
            AudioHardwareDestroyProcessTap(tapID)
            return
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Vinyl Equalizer Tap",
            kAudioAggregateDeviceUIDKey: "dev.danil.vinyl.eq-tap-\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true],
            ],
        ]

        var newAggregateID: AudioDeviceID = 0
        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID)
        guard status == noErr else {
            self.status = .failed("AudioHardwareCreateAggregateDevice \(status)")
            AudioHardwareDestroyProcessTap(tapID)
            return
        }
        aggregateID = newAggregateID

        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { [weak self] _, inputData, _, _, _ in
            self?.consume(inputData)
        }
        guard status == noErr, let ioProcID else {
            self.status = .failed("AudioDeviceCreateIOProcIDWithBlock \(status)")
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
            return
        }

        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else {
            self.status = .failed("AudioDeviceStart \(status)")
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
            return
        }

        running = true
        self.status = .waiting
    }

    func stop() {
        guard running else { return }
        guard #available(macOS 14.4, *) else { return }
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        AudioHardwareDestroyAggregateDevice(aggregateID)
        AudioHardwareDestroyProcessTap(tapID)
        ioProcID = nil
        tapID = 0
        aggregateID = 0
        running = false
        status = .stopped
        left = 0
        right = 0
        ringFill = 0
        bands.update(repeating: 0, count: Self.bandCount)
    }

    private func consume(_ bufferList: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard buffers.count > 0 else { return }


        func rms(_ buffer: AudioBuffer) -> Float {
            guard let data = buffer.mData else { return 0 }
            let frameCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard frameCount > 0 else { return 0 }
            let samples = data.assumingMemoryBound(to: Float.self)
            var sum: Float = 0
            for i in 0..<frameCount { sum += samples[i] * samples[i] }
            return (sum / Float(frameCount)).squareRoot()
        }

        let newLeft: Float
        let newRight: Float
        if buffers.count >= 2 {
            newLeft = rms(buffers[0])
            newRight = rms(buffers[1])
            if let l = buffers[0].mData, let r = buffers[1].mData {
                let frames = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size
                let ls = l.assumingMemoryBound(to: Float.self)
                let rs = r.assumingMemoryBound(to: Float.self)
                for i in 0..<frames { push((ls[i] + rs[i]) * 0.5) }
            }
        } else {
            let buffer = buffers[0]
            let channels = Int(buffer.mNumberChannels)
            guard channels >= 2, let data = buffer.mData else {
                let level = rms(buffer)
                if let mono = buffer.mData {
                    let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    let samples = mono.assumingMemoryBound(to: Float.self)
                    for i in 0..<frames { push(samples[i]) }
                }
                newLeft = level; newRight = level
                consume(newLeft: level, newRight: level)
                return
            }
            let frameCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
            let samples = data.assumingMemoryBound(to: Float.self)
            var sumL: Float = 0, sumR: Float = 0
            for i in 0..<frameCount {
                let l = samples[i * channels]
                let r = samples[i * channels + 1]
                sumL += l * l; sumR += r * r
                push((l + r) * 0.5)
            }
            newLeft = frameCount > 0 ? (sumL / Float(frameCount)).squareRoot() : 0
            newRight = frameCount > 0 ? (sumR / Float(frameCount)).squareRoot() : 0
        }
        consume(newLeft: newLeft, newRight: newRight)
    }

    private func push(_ sample: Float) {
        ring[ringFill] = sample
        ringFill += 1
        guard ringFill == Self.fftSize else { return }
        ringFill = 0
        analyze()
    }

    private func analyze() {
        guard let fftSetup else { return }
        let n = Self.fftSize
        let half = n / 2

        vDSP_vmul(ring, 1, window, 1, windowed, 1, vDSP_Length(n))

        var split = DSPSplitComplex(realp: realp, imagp: imagp)
        windowed.withMemoryRebound(to: DSPComplex.self, capacity: half) { pointer in
            vDSP_ctoz(pointer, 2, &split, 1, vDSP_Length(half))
        }
        vDSP_fft_zrip(fftSetup, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
        vDSP_zvabs(&split, 1, magnitudes, 1, vDSP_Length(half))

        var norm = 2 / Float(n)
        vDSP_vsmul(magnitudes, 1, &norm, magnitudes, 1, vDSP_Length(half))

        for i in 0..<Self.bandCount {
            let b0 = Int(bandBins[i * 2]), b1 = Int(bandBins[i * 2 + 1])
            var sum: Float = 0
            for bin in b0...b1 { sum += magnitudes[bin] }
            let mean = sum / Float(b1 - b0 + 1)

            let tilt = 1 + 1.1 * (Float(i) / Float(Self.bandCount - 1))
            let db = 20 * log10f(mean * tilt + 1e-9)
            let value = min(1, max(0, (db + 68) / 56))

            let previous = bands[i]
            bands[i] = value > previous ? previous + (value - previous) * attack
                                        : previous + (value - previous) * decay
        }
    }

    private func consume(newLeft: Float, newRight: Float) {
        if status == .waiting, newLeft > 0.0001 || newRight > 0.0001 { status = .receiving }
        let boosted = { (v: Float) in min(1, v * 3.2) }
        let l = boosted(newLeft), r = boosted(newRight)
        left = l > left ? left + (l - left) * attack : left + (l - left) * decay
        right = r > right ? right + (r - right) * attack : right + (r - right) * decay
    }
}
