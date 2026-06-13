import XCTest
@testable import tt

final class COCOMOEstimatorTests: XCTestCase {

    // MARK: - Zero SLOC

    func testZeroSLOCReturnsZeroEffort() {
        let result = COCOMOEstimator.estimate(sloc: 0, scaleFactors: [:], effortMultipliers: [:])
        XCTAssertEqual(result.personMonths, 0)
        XCTAssertEqual(result.hours, 0)
    }

    // MARK: - All-Nominal Baseline

    func testAllNominal10KSLOC() {
        // With all nominal ratings:
        //   SF sum = 3.72 + 3.04 + 4.24 + 3.29 + 4.68 = 18.97
        //   E = 0.91 + 0.01 * 18.97 = 1.0997
        //   EM product = 1.0 (all nominal)
        //   Effort = 2.94 * (10)^1.0997 * 1.0 ≈ 2.94 * 12.586 ≈ 37.0
        let result = COCOMOEstimator.estimate(sloc: 10_000, scaleFactors: [:], effortMultipliers: [:])
        XCTAssertGreaterThan(result.personMonths, 30)
        XCTAssertLessThan(result.personMonths, 45)
        XCTAssertEqual(result.hours, result.personMonths * 152.0, accuracy: 0.001)
    }

    func testAllNominal1KSLOC() {
        let result = COCOMOEstimator.estimate(sloc: 1_000, scaleFactors: [:], effortMultipliers: [:])
        // 2.94 * (1)^1.0997 = 2.94
        XCTAssertEqual(result.personMonths, 2.94, accuracy: 0.01)
    }

    // MARK: - Scale Factor Effect

    func testHigherScaleFactorsIncreaseExponent() {
        let nominalResult = COCOMOEstimator.estimate(sloc: 50_000, scaleFactors: [:], effortMultipliers: [:])

        // All VeryLow scale factors = max SF values = higher exponent = more effort
        var vlFactors: [ScaleFactor: COCOMORating] = [:]
        for sf in ScaleFactor.allCases { vlFactors[sf] = .veryLow }
        let vlResult = COCOMOEstimator.estimate(sloc: 50_000, scaleFactors: vlFactors, effortMultipliers: [:])

        XCTAssertGreaterThan(vlResult.personMonths, nominalResult.personMonths)
    }

    func testExtraHighScaleFactorsMinimizeExponent() {
        let nominalResult = COCOMOEstimator.estimate(sloc: 50_000, scaleFactors: [:], effortMultipliers: [:])

        var xhFactors: [ScaleFactor: COCOMORating] = [:]
        for sf in ScaleFactor.allCases { xhFactors[sf] = .extraHigh }
        let xhResult = COCOMOEstimator.estimate(sloc: 50_000, scaleFactors: xhFactors, effortMultipliers: [:])

        // XH scale factors = 0.0 each, so E = 0.91 (minimum)
        XCTAssertLessThan(xhResult.personMonths, nominalResult.personMonths)
    }

    // MARK: - Effort Multiplier Effect

    func testHighComplexityIncreasesEffort() {
        let nominalResult = COCOMOEstimator.estimate(sloc: 10_000, scaleFactors: [:], effortMultipliers: [:])
        let highCplx = COCOMOEstimator.estimate(
            sloc: 10_000,
            scaleFactors: [:],
            effortMultipliers: [.cplx: .extraHigh]
        )
        // CPLX XH = 1.74, so effort should be ~74% higher
        XCTAssertGreaterThan(highCplx.personMonths, nominalResult.personMonths * 1.5)
    }

    func testHighCapabilityReducesEffort() {
        let nominalResult = COCOMOEstimator.estimate(sloc: 10_000, scaleFactors: [:], effortMultipliers: [:])
        let highCap = COCOMOEstimator.estimate(
            sloc: 10_000,
            scaleFactors: [:],
            effortMultipliers: [.acap: .veryHigh, .pcap: .veryHigh]
        )
        // ACAP VH=0.71, PCAP VH=0.76 → product ≈ 0.54
        XCTAssertLessThan(highCap.personMonths, nominalResult.personMonths * 0.6)
    }

    // MARK: - Scale Factor Values

    func testAllScaleFactorsHaveAllRatings() {
        for sf in ScaleFactor.allCases {
            for rating in COCOMORating.allCases {
                let value = sf.value(for: rating)
                XCTAssertGreaterThanOrEqual(value, 0.0, "\(sf) \(rating)")
            }
        }
    }

    func testNominalScaleFactorsArePositive() {
        for sf in ScaleFactor.allCases {
            XCTAssertGreaterThan(sf.value(for: .nominal), 0.0)
        }
    }

    // MARK: - Effort Multiplier Values

    func testAllEffortMultipliersHaveAllRatings() {
        for em in EffortMultiplier.allCases {
            for rating in COCOMORating.allCases {
                let value = em.value(for: rating)
                XCTAssertGreaterThan(value, 0.0, "\(em) \(rating)")
            }
        }
    }

    func testNominalEffortMultipliersAreOne() {
        for em in EffortMultiplier.allCases {
            XCTAssertEqual(em.value(for: .nominal), 1.0, accuracy: 0.001, "\(em)")
        }
    }

    // MARK: - COCOMOParams

    func testDefaultParamsAreAllNominal() {
        let params = COCOMOParams.defaults(projectId: "test")
        for sf in ScaleFactor.allCases {
            XCTAssertEqual(params.scaleFactorRating(sf), .nominal)
        }
        for em in EffortMultiplier.allCases {
            XCTAssertEqual(params.effortMultiplierRating(em), .nominal)
        }
        XCTAssertEqual(params.sloc, 0)
    }

    func testSetAndGetScaleFactor() {
        var params = COCOMOParams.defaults(projectId: "test")
        params.setScaleFactor(.prec, to: .high)
        XCTAssertEqual(params.scaleFactorRating(.prec), .high)
        XCTAssertEqual(params.scaleFactorRating(.flex), .nominal)
    }

    func testSetAndGetEffortMultiplier() {
        var params = COCOMOParams.defaults(projectId: "test")
        params.setEffortMultiplier(.cplx, to: .veryHigh)
        XCTAssertEqual(params.effortMultiplierRating(.cplx), .veryHigh)
        XCTAssertEqual(params.effortMultiplierRating(.rely), .nominal)
    }

    func testParamsEstimateMatchesDirectCall() {
        var params = COCOMOParams.defaults(projectId: "test")
        params.sloc = 5000
        params.setScaleFactor(.prec, to: .high)
        params.setEffortMultiplier(.cplx, to: .low)

        let directResult = COCOMOEstimator.estimate(
            sloc: 5000,
            scaleFactors: params.scaleFactorRatings(),
            effortMultipliers: params.effortMultiplierRatings()
        )
        let paramsResult = params.estimate()

        XCTAssertEqual(paramsResult.personMonths, directResult.personMonths, accuracy: 0.001)
        XCTAssertEqual(paramsResult.hours, directResult.hours, accuracy: 0.001)
    }

    // MARK: - Hours Conversion

    func testHoursConversion() {
        let result = COCOMOEstimator.estimate(sloc: 1_000, scaleFactors: [:], effortMultipliers: [:])
        XCTAssertEqual(result.hours, result.personMonths * 152.0, accuracy: 0.001)
    }

    // MARK: - Repository Round-Trip

    func testRepositorySaveAndFetch() throws {
        let db = try TestDatabase.makeInMemory()
        let repo = COCOMORepository(dbQueue: db)

        var params = COCOMOParams.defaults(projectId: "p1")
        params.sloc = 8000
        params.setScaleFactor(.team, to: .veryHigh)
        params.setEffortMultiplier(.tool, to: .high)

        try repo.save(params)
        let fetched = try repo.fetchOrDefault(projectId: "p1")

        XCTAssertEqual(fetched.sloc, 8000)
        XCTAssertEqual(fetched.scaleFactorRating(.team), .veryHigh)
        XCTAssertEqual(fetched.effortMultiplierRating(.tool), .high)
        XCTAssertEqual(fetched.effortMultiplierRating(.cplx), .nominal)
    }

    func testFetchOrDefaultReturnsDefaultForMissing() throws {
        let db = try TestDatabase.makeInMemory()
        let repo = COCOMORepository(dbQueue: db)

        let params = try repo.fetchOrDefault(projectId: "nonexistent")
        XCTAssertEqual(params.projectId, "nonexistent")
        XCTAssertEqual(params.sloc, 0)
        XCTAssertEqual(params.scaleFactorRating(.prec), .nominal)
    }

    func testUpsertOverwrites() throws {
        let db = try TestDatabase.makeInMemory()
        let repo = COCOMORepository(dbQueue: db)

        var params = COCOMOParams.defaults(projectId: "p1")
        params.sloc = 1000
        try repo.save(params)

        params.sloc = 2000
        try repo.save(params)

        let fetched = try repo.fetchOrDefault(projectId: "p1")
        XCTAssertEqual(fetched.sloc, 2000)
    }
}
