import AVFoundation
import os

/// アラーム開始点(ratio=0)〜目標(ratio=1)の間でビープ間隔を 900ms → 110ms へ
/// 指数的に短縮し、目標以上で連続音を鳴らす。波形はオーディオスレッドの
/// レンダーコールバックでサンプル単位に合成するので、リズムは常に正確。
final class Beeper {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let ratioLock = OSAllocatedUnfairLock(initialState: -1.0)

    /// 負なら無音。メインスレッドから毎ティック書き込む。
    var ratio: Double {
        get { ratioLock.withLock { $0 } }
        set { ratioLock.withLock { $0 = newValue } }
    }

    func start() throws {
        guard sourceNode == nil else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate
        let lock = ratioLock

        // レンダーコールバック内だけで使う状態
        var phase: Double = 0
        var samplesUntilBeep: Double = 0
        var beepSamplesLeft: Double = 0
        var beepTotalSamples: Double = 1
        var freq: Double = 880

        let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let r = lock.withLock { $0 }
            let rampSamples = 0.005 * sampleRate

            for frame in 0..<Int(frameCount) {
                var sample: Float = 0

                if r >= 1 {
                    // 連続音（ピーーー）
                    freq = 1400
                    phase += freq / sampleRate
                    if phase >= 1 { phase -= 1 }
                    sample = phase < 0.5 ? 0.25 : -0.25
                    samplesUntilBeep = 0
                    beepSamplesLeft = 0
                } else if r >= 0 {
                    if beepSamplesLeft > 0 {
                        phase += freq / sampleRate
                        if phase >= 1 { phase -= 1 }
                        let played = beepTotalSamples - beepSamplesLeft
                        let env = min(1, min(played, beepSamplesLeft) / rampSamples)
                        sample = (phase < 0.5 ? 0.25 : -0.25) * Float(env)
                        beepSamplesLeft -= 1
                    } else {
                        samplesUntilBeep -= 1
                        if samplesUntilBeep <= 0 {
                            let interval = 0.9 * pow(0.11 / 0.9, r)   // 900ms → 110ms(指数)
                            samplesUntilBeep = interval * sampleRate  // ビープ開始間の間隔
                            beepTotalSamples = 0.07 * sampleRate
                            beepSamplesLeft = beepTotalSamples
                            freq = 880 + 440 * r
                            phase = 0
                        }
                    }
                } else {
                    samplesUntilBeep = 0
                    beepSamplesLeft = 0
                    phase = 0
                }

                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        try engine.start()
        sourceNode = node
    }

    func stop() {
        ratio = -1
        if let node = sourceNode {
            engine.stop()
            engine.detach(node)
            sourceNode = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
