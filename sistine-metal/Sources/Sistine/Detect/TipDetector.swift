import Foundation
import simd

/// Turns the GPU's per-column run table into a single point on the glass.
///
/// The core observation: at a grazing viewing angle the display's glass acts as
/// a mirror, so a finger above it appears as two vertically stacked blobs — the
/// finger, then a gap, then its reflection. Because the reflection is a mirror
/// image *through the glass plane*, the midpoint between the finger's lowest
/// pixel and the reflection's highest pixel lies **on the glass**, at every
/// hover height. That gives a stable cursor position while hovering, and makes
/// contact a separate, independent measurement (the gap closing) rather than
/// something that has to be inferred from position.
///
/// Sistine's original formulation looked only for the moment the two blobs
/// touched, which meant the cursor only existed at the instant of a click.
final class TipDetector {
    private var reflectionLengthEMA: Float = 12
    private var previousContact: GlassContact?

    struct ColumnCandidate {
        var x: Int
        var contactY: Float
        var gap: Float
        var fingerLength: Float
        var merged: Bool
    }

    func reset() {
        previousContact = nil
        reflectionLengthEMA = 12
    }

    func detect(runs: ColumnRunTable, config: Config) -> GlassContact? {
        var candidates: [ColumnCandidate] = []
        candidates.reserveCapacity(64)

        for x in 0..<runs.width {
            let n = runs.runCount(x)
            guard n >= 1 else { continue }

            if n >= 2 {
                // Bottom-most pair: everything above it is forearm, sleeve or
                // a stray reflection of the screen's own content.
                let f = n - 2, r = n - 1
                let fingerLen = Float(runs.length(x, f))
                let reflLen = Float(runs.length(x, r))
                let gap = Float(runs.start(x, r) - runs.end(x, f) - 1)

                guard gap >= 0, gap <= Float(config.maxPairGap),
                      fingerLen >= Float(config.minFingerRun),
                      reflLen >= config.minReflectionRatio * fingerLen
                else { continue }

                candidates.append(ColumnCandidate(
                    x: x,
                    contactY: Float(runs.end(x, f) + runs.start(x, r)) * 0.5,
                    gap: gap,
                    fingerLength: fingerLen,
                    merged: false))
            } else {
                // One run: the finger and its reflection have fused, which is
                // what contact looks like. The contact plane sits one
                // reflection-length up from the bottom of the fused blob — we
                // carry that length forward from the hover frames that preceded
                // the touch, where it was directly observable.
                let len = Float(runs.length(x, 0))
                guard len >= Float(config.minFingerRun) else { continue }
                candidates.append(ColumnCandidate(
                    x: x,
                    contactY: Float(runs.end(x, 0)) - reflectionLengthEMA,
                    gap: 0,
                    fingerLength: len - reflectionLengthEMA,
                    merged: true))
            }
        }

        guard let cluster = bestCluster(candidates, config: config) else {
            previousContact = nil
            return nil
        }

        let contact = refine(cluster, config: config)
        updateReflectionEstimate(from: cluster, runs: runs)
        previousContact = contact
        return contact
    }

    // MARK: - Clustering

    /// Group columns whose contact height varies smoothly. A finger produces a
    /// short, flat arc of columns; a false positive from screen content or a
    /// sleeve edge produces either a single column or a wildly jagged one.
    private func bestCluster(_ candidates: [ColumnCandidate], config: Config) -> [ColumnCandidate]? {
        guard !candidates.isEmpty else { return nil }

        var clusters: [[ColumnCandidate]] = []
        var current: [ColumnCandidate] = [candidates[0]]

        for c in candidates.dropFirst() {
            let prev = current[current.count - 1]
            let columnGap = c.x - prev.x
            let heightJump = abs(c.contactY - prev.contactY)
            // Tolerate a one-column dropout (a specular highlight on the nail).
            if columnGap <= 2 && heightJump <= Float(config.maxColumnJump) {
                current.append(c)
            } else {
                clusters.append(current)
                current = [c]
            }
        }
        clusters.append(current)

        let viable = clusters.filter { $0.count >= config.minClusterWidth }
        guard !viable.isEmpty else { return nil }

        // Temporal continuity beats size: if we were already tracking a finger,
        // stay with the cluster nearest it so a second hand entering frame
        // cannot steal the pointer mid-drag.
        if let prev = previousContact {
            return viable.min { a, b in
                distance(centroid(a), prev.point) < distance(centroid(b), prev.point)
            }
        }
        return viable.max { $0.count < $1.count }
    }

    private func centroid(_ cluster: [ColumnCandidate]) -> SIMD2<Float> {
        var sum = SIMD2<Float>(0, 0)
        for c in cluster { sum += SIMD2(Float(c.x), c.contactY) }
        return sum / Float(cluster.count)
    }

    // MARK: - Refinement

    /// The fingertip is the part of the cluster closest to the glass, not its
    /// centre — a finger approaches at an angle, so the knuckle end of the blob
    /// still has a large gap while the tip is already touching down.
    private func refine(_ cluster: [ColumnCandidate], config: Config) -> GlassContact {
        let minGap = cluster.map(\.gap).min() ?? 0
        let cut = minGap + max(2, minGap * 0.5)
        let tip = cluster.filter { $0.gap <= cut }
        let use = tip.isEmpty ? cluster : tip

        var weighted = SIMD2<Float>(0, 0)
        var weight: Float = 0
        for c in use {
            let w = max(c.fingerLength, 1)
            weighted += SIMD2(Float(c.x), c.contactY) * w
            weight += w
        }
        let point = weighted / max(weight, 1)

        let xs = cluster.map(\.x)
        let span = (xs.min() ?? 0)...(xs.max() ?? 0)
        let mergedFraction = Float(cluster.filter(\.merged).count) / Float(cluster.count)

        return GlassContact(
            point: point,
            gap: minGap,
            // Apparent finger width is the perspective scale reference. Using the
            // full cluster span (not just the tip columns) keeps it stable as the
            // gap collapses.
            widthPx: Float(span.count),
            columns: span,
            // A cluster that is mostly merged runs is a confident touch; one that
            // is mostly paired runs is a confident hover. A half-and-half cluster
            // is usually two fingers being read as one.
            confidence: max(mergedFraction, 1 - mergedFraction))
    }

    /// Track the reflection's length while it is visible, so the merged-run case
    /// has a recent, position-appropriate value to subtract.
    private func updateReflectionEstimate(from cluster: [ColumnCandidate], runs: ColumnRunTable) {
        let visible = cluster.filter { !$0.merged }
        guard !visible.isEmpty else { return }
        var total: Float = 0
        var count: Float = 0
        for c in visible {
            let n = runs.runCount(c.x)
            guard n >= 2 else { continue }
            total += Float(runs.length(c.x, n - 1))
            count += 1
        }
        guard count > 0 else { return }
        let observed = total / count
        reflectionLengthEMA += 0.2 * (observed - reflectionLengthEMA)
    }
}
