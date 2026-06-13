import Foundation
import GRDB

// MARK: - Rating

enum COCOMORating: Int, Codable, CaseIterable {
    case veryLow = 0
    case low = 1
    case nominal = 2
    case high = 3
    case veryHigh = 4
    case extraHigh = 5

    var label: String {
        switch self {
        case .veryLow:   return "VL"
        case .low:       return "L"
        case .nominal:   return "N"
        case .high:      return "H"
        case .veryHigh:  return "VH"
        case .extraHigh: return "XH"
        }
    }
}

// MARK: - Scale Factors

enum ScaleFactor: String, CaseIterable {
    case prec, flex, resl, team, pmat

    var label: String {
        switch self {
        case .prec: return "Precedentedness"
        case .flex: return "Dev. Flexibility"
        case .resl: return "Risk Resolution"
        case .team: return "Team Cohesion"
        case .pmat: return "Process Maturity"
        }
    }

    // COCOMO II Post-Architecture scale factor values.
    // Source: Boehm et al., "Software Cost Estimation with COCOMO II" (2000).
    private static let tables: [ScaleFactor: [COCOMORating: Double]] = [
        .prec: [.veryLow: 6.20, .low: 4.96, .nominal: 3.72, .high: 2.46, .veryHigh: 1.24, .extraHigh: 0.00],
        .flex: [.veryLow: 5.07, .low: 4.05, .nominal: 3.04, .high: 2.03, .veryHigh: 1.01, .extraHigh: 0.00],
        .resl: [.veryLow: 7.07, .low: 5.65, .nominal: 4.24, .high: 2.83, .veryHigh: 1.41, .extraHigh: 0.00],
        .team: [.veryLow: 5.48, .low: 4.38, .nominal: 3.29, .high: 2.19, .veryHigh: 1.10, .extraHigh: 0.00],
        .pmat: [.veryLow: 7.80, .low: 6.24, .nominal: 4.68, .high: 3.12, .veryHigh: 1.56, .extraHigh: 0.00],
    ]

    func value(for rating: COCOMORating) -> Double {
        Self.tables[self]![rating]!
    }
}

// MARK: - Effort Multipliers

enum EffortMultiplier: String, CaseIterable {
    // Product
    case rely, data, cplx, ruse, docu
    // Platform
    case time, stor, pvol
    // Personnel
    case acap, pcap, pcon, apex, plex, ltex
    // Project
    case tool, site, sced

    var label: String {
        switch self {
        case .rely: return "Reliability"
        case .data: return "Database Size"
        case .cplx: return "Complexity"
        case .ruse: return "Reusability"
        case .docu: return "Documentation"
        case .time: return "Exec. Time"
        case .stor: return "Storage"
        case .pvol: return "Platform Vol."
        case .acap: return "Analyst Cap."
        case .pcap: return "Programmer Cap."
        case .pcon: return "Personnel Cont."
        case .apex: return "App Experience"
        case .plex: return "Platform Exp."
        case .ltex: return "Language Exp."
        case .tool: return "Tool Use"
        case .site: return "Multi-site"
        case .sced: return "Schedule"
        }
    }

    var group: EffortMultiplierGroup {
        switch self {
        case .rely, .data, .cplx, .ruse, .docu: return .product
        case .time, .stor, .pvol:               return .platform
        case .acap, .pcap, .pcon, .apex, .plex, .ltex: return .personnel
        case .tool, .site, .sced:               return .project
        }
    }

    // COCOMO II Post-Architecture effort multiplier values.
    // Where a rating is undefined in the standard, the nearest valid value
    // is used (e.g. DATA has no VL — it clamps to the L value).
    private static let tables: [EffortMultiplier: [COCOMORating: Double]] = [
        .rely: [.veryLow: 0.82, .low: 0.92, .nominal: 1.00, .high: 1.10, .veryHigh: 1.26, .extraHigh: 1.26],
        .data: [.veryLow: 0.90, .low: 0.90, .nominal: 1.00, .high: 1.14, .veryHigh: 1.28, .extraHigh: 1.28],
        .cplx: [.veryLow: 0.73, .low: 0.87, .nominal: 1.00, .high: 1.17, .veryHigh: 1.34, .extraHigh: 1.74],
        .ruse: [.veryLow: 0.95, .low: 0.95, .nominal: 1.00, .high: 1.07, .veryHigh: 1.15, .extraHigh: 1.24],
        .docu: [.veryLow: 0.81, .low: 0.91, .nominal: 1.00, .high: 1.11, .veryHigh: 1.23, .extraHigh: 1.23],
        .time: [.veryLow: 1.00, .low: 1.00, .nominal: 1.00, .high: 1.11, .veryHigh: 1.29, .extraHigh: 1.63],
        .stor: [.veryLow: 1.00, .low: 1.00, .nominal: 1.00, .high: 1.05, .veryHigh: 1.17, .extraHigh: 1.46],
        .pvol: [.veryLow: 0.87, .low: 0.87, .nominal: 1.00, .high: 1.15, .veryHigh: 1.30, .extraHigh: 1.30],
        .acap: [.veryLow: 1.42, .low: 1.19, .nominal: 1.00, .high: 0.85, .veryHigh: 0.71, .extraHigh: 0.71],
        .pcap: [.veryLow: 1.34, .low: 1.15, .nominal: 1.00, .high: 0.88, .veryHigh: 0.76, .extraHigh: 0.76],
        .pcon: [.veryLow: 1.29, .low: 1.12, .nominal: 1.00, .high: 0.90, .veryHigh: 0.81, .extraHigh: 0.81],
        .apex: [.veryLow: 1.22, .low: 1.10, .nominal: 1.00, .high: 0.88, .veryHigh: 0.81, .extraHigh: 0.81],
        .plex: [.veryLow: 1.19, .low: 1.09, .nominal: 1.00, .high: 0.91, .veryHigh: 0.85, .extraHigh: 0.85],
        .ltex: [.veryLow: 1.20, .low: 1.09, .nominal: 1.00, .high: 0.91, .veryHigh: 0.84, .extraHigh: 0.84],
        .tool: [.veryLow: 1.17, .low: 1.09, .nominal: 1.00, .high: 0.90, .veryHigh: 0.78, .extraHigh: 0.78],
        .site: [.veryLow: 1.22, .low: 1.09, .nominal: 1.00, .high: 0.93, .veryHigh: 0.86, .extraHigh: 0.80],
        .sced: [.veryLow: 1.43, .low: 1.14, .nominal: 1.00, .high: 1.00, .veryHigh: 1.00, .extraHigh: 1.00],
    ]

    func value(for rating: COCOMORating) -> Double {
        Self.tables[self]![rating]!
    }
}

enum EffortMultiplierGroup: String, CaseIterable {
    case product, platform, personnel, project
}

// MARK: - Estimation Result

struct COCOMOResult: Equatable {
    let personMonths: Double
    let hours: Double
}

// MARK: - Estimator

enum COCOMOEstimator {
    static let a: Double = 2.94
    static let b: Double = 0.91
    static let hoursPerPersonMonth: Double = 152.0

    static func estimate(
        sloc: Int,
        scaleFactors: [ScaleFactor: COCOMORating],
        effortMultipliers: [EffortMultiplier: COCOMORating]
    ) -> COCOMOResult {
        guard sloc > 0 else {
            return COCOMOResult(personMonths: 0, hours: 0)
        }

        let ksloc = Double(sloc) / 1000.0

        let sfSum = ScaleFactor.allCases.reduce(0.0) { sum, sf in
            sum + sf.value(for: scaleFactors[sf] ?? .nominal)
        }
        let e = b + 0.01 * sfSum

        let emProduct = EffortMultiplier.allCases.reduce(1.0) { product, em in
            product * em.value(for: effortMultipliers[em] ?? .nominal)
        }

        let effortPM = a * pow(ksloc, e) * emProduct
        let effortHours = effortPM * hoursPerPersonMonth

        return COCOMOResult(personMonths: effortPM, hours: effortHours)
    }
}

// MARK: - Persisted Params

struct COCOMOParams: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "cocomo_params"

    var projectId: String
    var sloc: Int

    var prec: Int
    var flex: Int
    var resl: Int
    var team: Int
    var pmat: Int

    var rely: Int
    var data: Int
    var cplx: Int
    var ruse: Int
    var docu: Int
    var time: Int
    var stor: Int
    var pvol: Int
    var acap: Int
    var pcap: Int
    var pcon: Int
    var apex: Int
    var plex: Int
    var ltex: Int
    var tool: Int
    var site: Int
    var sced: Int

    static func defaults(projectId: String) -> COCOMOParams {
        let n = COCOMORating.nominal.rawValue
        return COCOMOParams(
            projectId: projectId, sloc: 0,
            prec: n, flex: n, resl: n, team: n, pmat: n,
            rely: n, data: n, cplx: n, ruse: n, docu: n,
            time: n, stor: n, pvol: n,
            acap: n, pcap: n, pcon: n, apex: n, plex: n, ltex: n,
            tool: n, site: n, sced: n
        )
    }

    func scaleFactorRating(_ sf: ScaleFactor) -> COCOMORating {
        let raw: Int
        switch sf {
        case .prec: raw = prec
        case .flex: raw = flex
        case .resl: raw = resl
        case .team: raw = team
        case .pmat: raw = pmat
        }
        return COCOMORating(rawValue: raw) ?? .nominal
    }

    func effortMultiplierRating(_ em: EffortMultiplier) -> COCOMORating {
        let raw: Int
        switch em {
        case .rely: raw = rely
        case .data: raw = data
        case .cplx: raw = cplx
        case .ruse: raw = ruse
        case .docu: raw = docu
        case .time: raw = time
        case .stor: raw = stor
        case .pvol: raw = pvol
        case .acap: raw = acap
        case .pcap: raw = pcap
        case .pcon: raw = pcon
        case .apex: raw = apex
        case .plex: raw = plex
        case .ltex: raw = ltex
        case .tool: raw = tool
        case .site: raw = site
        case .sced: raw = sced
        }
        return COCOMORating(rawValue: raw) ?? .nominal
    }

    mutating func setScaleFactor(_ sf: ScaleFactor, to rating: COCOMORating) {
        switch sf {
        case .prec: prec = rating.rawValue
        case .flex: flex = rating.rawValue
        case .resl: resl = rating.rawValue
        case .team: team = rating.rawValue
        case .pmat: pmat = rating.rawValue
        }
    }

    mutating func setEffortMultiplier(_ em: EffortMultiplier, to rating: COCOMORating) {
        switch em {
        case .rely: rely = rating.rawValue
        case .data: data = rating.rawValue
        case .cplx: cplx = rating.rawValue
        case .ruse: ruse = rating.rawValue
        case .docu: docu = rating.rawValue
        case .time: time = rating.rawValue
        case .stor: stor = rating.rawValue
        case .pvol: pvol = rating.rawValue
        case .acap: acap = rating.rawValue
        case .pcap: pcap = rating.rawValue
        case .pcon: pcon = rating.rawValue
        case .apex: apex = rating.rawValue
        case .plex: plex = rating.rawValue
        case .ltex: ltex = rating.rawValue
        case .tool: tool = rating.rawValue
        case .site: site = rating.rawValue
        case .sced: sced = rating.rawValue
        }
    }

    func scaleFactorRatings() -> [ScaleFactor: COCOMORating] {
        Dictionary(uniqueKeysWithValues: ScaleFactor.allCases.map { ($0, scaleFactorRating($0)) })
    }

    func effortMultiplierRatings() -> [EffortMultiplier: COCOMORating] {
        Dictionary(uniqueKeysWithValues: EffortMultiplier.allCases.map { ($0, effortMultiplierRating($0)) })
    }

    func estimate() -> COCOMOResult {
        COCOMOEstimator.estimate(
            sloc: sloc,
            scaleFactors: scaleFactorRatings(),
            effortMultipliers: effortMultiplierRatings()
        )
    }
}
