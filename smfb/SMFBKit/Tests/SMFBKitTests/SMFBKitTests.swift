import XCTest
@testable import SMFBKit

final class FlyBrainTests: XCTestCase {
    func testBrainBuildsAndFires() throws {
        let brain = try XCTUnwrap(FlyBrain(scale: 1, seed: 3))
        XCTAssertGreaterThan(brain.neuronCount, 1500)
        XCTAssertGreaterThan(brain.synapseCount, 20_000)
        XCTAssertEqual(brain.neuronCount % 16, 0, "neuron count is padded for the vector kernels")
        for _ in 0..<500 { brain.step() }
        XCTAssertGreaterThan(brain.totalSpikes, 0, "a resting brain still has spontaneous activity")
        XCTAssertGreaterThan(brain.rate(of: .centralComplex), 0)
        XCTAssertFalse(brain.kernelName.isEmpty)
    }

    func testRegionsTileTheNetwork() throws {
        let brain = try XCTUnwrap(FlyBrain(scale: 2, seed: 1))
        var next = 0
        for region in BrainRegion.allCases {
            let span = brain.span(of: region)
            XCTAssertEqual(span.lowerBound, next, "\(region.name) is contiguous with the previous region")
            XCTAssertEqual(span.count % 4, 0, "\(region.name) is a multiple of four neurons")
            next = span.upperBound
        }
        XCTAssertLessThanOrEqual(next, brain.neuronCount)
        XCTAssertEqual(BrainRegion.ornLeft.hemisphere, .left)
        XCTAssertEqual(BrainRegion.descendingRight.hemisphere, .right)
        XCTAssertEqual(BrainRegion.centralComplex.hemisphere, .midline)
    }

    func testOdorDrivesTheOlfactoryPathway() throws {
        let brain = try XCTUnwrap(FlyBrain(scale: 1, seed: 5))
        for _ in 0..<300 { brain.clearDrive(); brain.step() }
        let quiet = brain.rate(of: .antennalLobeLeft)
        for _ in 0..<300 {
            brain.clearDrive()
            brain.driveRegion(.ornLeft, millivolts: 25, fraction: 0.5)
            brain.step()
        }
        XCTAssertGreaterThan(brain.rate(of: .antennalLobeLeft), quiet + 0.2)
        XCTAssertGreaterThan(brain.rate(of: .antennalLobeLeft), brain.rate(of: .antennalLobeRight))
    }

    func testSameSeedSameRun() throws {
        let a = try XCTUnwrap(FlyBrain(scale: 1, seed: 11))
        let b = try XCTUnwrap(FlyBrain(scale: 1, seed: 11))
        for _ in 0..<200 { a.step(); b.step() }
        XCTAssertEqual(a.totalSpikes, b.totalSpikes)
        XCTAssertEqual(a.lastSpikes, b.lastSpikes)
    }
}

final class SimulationTests: XCTestCase {
    func testMouseFindsACrumb() {
        let sim = Simulation(config: .init(scale: 1, seed: 7))
        sim.setAspect(1)
        sim.dropFood(x: 0.8, y: 0.5)
        var closest: Float = .infinity
        var ateAt: Double = -1
        for _ in 0..<(30 * 4) {
            sim.advance(seconds: 0.25)
            let s = sim.currentSnapshot()
            let d = hypotf(s.mouse.x - 0.8, s.mouse.y - 0.5)
            closest = min(closest, d)
            if s.pelletsEaten > 0 { ateAt = s.time; break }
        }
        XCTAssertGreaterThan(ateAt, 0, "the mouse should eat the crumb within 30 s (closest \(closest))")
        XCTAssertTrue(sim.currentSnapshot().food.isEmpty)
    }

    func testFoodIsClampedInsideTheArena() {
        let sim = Simulation(config: .init(scale: 1, seed: 1))
        sim.setAspect(0.5)
        sim.dropFood(x: 5, y: -3)
        sim.advance(seconds: 0.01)
        let food = sim.currentSnapshot().food
        XCTAssertEqual(food.count, 1)
        XCTAssertLessThanOrEqual(food[0].x, 1)
        XCTAssertGreaterThanOrEqual(food[0].y, 0)
        XCTAssertLessThanOrEqual(food[0].y, 0.5)
    }

    func testSnapshotCarriesBrainStats() {
        let sim = Simulation(config: .init(scale: 1, seed: 2))
        sim.advance(seconds: 0.5)
        let s = sim.currentSnapshot()
        XCTAssertEqual(s.regionRates.count, BrainRegion.allCases.count)
        XCTAssertGreaterThan(s.neuronCount, 0)
        XCTAssertGreaterThan(s.activityHistory.reduce(0, +), 0)
        XCTAssertEqual(s.width, 1)
    }
}
