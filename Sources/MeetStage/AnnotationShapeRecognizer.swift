import CoreGraphics
import Foundation

/// Conservatively recognizes closed, single-stroke shapes at pointer-up.
/// Measurements happen in pixels so a wide source window does not distort the
/// user's geometry before it is classified.
enum AnnotationShapeRecognizer {
    private static let sampleCount = 64
    private static let minimumPointCount = 10
    private static let minimumDimension: CGFloat = 24
    private static let minimumPathLength: CGFloat = 72

    static func recognize(
        points: [NormalizedWindowPoint],
        in canvasSize: CGSize
    ) -> AnnotationStrokeGeometry? {
        guard canvasSize.width > 0,
            canvasSize.height > 0,
            points.count >= minimumPointCount
        else { return nil }

        let pixelPoints = points.map {
            CGPoint(x: $0.x * canvasSize.width, y: $0.y * canvasSize.height)
        }
        let pathLength = polylineLength(pixelPoints)
        guard pathLength >= minimumPathLength,
            let samples = resample(pixelPoints, count: sampleCount),
            let bounds = bounds(of: samples),
            bounds.width >= minimumDimension,
            bounds.height >= minimumDimension,
            isClosed(samples, bounds: bounds)
        else { return nil }

        if isRectangle(samples, bounds: bounds, pathLength: pathLength) {
            return .rectangle(normalizedBounds(bounds, in: canvasSize))
        }

        if isCircle(samples, bounds: bounds, pathLength: pathLength) {
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let meanRadius =
                samples.reduce(CGFloat.zero) {
                    $0 + distance($1, center)
                } / CGFloat(samples.count)
            let maximumRadius = min(
                center.x,
                canvasSize.width - center.x,
                center.y,
                canvasSize.height - center.y
            )
            let radius = min(meanRadius, maximumRadius)

            guard radius >= minimumDimension / 2 else { return nil }
            return .circle(
                center: NormalizedWindowPoint(
                    x: center.x / canvasSize.width,
                    y: center.y / canvasSize.height
                ),
                diameter: radius * 2 / min(canvasSize.width, canvasSize.height)
            )
        }

        return nil
    }

    private static func isClosed(_ points: [CGPoint], bounds: CGRect) -> Bool {
        guard let first = points.first, let last = points.last else { return false }
        let tolerance = max(10, min(36, min(bounds.width, bounds.height) * 0.25))
        return distance(first, last) <= tolerance
    }

    private static func isRectangle(
        _ points: [CGPoint],
        bounds: CGRect,
        pathLength: CGFloat
    ) -> Bool {
        let expectedPerimeter = 2 * (bounds.width + bounds.height)
        let perimeterRatio = pathLength / expectedPerimeter
        guard perimeterRatio >= 0.72, perimeterRatio <= 1.45 else { return false }

        let edgeErrors = points.map { point in
            min(
                abs(point.x - bounds.minX) / bounds.width,
                abs(point.x - bounds.maxX) / bounds.width,
                abs(point.y - bounds.minY) / bounds.height,
                abs(point.y - bounds.maxY) / bounds.height
            )
        }
        guard mean(edgeErrors) <= 0.055,
            percentile(edgeErrors, fraction: 0.9) <= 0.11
        else { return false }

        let corners = [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
            CGPoint(x: bounds.minX, y: bounds.maxY)
        ]
        let reachesEveryBoundingCorner = corners.allSatisfy { corner in
            let nearestNormalizedDistance =
                points.map { point in
                    hypot(
                        (point.x - corner.x) / bounds.width,
                        (point.y - corner.y) / bounds.height
                    )
                }.min() ?? .infinity
            return nearestNormalizedDistance <= 0.16
        }
        return reachesEveryBoundingCorner
            || resemblesFourSidedOutline(points, bounds: bounds)
    }

    /// Handles rectangles drawn with noticeably converging sides. A circle
    /// also stays close to its bounding edges, so the fallback requires four
    /// simplified, alternating horizontal/vertical sides with plausible
    /// corner angles before it may snap to a box.
    private static func resemblesFourSidedOutline(
        _ points: [CGPoint],
        bounds: CGRect
    ) -> Bool {
        let tolerance = min(bounds.width, bounds.height) * 0.055
        let vertices = simplifiedClosedVertices(points, tolerance: tolerance)
        guard vertices.count == 4 else { return false }

        let edges = vertices.indices.map { index in
            let start = vertices[index]
            let end = vertices[(index + 1) % vertices.count]
            return CGVector(dx: end.x - start.x, dy: end.y - start.y)
        }
        let lengths = edges.map { hypot($0.dx, $0.dy) }
        let diagonal = hypot(bounds.width, bounds.height)
        guard lengths.allSatisfy({ $0 >= diagonal * 0.14 }) else { return false }

        let horizontalSides = edges.map { abs($0.dx) >= abs($0.dy) }
        guard horizontalSides[0] != horizontalSides[1],
            horizontalSides[1] != horizontalSides[2],
            horizontalSides[2] != horizontalSides[3],
            horizontalSides[3] != horizontalSides[0]
        else { return false }

        for index in edges.indices {
            let first = edges[index]
            let second = edges[(index + 1) % edges.count]
            let normalizedDot =
                abs(first.dx * second.dx + first.dy * second.dy)
                / (lengths[index] * lengths[(index + 1) % lengths.count])
            guard normalizedDot <= 0.7 else { return false }
        }

        for index in 0..<2 {
            let first = edges[index]
            let opposite = edges[index + 2]
            let normalizedCross =
                abs(first.dx * opposite.dy - first.dy * opposite.dx)
                / (lengths[index] * lengths[index + 2])
            guard normalizedCross <= 0.58 else { return false }
        }

        let polygonArea =
            abs(
                vertices.indices.reduce(CGFloat.zero) { area, index in
                    let point = vertices[index]
                    let next = vertices[(index + 1) % vertices.count]
                    return area + point.x * next.y - next.x * point.y
                }
            ) / 2
        return polygonArea / (bounds.width * bounds.height) >= 0.58
    }

    private static func isCircle(
        _ points: [CGPoint],
        bounds: CGRect,
        pathLength: CGFloat
    ) -> Bool {
        let aspectRatio = bounds.width / bounds.height
        guard aspectRatio >= 0.68, aspectRatio <= 1.47 else { return false }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radii = points.map { distance($0, center) }
        let meanRadius = mean(radii)
        guard meanRadius > 0 else { return false }

        let radialErrors = radii.map { abs($0 - meanRadius) / meanRadius }
        guard mean(radialErrors) <= 0.13,
            percentile(radialErrors, fraction: 0.9) <= 0.24
        else { return false }

        let circumferenceRatio = pathLength / (2 * .pi * meanRadius)
        guard circumferenceRatio >= 0.72, circumferenceRatio <= 1.38 else { return false }

        var signedAngularTravel: CGFloat = 0
        var totalAngularTravel: CGFloat = 0
        for pair in zip(points, points.dropFirst()) {
            let startAngle = atan2(pair.0.y - center.y, pair.0.x - center.x)
            let endAngle = atan2(pair.1.y - center.y, pair.1.x - center.x)
            var delta = endAngle - startAngle
            if delta > .pi {
                delta -= 2 * .pi
            } else if delta < -.pi {
                delta += 2 * .pi
            }
            signedAngularTravel += delta
            totalAngularTravel += abs(delta)
        }

        guard totalAngularTravel > 0 else { return false }
        let directionConsistency = abs(signedAngularTravel) / totalAngularTravel
        return abs(signedAngularTravel) >= 5.2
            && totalAngularTravel <= 8.5
            && directionConsistency >= 0.72
    }

    private static func normalizedBounds(
        _ bounds: CGRect,
        in canvasSize: CGSize
    ) -> NormalizedAnnotationBounds {
        NormalizedAnnotationBounds(
            minX: bounds.minX / canvasSize.width,
            minY: bounds.minY / canvasSize.height,
            width: bounds.width / canvasSize.width,
            height: bounds.height / canvasSize.height
        )
    }

    private static func polylineLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(CGFloat.zero) {
            $0 + distance($1.0, $1.1)
        }
    }

    /// Uniform arc-length sampling prevents slow movement near a corner from
    /// receiving more weight than a quickly drawn edge.
    private static func resample(_ points: [CGPoint], count: Int) -> [CGPoint]? {
        guard count >= 2, points.count >= 2 else { return nil }

        var cumulativeLengths = [CGFloat.zero]
        cumulativeLengths.reserveCapacity(points.count)
        for pair in zip(points, points.dropFirst()) {
            let previousLength = cumulativeLengths[cumulativeLengths.count - 1]
            cumulativeLengths.append(previousLength + distance(pair.0, pair.1))
        }

        guard let totalLength = cumulativeLengths.last, totalLength > 0 else { return nil }

        var result: [CGPoint] = []
        result.reserveCapacity(count)
        var segmentIndex = 1

        for sampleIndex in 0..<count {
            let targetLength = totalLength * CGFloat(sampleIndex) / CGFloat(count - 1)
            while segmentIndex < cumulativeLengths.count - 1,
                cumulativeLengths[segmentIndex] < targetLength
            {
                segmentIndex += 1
            }

            let segmentStartLength = cumulativeLengths[segmentIndex - 1]
            let segmentEndLength = cumulativeLengths[segmentIndex]
            let segmentLength = segmentEndLength - segmentStartLength
            let progress =
                segmentLength > 0
                ? (targetLength - segmentStartLength) / segmentLength
                : 0
            let start = points[segmentIndex - 1]
            let end = points[segmentIndex]
            result.append(
                CGPoint(
                    x: start.x + (end.x - start.x) * progress,
                    y: start.y + (end.y - start.y) * progress
                )
            )
        }

        return result
    }

    private static func simplifiedClosedVertices(
        _ points: [CGPoint],
        tolerance: CGFloat
    ) -> [CGPoint] {
        guard points.count >= 4 else { return points }

        var firstIndex = 0
        var secondIndex = 1
        var maximumDistance: CGFloat = 0
        for startIndex in points.indices {
            for endIndex in points.indices where endIndex > startIndex {
                let candidateDistance = distance(points[startIndex], points[endIndex])
                if candidateDistance > maximumDistance {
                    maximumDistance = candidateDistance
                    firstIndex = startIndex
                    secondIndex = endIndex
                }
            }
        }

        let firstArc = Array(points[firstIndex...secondIndex])
        let secondArc = Array(points[secondIndex...]) + Array(points[...firstIndex])
        let simplifiedFirstArc = simplify(firstArc, tolerance: tolerance)
        let simplifiedSecondArc = simplify(secondArc, tolerance: tolerance)
        return Array(simplifiedFirstArc.dropLast())
            + Array(simplifiedSecondArc.dropLast())
    }

    private static func simplify(
        _ points: [CGPoint],
        tolerance: CGFloat
    ) -> [CGPoint] {
        guard points.count > 2,
            let first = points.first,
            let last = points.last
        else { return points }

        var splitIndex = 0
        var maximumDistance: CGFloat = 0
        for index in 1..<(points.count - 1) {
            let candidateDistance = perpendicularDistance(
                points[index],
                from: first,
                to: last
            )
            if candidateDistance > maximumDistance {
                maximumDistance = candidateDistance
                splitIndex = index
            }
        }

        guard maximumDistance > tolerance else { return [first, last] }
        let firstHalf = simplify(Array(points[...splitIndex]), tolerance: tolerance)
        let secondHalf = simplify(Array(points[splitIndex...]), tolerance: tolerance)
        return firstHalf + secondHalf.dropFirst()
    }

    private static func perpendicularDistance(
        _ point: CGPoint,
        from lineStart: CGPoint,
        to lineEnd: CGPoint
    ) -> CGFloat {
        let deltaX = lineEnd.x - lineStart.x
        let deltaY = lineEnd.y - lineStart.y
        let squaredLength = deltaX * deltaX + deltaY * deltaY
        guard squaredLength > 0 else { return distance(point, lineStart) }

        let projection = min(
            max(
                ((point.x - lineStart.x) * deltaX + (point.y - lineStart.y) * deltaY)
                    / squaredLength,
                0
            ),
            1
        )
        let closestPoint = CGPoint(
            x: lineStart.x + projection * deltaX,
            y: lineStart.y + projection * deltaY
        )
        return distance(point, closestPoint)
    }

    private static func bounds(of points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y

        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private static func mean(_ values: [CGFloat]) -> CGFloat {
        values.reduce(CGFloat.zero, +) / CGFloat(values.count)
    }

    private static func percentile(_ values: [CGFloat], fraction: CGFloat) -> CGFloat {
        let sortedValues = values.sorted()
        let index = Int((CGFloat(sortedValues.count - 1) * fraction).rounded(.down))
        return sortedValues[index]
    }
}
