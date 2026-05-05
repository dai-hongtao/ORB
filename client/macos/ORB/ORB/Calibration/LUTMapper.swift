import Foundation

enum LUTMapper {
    static func defaultLUT(
        for moduleType: ModuleType,
        moduleID: Int,
        channelIndex: Int
    ) -> CalibrationLUT {
        let steps: [Double]

        switch moduleType {
        case .radiance:
            steps = [0, 0.25, 0.5, 0.75, 1.0]
        case .balance, .unknown:
            steps = stride(from: 0.0, through: 1.0, by: 0.1).map { $0 }
        }

        let points = steps.map { LUTPoint(input: $0, output: $0) }
        return CalibrationLUT(
            moduleID: moduleID,
            channelIndex: channelIndex,
            points: points,
            updatedAt: .now
        )
    }

    static func map(normalizedValue: Double, with lut: CalibrationLUT?) -> Int {
        let clamped = min(max(normalizedValue, 0), 1)
        guard let lut, lut.points.count >= 2 else {
            return Int((clamped * 4095).rounded())
        }

        var sorted = lut.points.sorted { $0.input < $1.input }

        if let first = sorted.first, first.input > 0.0001 {
            sorted.insert(LUTPoint(input: 0, output: 0), at: 0)
        }

        if let last = sorted.last, last.input < 0.9999 {
            sorted.append(LUTPoint(input: 1, output: 1))
        }

        if clamped <= sorted[0].input {
            return Int((sorted[0].output * 4095).rounded())
        }

        for index in 0..<(sorted.count - 1) {
            let left = sorted[index]
            let right = sorted[index + 1]
            guard clamped >= left.input, clamped <= right.input else { continue }
            let progress = (clamped - left.input) / max(right.input - left.input, 0.0001)
            let output = left.output + ((right.output - left.output) * progress)
            return Int((min(max(output, 0), 1) * 4095).rounded())
        }

        return Int((min(max(sorted[sorted.count - 1].output, 0), 1) * 4095).rounded())
    }
}
