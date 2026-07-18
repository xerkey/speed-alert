import SwiftUI

struct ContentView: View {
    @StateObject private var engine = RideEngine()

    private var speedColor: Color {
        if engine.speedKmh >= engine.targetKmh { return .red }
        if engine.speedKmh >= engine.alarmStartKmh { return .orange }
        return .primary
    }

    var body: some View {
        VStack(spacing: 20) {
            header
            Spacer(minLength: 0)
            speedDisplay
            progressBar
            settings
            demoRow
            startButton
            Text("バックグラウンド動作対応：スタート後は画面をロックしてポケットに入れてOK")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color(red: 0.043, green: 0.063, blue: 0.125).ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            Text("SPEED ALERT")
                .font(.subheadline.weight(.semibold))
                .kerning(1.5)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(gpsDotColor).frame(width: 8, height: 8)
                Text(engine.gps.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var gpsDotColor: Color {
        switch engine.gps {
        case .off: return .gray
        case .acquiring: return .yellow
        case .fix(let acc): return acc <= 10 ? .green : (acc <= 30 ? .orange : .red)
        case .denied, .error: return .red
        }
    }

    private var speedDisplay: some View {
        VStack(spacing: 4) {
            Text(engine.speedKmh, format: .number.precision(.fractionLength(1)))
                .font(.system(size: 110, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(speedColor)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("km/h")
                .font(.headline)
                .kerning(2)
                .foregroundStyle(.secondary)
        }
    }

    private var progressBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(speedColor == .primary ? Color.blue : speedColor)
                        .frame(width: geo.size.width * min(1, engine.speedKmh / (engine.targetKmh * 1.15)))
                        .animation(.linear(duration: 0.2), value: engine.speedKmh)
                }
            }
            .frame(height: 14)
            HStack {
                Text("0")
                Spacer()
                Text("アラーム開始 \(Int(engine.alarmStartKmh))")
                Spacer()
                Text("目標 \(Int(engine.targetKmh))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private var settings: some View {
        HStack(spacing: 12) {
            SettingStepper(title: "目標スピード",
                           value: $engine.targetKmh,
                           range: 5...120)
            SettingStepper(title: "アラーム開始（手前）",
                           value: $engine.rangeKmh,
                           range: 3...60)
        }
    }

    private var demoRow: some View {
        HStack(spacing: 10) {
            Toggle("デモ", isOn: $engine.demoMode)
                .labelsHidden()
            Text("デモ")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $engine.demoKmh, in: 0...80)
                .disabled(!engine.demoMode)
            Text("\(Int(engine.demoKmh))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 28)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private var startButton: some View {
        Button {
            engine.toggle()
        } label: {
            Text(engine.running ? "■ ストップ" : "▶ スタート")
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(engine.running ? .red : .blue)
    }
}

private struct SettingStepper: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                stepButton("minus") { value = max(range.lowerBound, value - 1) }
                Text("\(Int(value))")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .frame(minWidth: 48)
                stepButton("plus") { value = min(range.upperBound, value + 1) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func stepButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.bold))
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
