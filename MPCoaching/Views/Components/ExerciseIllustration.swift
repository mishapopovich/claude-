import SwiftUI

/// Movement families. Each one has an animated placard-style drawing, so every exercise has a
/// picture without depending on licensed photos. Drop a real photo into the asset catalog named
/// `exercise-<id>` and `ExercisePicture` shows that instead.
enum MovementPattern {
    case squat, gobletSquat, deadlift, romanianDeadlift, lunge, legPress, hipThrust, legCurl, legExtension, calfRaise
    case benchPress, dumbbellBench, pushUp, dip
    case overheadPress, seatedPress, uprightRow, lateralRaise, facePull
    case latPulldown, pullUp, bentOverRow, cableRow
    case curl, tricepsPushdown, overheadExtension
    case carry, plank, hangingKneeRaise, deadBug, pallofPress
}

// MARK: - Pose model

/// A side-view stick figure described by joint angles (degrees, 0 = straight up, 90 = facing right,
/// 180 = straight down). Positions are computed from fixed segment lengths, so interpolating
/// angles between two poses produces natural-looking motion.
struct Pose {
    var torso: Double = 0
    var thighA: Double = 180, shinA: Double = 180
    var thighB: Double? = nil, shinB: Double? = nil
    var upperArmA: Double = 180, forearmA: Double = 180
    var upperArmB: Double? = nil, forearmB: Double? = nil
    var foot: Double = 90
    /// How the figure is placed: on the floor, or pinned at a point (bars, machines).
    var anchor: Anchor = .floor

    enum Anchor {
        case floor
        case hand(CGPoint)
        case hip(CGPoint)
    }

    func interpolated(to other: Pose, t: Double) -> Pose {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        func mixOpt(_ a: Double?, _ fa: Double, _ b: Double?, _ fb: Double) -> Double? {
            if a == nil && b == nil { return nil }
            return mix(a ?? fa, b ?? fb)
        }
        var p = Pose()
        p.torso = mix(torso, other.torso)
        p.thighA = mix(thighA, other.thighA)
        p.shinA = mix(shinA, other.shinA)
        p.thighB = mixOpt(thighB, thighA, other.thighB, other.thighA)
        p.shinB = mixOpt(shinB, shinA, other.shinB, other.shinA)
        p.upperArmA = mix(upperArmA, other.upperArmA)
        p.forearmA = mix(forearmA, other.forearmA)
        p.upperArmB = mixOpt(upperArmB, upperArmA, other.upperArmB, other.upperArmA)
        p.forearmB = mixOpt(forearmB, forearmA, other.forearmB, other.forearmA)
        p.foot = mix(foot, other.foot)
        switch (anchor, other.anchor) {
        case let (.hand(a), .hand(b)):
            p.anchor = .hand(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        case let (.hip(a), .hip(b)):
            p.anchor = .hip(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        default:
            p.anchor = anchor
        }
        return p
    }
}

/// Joint positions in a 100 x 100 drawing space (y grows downward, floor at y = 92).
struct Skeleton {
    var head: CGPoint
    var shoulder: CGPoint
    var hip: CGPoint
    var kneeA: CGPoint, ankleA: CGPoint, toeA: CGPoint
    var kneeB: CGPoint, ankleB: CGPoint, toeB: CGPoint
    var elbowA: CGPoint, handA: CGPoint
    var elbowB: CGPoint, handB: CGPoint

    static let floorY: CGFloat = 92
    static let thigh: CGFloat = 19, shin: CGFloat = 19, torsoLength: CGFloat = 23
    static let upperArm: CGFloat = 12.5, forearm: CGFloat = 11.5, neck: CGFloat = 8, footLength: CGFloat = 6
    static let headRadius: CGFloat = 5

    init(_ p: Pose) {
        func dir(_ deg: Double) -> CGPoint {
            let r = deg * .pi / 180
            return CGPoint(x: sin(r), y: -cos(r))
        }
        func step(_ from: CGPoint, _ deg: Double, _ len: CGFloat) -> CGPoint {
            let d = dir(deg)
            return CGPoint(x: from.x + d.x * len, y: from.y + d.y * len)
        }
        let hip = CGPoint.zero
        let shoulder = step(hip, p.torso, Skeleton.torsoLength)
        let head = step(shoulder, p.torso, Skeleton.neck)
        let kneeA = step(hip, p.thighA, Skeleton.thigh)
        let ankleA = step(kneeA, p.shinA, Skeleton.shin)
        let toeA = step(ankleA, p.foot, Skeleton.footLength)
        let kneeB = step(hip, p.thighB ?? p.thighA, Skeleton.thigh)
        let ankleB = step(kneeB, p.shinB ?? p.shinA, Skeleton.shin)
        let toeB = step(ankleB, p.foot, Skeleton.footLength)
        let elbowA = step(shoulder, p.upperArmA, Skeleton.upperArm)
        let handA = step(elbowA, p.forearmA, Skeleton.forearm)
        let elbowB = step(shoulder, p.upperArmB ?? p.upperArmA, Skeleton.upperArm)
        let handB = step(elbowB, p.forearmB ?? p.forearmA, Skeleton.forearm)

        self.head = head; self.shoulder = shoulder; self.hip = hip
        self.kneeA = kneeA; self.ankleA = ankleA; self.toeA = toeA
        self.kneeB = kneeB; self.ankleB = ankleB; self.toeB = toeB
        self.elbowA = elbowA; self.handA = handA
        self.elbowB = elbowB; self.handB = handB

        // Place the figure in the frame.
        let offset: CGPoint
        switch p.anchor {
        case .floor:
            let points = [head, shoulder, hip, kneeA, ankleA, toeA, kneeB, ankleB, toeB, elbowA, handA, elbowB, handB]
            let lowest = points.map(\.y).max() ?? 0
            let xs = points.map(\.x)
            let midX = ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2
            offset = CGPoint(x: 50 - midX, y: Skeleton.floorY - lowest)
        case .hand(let target):
            offset = CGPoint(x: target.x - handA.x, y: target.y - handA.y)
        case .hip(let target):
            offset = target
        }
        translate(by: offset)
    }

    private mutating func translate(by o: CGPoint) {
        func t(_ p: inout CGPoint) { p = CGPoint(x: p.x + o.x, y: p.y + o.y) }
        t(&head); t(&shoulder); t(&hip)
        t(&kneeA); t(&ankleA); t(&toeA)
        t(&kneeB); t(&ankleB); t(&toeB)
        t(&elbowA); t(&handA); t(&elbowB); t(&handB)
    }
}

// MARK: - Props

enum Prop {
    case barbellAtHands
    case barbellAtHip
    case dumbbells
    case kettlebellAtChest
    case bench           // flat bench under hip and shoulders
    case benchUnderShoulders
    case seat            // box seat under the hip
    case cableFromAbove
    case cableFromFront
    case bar(CGPoint)    // fixed bar (pull-up bar / dip bars)
    case platformAtFeet
    case padAtShin
}

struct MovementAnimation {
    let start: Pose
    let end: Pose
    let props: [Prop]
    /// Seconds for one full rep (start → end → start).
    var period: Double = 2.6
}

extension MovementPattern {
    var animation: MovementAnimation {
        switch self {
        case .squat:
            return .init(
                start: Pose(upperArmA: 210, forearmA: 20),
                end: Pose(torso: 38, thighA: 100, shinA: 200, upperArmA: 245, forearmA: 55),
                props: [.barbellAtHands])
        case .gobletSquat:
            return .init(
                start: Pose(upperArmA: 165, forearmA: 15),
                end: Pose(torso: 22, thighA: 98, shinA: 200, upperArmA: 185, forearmA: 30),
                props: [.kettlebellAtChest])
        case .deadlift:
            return .init(
                start: Pose(torso: 68, thighA: 122, shinA: 196),
                end: Pose(),
                props: [.barbellAtHands], period: 3)
        case .romanianDeadlift:
            return .init(
                start: Pose(),
                end: Pose(torso: 78, thighA: 165, shinA: 182),
                props: [.barbellAtHands], period: 3)
        case .lunge:
            return .init(
                start: Pose(),
                end: Pose(thighA: 95, shinA: 183, thighB: 190, shinB: 262, foot: 90),
                props: [.dumbbells], period: 3)
        case .legPress:
            let hip = CGPoint(x: 34, y: 66)
            return .init(
                start: Pose(torso: 300, thighA: 28, shinA: 125, upperArmA: 200, forearmA: 150, foot: 30, anchor: .hip(hip)),
                end: Pose(torso: 300, thighA: 58, shinA: 62, upperArmA: 200, forearmA: 150, foot: 330, anchor: .hip(hip)),
                props: [.seat, .platformAtFeet])
        case .hipThrust:
            return .init(
                start: Pose(torso: 300, thighA: 70, shinA: 172, upperArmA: 120, forearmA: 120),
                end: Pose(torso: 278, thighA: 88, shinA: 180, upperArmA: 105, forearmA: 100),
                props: [.benchUnderShoulders, .barbellAtHip])
        case .legCurl:
            let hip = CGPoint(x: 40, y: 62)
            return .init(
                start: Pose(torso: 350, thighA: 90, shinA: 115, upperArmA: 175, forearmA: 120, anchor: .hip(hip)),
                end: Pose(torso: 350, thighA: 90, shinA: 205, upperArmA: 175, forearmA: 120, anchor: .hip(hip)),
                props: [.seat, .padAtShin])
        case .legExtension:
            let hip = CGPoint(x: 40, y: 62)
            return .init(
                start: Pose(torso: 350, thighA: 90, shinA: 185, upperArmA: 175, forearmA: 120, anchor: .hip(hip)),
                end: Pose(torso: 350, thighA: 90, shinA: 95, upperArmA: 175, forearmA: 120, anchor: .hip(hip)),
                props: [.seat, .padAtShin])
        case .calfRaise:
            return .init(start: Pose(), end: Pose(foot: 140), props: [.dumbbells], period: 2)
        case .benchPress:
            return .init(
                start: Pose(torso: 90, thighA: 255, shinA: 182, upperArmA: 178, forearmA: 0),
                end: Pose(torso: 90, thighA: 255, shinA: 182, upperArmA: 2, forearmA: 0),
                props: [.bench, .barbellAtHands])
        case .dumbbellBench:
            return .init(
                start: Pose(torso: 90, thighA: 255, shinA: 182, upperArmA: 182, forearmA: 0),
                end: Pose(torso: 90, thighA: 255, shinA: 182, upperArmA: 0, forearmA: 0),
                props: [.bench, .dumbbells])
        case .pushUp:
            return .init(
                start: Pose(torso: 76, thighA: 256, shinA: 256, upperArmA: 180, forearmA: 180, foot: 180),
                end: Pose(torso: 76, thighA: 256, shinA: 256, upperArmA: 238, forearmA: 140, foot: 180),
                props: [])
        case .dip:
            let bar = CGPoint(x: 50, y: 50)
            return .init(
                start: Pose(torso: 8, thighA: 175, shinA: 225, upperArmA: 182, forearmA: 180, anchor: .hand(bar)),
                end: Pose(torso: 20, thighA: 170, shinA: 230, upperArmA: 245, forearmA: 165, anchor: .hand(bar)),
                props: [.bar(bar)])
        case .overheadPress:
            return .init(
                start: Pose(upperArmA: 170, forearmA: 8),
                end: Pose(upperArmA: 2, forearmA: 0),
                props: [.dumbbells])
        case .seatedPress:
            return .init(
                start: Pose(thighA: 90, shinA: 180, upperArmA: 170, forearmA: 8),
                end: Pose(thighA: 90, shinA: 180, upperArmA: 2, forearmA: 0),
                props: [.seat, .dumbbells])
        case .uprightRow:
            return .init(
                start: Pose(upperArmA: 178, forearmA: 180),
                end: Pose(upperArmA: 62, forearmA: 218),
                props: [.dumbbells])
        case .lateralRaise:
            return .init(
                start: Pose(upperArmA: 175, forearmA: 172),
                end: Pose(upperArmA: 95, forearmA: 92),
                props: [.dumbbells], period: 2.2)
        case .facePull:
            return .init(
                start: Pose(upperArmA: 82, forearmA: 82),
                end: Pose(upperArmA: 100, forearmA: 330),
                props: [.cableFromFront])
        case .latPulldown:
            return .init(
                start: Pose(torso: 352, thighA: 90, shinA: 180, upperArmA: 8, forearmA: 8),
                end: Pose(torso: 345, thighA: 90, shinA: 180, upperArmA: 198, forearmA: 12),
                props: [.seat, .cableFromAbove])
        case .pullUp:
            let bar = CGPoint(x: 54, y: 20)
            return .init(
                start: Pose(torso: 0, thighA: 175, shinA: 200, upperArmA: 4, forearmA: 2, foot: 150, anchor: .hand(bar)),
                end: Pose(torso: 350, thighA: 170, shinA: 205, upperArmA: 200, forearmA: 14, foot: 150, anchor: .hand(bar)),
                props: [.bar(bar)])
        case .bentOverRow:
            return .init(
                start: Pose(torso: 62, thighA: 160, shinA: 190, upperArmA: 180, forearmA: 180),
                end: Pose(torso: 62, thighA: 160, shinA: 190, upperArmA: 250, forearmA: 170),
                props: [.barbellAtHands])
        case .cableRow:
            return .init(
                start: Pose(torso: 15, thighA: 82, shinA: 120, upperArmA: 85, forearmA: 85, foot: 20),
                end: Pose(torso: 355, thighA: 82, shinA: 120, upperArmA: 200, forearmA: 95, foot: 20),
                props: [.cableFromFront])
        case .curl:
            return .init(
                start: Pose(upperArmA: 180, forearmA: 180),
                end: Pose(upperArmA: 176, forearmA: 22),
                props: [.dumbbells], period: 2.2)
        case .tricepsPushdown:
            return .init(
                start: Pose(torso: 8, upperArmA: 182, forearmA: 40),
                end: Pose(torso: 8, upperArmA: 182, forearmA: 180),
                props: [.cableFromAbove], period: 2.2)
        case .overheadExtension:
            return .init(
                start: Pose(upperArmA: 352, forearmA: 200),
                end: Pose(upperArmA: 356, forearmA: 0),
                props: [.dumbbells], period: 2.4)
        case .carry:
            return .init(
                start: Pose(thighA: 160, shinA: 182, thighB: 200, shinB: 205),
                end: Pose(thighA: 200, shinA: 205, thighB: 160, shinB: 182),
                props: [.dumbbells], period: 1.4)
        case .plank:
            return .init(
                start: Pose(torso: 78, thighA: 258, shinA: 258, upperArmA: 180, forearmA: 90, foot: 180),
                end: Pose(torso: 80, thighA: 259, shinA: 259, upperArmA: 180, forearmA: 90, foot: 180),
                props: [], period: 3)
        case .hangingKneeRaise:
            let bar = CGPoint(x: 54, y: 20)
            return .init(
                start: Pose(torso: 0, thighA: 180, shinA: 185, upperArmA: 2, forearmA: 0, foot: 150, anchor: .hand(bar)),
                end: Pose(torso: 350, thighA: 70, shinA: 175, upperArmA: 2, forearmA: 0, foot: 150, anchor: .hand(bar)),
                props: [.bar(bar)])
        case .deadBug:
            return .init(
                start: Pose(torso: 270, thighA: 0, shinA: 90, upperArmA: 0, forearmA: 0, foot: 0),
                end: Pose(torso: 270, thighA: 0, shinA: 90, thighB: 75, shinB: 80, upperArmA: 0, forearmA: 0, upperArmB: 280, forearmB: 280, foot: 0),
                props: [], period: 3)
        case .pallofPress:
            return .init(
                start: Pose(upperArmA: 165, forearmA: 20),
                end: Pose(upperArmA: 92, forearmA: 90),
                props: [.cableFromFront])
        }
    }
}

// MARK: - Muscle highlighting on the figure

/// Body parts of the side-view figure that can light up.
enum FigurePart: Hashable {
    case neck, shoulder, chestBack, midsection, hip, thigh, shin, upperArm, forearm
}

enum MuscleMapping {
    /// Which figure parts a muscle name lights up.
    static func figureParts(_ muscle: String) -> Set<FigurePart> {
        switch muscle.lowercased() {
        case "quads", "hamstrings", "adductors": [.thigh]
        case "glutes": [.hip]
        case "calves": [.shin]
        case "chest", "upper chest", "lats", "mid back", "upper back": [.chestBack]
        case "abs", "core", "obliques", "lower back", "hip flexors": [.midsection]
        case "front delts", "side delts", "rear delts", "shoulders", "rotator cuff": [.shoulder]
        case "traps": [.neck]
        case "biceps", "triceps", "brachialis": [.upperArm]
        case "forearms", "grip": [.forearm]
        default: []
        }
    }

    static func figureParts(_ muscles: [String]) -> Set<FigurePart> {
        muscles.reduce(into: Set<FigurePart>()) { $0.formUnion(figureParts($1)) }
    }
}

// MARK: - Views

/// Shows the bundled photo for an exercise if there is one, otherwise the placard-style drawing.
struct ExercisePicture: View {
    let exercise: Exercise
    var animated: Bool = true
    var showArrow: Bool = true

    var body: some View {
        Group {
            if let image = UIImage(named: exercise.photoAssetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ExerciseIllustration(
                    pattern: exercise.pattern,
                    primary: MuscleMapping.figureParts(exercise.primaryMuscles),
                    secondary: MuscleMapping.figureParts(exercise.secondaryMuscles),
                    animated: animated,
                    showArrow: showArrow && animated)
            }
        }
        .accessibilityLabel("Picture of \(exercise.name), works \(exercise.primaryMuscles.joined(separator: ", "))")
    }
}

/// Machine-placard style drawing: a solid neutral figure, the working muscles lit in blue,
/// and a dashed arrow tracing the movement path.
struct ExerciseIllustration: View {
    let pattern: MovementPattern
    var primary: Set<FigurePart> = []
    var secondary: Set<FigurePart> = []
    var animated: Bool = true
    var showArrow: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let anim = pattern.animation
        Group {
            if animated && !reduceMotion {
                TimelineView(.animation) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    let phase = (time.truncatingRemainder(dividingBy: anim.period)) / anim.period
                    // Smooth there-and-back: 0 → 1 → 0 over one period.
                    let t = (1 - cos(phase * 2 * .pi)) / 2
                    figure(anim.start.interpolated(to: anim.end, t: t), anim: anim)
                }
            } else {
                figure(anim.start.interpolated(to: anim.end, t: 0.85), anim: anim)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func figure(_ pose: Pose, anim: MovementAnimation) -> some View {
        let props = anim.props
        let arrow = showArrow ? MotionPath(anim) : nil
        let primary = self.primary
        let secondary = self.secondary.subtracting(primary)
        return Canvas { ctx, size in
            let s = min(size.width, size.height) / 100
            let ox = (size.width - 100 * s) / 2
            let oy = (size.height - 100 * s) / 2
            func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: ox + p.x * s, y: oy + p.y * s) }

            let sk = Skeleton(pose)
            let body = GraphicsContext.Shading.color(Theme.figure)
            let bodyFar = GraphicsContext.Shading.color(Theme.figureFaint)
            let hot = GraphicsContext.Shading.color(Theme.blue)
            let warm = GraphicsContext.Shading.color(Theme.blue.opacity(0.45))
            let equipment = GraphicsContext.Shading.color(Color(.systemGray2))
            let plate = GraphicsContext.Shading.color(Color(.systemGray))

            func capsule(_ pts: [CGPoint], _ shading: GraphicsContext.Shading, width: CGFloat) {
                var path = Path()
                path.addLines(pts.map(pt))
                ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: width * s, lineCap: .round, lineJoin: .round))
            }
            func rect(_ r: CGRect, _ shading: GraphicsContext.Shading) {
                let path = Path(roundedRect: CGRect(x: ox + r.minX * s, y: oy + r.minY * s, width: r.width * s, height: r.height * s), cornerRadius: 1.2 * s)
                ctx.fill(path, with: shading)
            }
            func circle(_ c: CGPoint, r: CGFloat, _ shading: GraphicsContext.Shading, stroke: CGFloat? = nil) {
                let p = pt(c)
                let path = Path(ellipseIn: CGRect(x: p.x - r * s, y: p.y - r * s, width: 2 * r * s, height: 2 * r * s))
                if let stroke { ctx.stroke(path, with: shading, lineWidth: stroke * s) } else { ctx.fill(path, with: shading) }
            }
            func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
                CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            func shade(_ part: FigurePart) -> GraphicsContext.Shading? {
                if primary.contains(part) { return hot }
                if secondary.contains(part) { return warm }
                return nil
            }
            /// Draws a limb segment, then its muscle highlight on top (slightly thinner so the outline shows).
            func limb(_ a: CGPoint, _ b: CGPoint, _ part: FigurePart, width: CGFloat, base: GraphicsContext.Shading, highlight: Bool = true) {
                capsule([a, b], base, width: width)
                if highlight, let h = shade(part) {
                    capsule([lerp(a, b, 0.12), lerp(a, b, 0.88)], h, width: width * 0.62)
                }
            }

            // Floor
            capsule([CGPoint(x: 6, y: Skeleton.floorY + 3), CGPoint(x: 94, y: Skeleton.floorY + 3)], equipment, width: 1.4)

            // Equipment behind the body
            for prop in props {
                switch prop {
                case .bench:
                    let left = min(sk.hip.x, sk.shoulder.x) - 7
                    let right = max(sk.hip.x, sk.shoulder.x) + 5
                    let top = max(sk.hip.y, sk.shoulder.y) + 4
                    rect(CGRect(x: left, y: top, width: right - left, height: 4.5), equipment)
                    rect(CGRect(x: left + 3, y: top + 4, width: 2.5, height: max(0, Skeleton.floorY + 3 - top - 4)), equipment)
                    rect(CGRect(x: right - 5.5, y: top + 4, width: 2.5, height: max(0, Skeleton.floorY + 3 - top - 4)), equipment)
                case .benchUnderShoulders:
                    let top = sk.shoulder.y + 4
                    rect(CGRect(x: sk.shoulder.x - 13, y: top, width: 15, height: max(0, Skeleton.floorY + 3 - top)), equipment)
                case .seat:
                    let top = sk.hip.y + 4
                    rect(CGRect(x: sk.hip.x - 10, y: top, width: 18, height: 4), equipment)
                    rect(CGRect(x: sk.hip.x - 2.5, y: top + 4, width: 3.5, height: max(0, Skeleton.floorY + 3 - top - 4)), equipment)
                case .cableFromAbove:
                    capsule([CGPoint(x: sk.handA.x + 2, y: 2), sk.handA], equipment, width: 1)
                    rect(CGRect(x: sk.handA.x - 4, y: 0, width: 12, height: 2.5), equipment)
                case .cableFromFront:
                    rect(CGRect(x: 95, y: 4, width: 4, height: Skeleton.floorY - 1), equipment)
                    capsule([CGPoint(x: 95, y: sk.handA.y - 2), sk.handA], equipment, width: 1)
                case .bar(let p):
                    capsule([CGPoint(x: p.x - 15, y: p.y), CGPoint(x: p.x + 15, y: p.y)], equipment, width: 2.4)
                case .platformAtFeet:
                    let c = lerp(sk.ankleA, sk.toeA, 0.5)
                    capsule([CGPoint(x: c.x + 4, y: c.y - 10), CGPoint(x: c.x + 10, y: c.y + 10)], equipment, width: 3)
                default:
                    break
                }
            }

            // Far side of the body (muted), then torso, then near side.
            capsule([sk.hip, sk.kneeB, sk.ankleB], bodyFar, width: 7)
            capsule([sk.ankleB, sk.toeB], bodyFar, width: 4)
            capsule([sk.shoulder, sk.elbowB, sk.handB], bodyFar, width: 5.5)

            let mid = lerp(sk.hip, sk.shoulder, 0.5)
            limb(sk.hip, sk.shoulder, .chestBack, width: 11, base: body, highlight: false)
            if let h = shade(.midsection) { capsule([lerp(sk.hip, sk.shoulder, 0.15), mid], h, width: 7) }
            if let h = shade(.chestBack) { capsule([mid, lerp(sk.hip, sk.shoulder, 0.88)], h, width: 7) }
            capsule([sk.shoulder, sk.head], body, width: 4.5)
            if let h = shade(.neck) { capsule([sk.shoulder, lerp(sk.shoulder, sk.head, 0.6)], h, width: 4) }
            circle(sk.head, r: Skeleton.headRadius + 0.8, body)
            if let h = shade(.hip) { circle(sk.hip, r: 4.6, h) }

            limb(sk.hip, sk.kneeA, .thigh, width: 8, base: body)
            limb(sk.kneeA, sk.ankleA, .shin, width: 6.5, base: body)
            capsule([sk.ankleA, sk.toeA], body, width: 4.5)
            limb(sk.shoulder, sk.elbowA, .upperArm, width: 6, base: body)
            limb(sk.elbowA, sk.handA, .forearm, width: 5, base: body)
            if let h = shade(.shoulder) { circle(sk.shoulder, r: 3.6, h) }

            // Equipment in front of the body
            for prop in props {
                switch prop {
                case .barbellAtHands:
                    circle(sk.handA, r: 8.5, plate)
                    circle(sk.handA, r: 8.5, equipment, stroke: 1.2)
                    circle(sk.handA, r: 1.8, equipment)
                case .barbellAtHip:
                    let c = CGPoint(x: sk.hip.x + 1, y: sk.hip.y - 6)
                    circle(c, r: 8.5, plate)
                    circle(c, r: 1.8, equipment)
                case .dumbbells:
                    rect(CGRect(x: sk.handA.x - 5, y: sk.handA.y - 1.2, width: 10, height: 2.4), equipment)
                    rect(CGRect(x: sk.handA.x - 6, y: sk.handA.y - 3.2, width: 3, height: 6.4), plate)
                    rect(CGRect(x: sk.handA.x + 3, y: sk.handA.y - 3.2, width: 3, height: 6.4), plate)
                case .kettlebellAtChest:
                    circle(CGPoint(x: sk.handA.x + 2, y: sk.handA.y + 2.5), r: 4, plate)
                case .padAtShin:
                    circle(lerp(sk.kneeA, sk.ankleA, 0.8), r: 3, equipment)
                default:
                    break
                }
            }

            // Movement path arrow
            if let arrow {
                var path = Path()
                path.move(to: pt(arrow.from))
                path.addQuadCurve(to: pt(arrow.to), control: pt(arrow.control))
                ctx.stroke(path, with: hot, style: StrokeStyle(lineWidth: 1.4 * s, lineCap: .round, dash: [3 * s, 2.5 * s]))
                for (tip, toward) in [(arrow.to, arrow.control), (arrow.from, arrow.control)] {
                    let dx = tip.x - toward.x, dy = tip.y - toward.y
                    let len = max(0.001, (dx * dx + dy * dy).squareRoot())
                    let ux = dx / len, uy = dy / len
                    var head = Path()
                    head.move(to: pt(tip))
                    head.addLine(to: pt(CGPoint(x: tip.x - ux * 4 - uy * 2.6, y: tip.y - uy * 4 + ux * 2.6)))
                    head.addLine(to: pt(CGPoint(x: tip.x - ux * 4 + uy * 2.6, y: tip.y - uy * 4 - ux * 2.6)))
                    head.closeSubpath()
                    ctx.fill(head, with: hot)
                }
            }
        }
    }
}

/// The path of the joint that moves the most between the two poses, bowed slightly outward.
struct MotionPath {
    let from: CGPoint
    let to: CGPoint
    let control: CGPoint

    init?(_ anim: MovementAnimation) {
        let a = Skeleton(anim.start), b = Skeleton(anim.end)
        let pairs: [(CGPoint, CGPoint)] = [(a.handA, b.handA), (a.hip, b.hip), (a.shoulder, b.shoulder), (a.ankleA, b.ankleA), (a.kneeA, b.kneeA)]
        func dist(_ p: (CGPoint, CGPoint)) -> CGFloat { hypot(p.1.x - p.0.x, p.1.y - p.0.y) }
        guard let best = pairs.max(by: { dist($0) < dist($1) }), dist(best) > 6 else { return nil }
        // Pull the ends in a little so the arrowheads don't sit on the joint, and offset sideways.
        let dx = best.1.x - best.0.x, dy = best.1.y - best.0.y
        let len = hypot(dx, dy)
        let nx = -dy / len, ny = dx / len
        let side: CGFloat = 7
        from = CGPoint(x: best.0.x + dx * 0.08 + nx * side, y: best.0.y + dy * 0.08 + ny * side)
        to = CGPoint(x: best.1.x - dx * 0.08 + nx * side, y: best.1.y - dy * 0.08 + ny * side)
        control = CGPoint(x: (from.x + to.x) / 2 + nx * len * 0.18, y: (from.y + to.y) / 2 + ny * len * 0.18)
    }
}

// MARK: - Muscle map (front and back)

/// Regions on the front/back anatomy chart.
enum MuscleRegion: Hashable {
    case frontDelts, rearDelts, chest, biceps, forearms, abs, obliques, hipFlexors, quads, adductors
    case traps, lats, midBack, lowerBack, triceps, glutes, hamstrings, calves

    static func regions(for muscle: String) -> Set<MuscleRegion> {
        switch muscle.lowercased() {
        case "front delts": [.frontDelts]
        case "side delts", "shoulders": [.frontDelts, .rearDelts]
        case "rear delts", "rotator cuff": [.rearDelts]
        case "chest", "upper chest": [.chest]
        case "biceps", "brachialis": [.biceps]
        case "forearms", "grip": [.forearms]
        case "abs": [.abs]
        case "core": [.abs, .obliques, .lowerBack]
        case "obliques": [.obliques]
        case "hip flexors": [.hipFlexors]
        case "quads": [.quads]
        case "adductors": [.adductors]
        case "traps": [.traps]
        case "upper back": [.traps, .midBack, .rearDelts]
        case "lats": [.lats]
        case "mid back": [.midBack]
        case "lower back": [.lowerBack]
        case "triceps": [.triceps]
        case "glutes": [.glutes]
        case "hamstrings": [.hamstrings]
        case "calves": [.calves]
        default: []
        }
    }

    static func regions(for muscles: [String]) -> Set<MuscleRegion> {
        muscles.reduce(into: Set<MuscleRegion>()) { $0.formUnion(regions(for: $1)) }
    }
}

/// Front and back anatomy chart with primary muscles in blue and secondary muscles in light blue,
/// like the diagram printed on gym machines.
struct MuscleMapView: View {
    let primary: [String]
    let secondary: [String]
    var showLegend = true

    private struct Shape2D {
        let region: MuscleRegion?
        let rect: CGRect
        var oval = false
    }

    // Coordinates in a 50 x 100 box per figure.
    private static let front: [Shape2D] = [
        Shape2D(region: .frontDelts, rect: CGRect(x: 7, y: 15, width: 9, height: 9), oval: true),
        Shape2D(region: .frontDelts, rect: CGRect(x: 34, y: 15, width: 9, height: 9), oval: true),
        Shape2D(region: .chest, rect: CGRect(x: 15, y: 17, width: 9.6, height: 11)),
        Shape2D(region: .chest, rect: CGRect(x: 25.4, y: 17, width: 9.6, height: 11)),
        Shape2D(region: .biceps, rect: CGRect(x: 6.5, y: 24.5, width: 6, height: 13), oval: true),
        Shape2D(region: .biceps, rect: CGRect(x: 37.5, y: 24.5, width: 6, height: 13), oval: true),
        Shape2D(region: .forearms, rect: CGRect(x: 5, y: 38.5, width: 5.5, height: 14), oval: true),
        Shape2D(region: .forearms, rect: CGRect(x: 39.5, y: 38.5, width: 5.5, height: 14), oval: true),
        Shape2D(region: .abs, rect: CGRect(x: 19.5, y: 29, width: 11, height: 18)),
        Shape2D(region: .obliques, rect: CGRect(x: 15, y: 29.5, width: 4, height: 15)),
        Shape2D(region: .obliques, rect: CGRect(x: 31, y: 29.5, width: 4, height: 15)),
        Shape2D(region: .hipFlexors, rect: CGRect(x: 17, y: 47.5, width: 6.5, height: 5)),
        Shape2D(region: .hipFlexors, rect: CGRect(x: 26.5, y: 47.5, width: 6.5, height: 5)),
        Shape2D(region: .quads, rect: CGRect(x: 14.5, y: 53, width: 9, height: 24), oval: true),
        Shape2D(region: .quads, rect: CGRect(x: 26.5, y: 53, width: 9, height: 24), oval: true),
        Shape2D(region: .adductors, rect: CGRect(x: 22.5, y: 53, width: 5, height: 13), oval: true),
        Shape2D(region: .calves, rect: CGRect(x: 15.5, y: 79, width: 7, height: 15), oval: true),
        Shape2D(region: .calves, rect: CGRect(x: 27.5, y: 79, width: 7, height: 15), oval: true),
    ]

    private static let back: [Shape2D] = [
        Shape2D(region: .traps, rect: CGRect(x: 17, y: 13, width: 16, height: 10)),
        Shape2D(region: .rearDelts, rect: CGRect(x: 7, y: 15, width: 9, height: 9), oval: true),
        Shape2D(region: .rearDelts, rect: CGRect(x: 34, y: 15, width: 9, height: 9), oval: true),
        Shape2D(region: .lats, rect: CGRect(x: 14.5, y: 24, width: 7.5, height: 18)),
        Shape2D(region: .lats, rect: CGRect(x: 28, y: 24, width: 7.5, height: 18)),
        Shape2D(region: .midBack, rect: CGRect(x: 22, y: 23.5, width: 6, height: 15)),
        Shape2D(region: .lowerBack, rect: CGRect(x: 19.5, y: 39, width: 11, height: 9)),
        Shape2D(region: .triceps, rect: CGRect(x: 6.5, y: 24.5, width: 6, height: 13), oval: true),
        Shape2D(region: .triceps, rect: CGRect(x: 37.5, y: 24.5, width: 6, height: 13), oval: true),
        Shape2D(region: .forearms, rect: CGRect(x: 5, y: 38.5, width: 5.5, height: 14), oval: true),
        Shape2D(region: .forearms, rect: CGRect(x: 39.5, y: 38.5, width: 5.5, height: 14), oval: true),
        Shape2D(region: .glutes, rect: CGRect(x: 15, y: 48.5, width: 9.6, height: 11), oval: true),
        Shape2D(region: .glutes, rect: CGRect(x: 25.4, y: 48.5, width: 9.6, height: 11), oval: true),
        Shape2D(region: .hamstrings, rect: CGRect(x: 14.5, y: 60, width: 9, height: 18), oval: true),
        Shape2D(region: .hamstrings, rect: CGRect(x: 26.5, y: 60, width: 9, height: 18), oval: true),
        Shape2D(region: .calves, rect: CGRect(x: 15.5, y: 79, width: 7, height: 15), oval: true),
        Shape2D(region: .calves, rect: CGRect(x: 27.5, y: 79, width: 7, height: 15), oval: true),
    ]

    var body: some View {
        let hot = MuscleRegion.regions(for: primary)
        let warm = MuscleRegion.regions(for: secondary).subtracting(hot)
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                chart(Self.front, label: "Front", hot: hot, warm: warm)
                chart(Self.back, label: "Back", hot: hot, warm: warm)
            }
            if showLegend {
                HStack(spacing: 12) {
                    legend(Theme.blue, "Primary")
                    legend(Theme.blue.opacity(0.45), "Secondary")
                }
                .font(.caption2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Works \(primary.joined(separator: ", "))" + (secondary.isEmpty ? "" : ", also \(secondary.joined(separator: ", "))"))
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func chart(_ shapes: [Shape2D], label: String, hot: Set<MuscleRegion>, warm: Set<MuscleRegion>) -> some View {
        VStack(spacing: 2) {
            Canvas { ctx, size in
                let s = min(size.width / 50, size.height / 100)
                let ox = (size.width - 50 * s) / 2
                let oy = (size.height - 100 * s) / 2
                func r(_ rect: CGRect) -> CGRect {
                    CGRect(x: ox + rect.minX * s, y: oy + rect.minY * s, width: rect.width * s, height: rect.height * s)
                }
                let base = GraphicsContext.Shading.color(Theme.figureFaint)
                // Head, neck, hands, feet, pelvis: the silhouette pieces that never light up.
                ctx.fill(Path(ellipseIn: r(CGRect(x: 20, y: 1, width: 10, height: 11))), with: base)
                ctx.fill(Path(roundedRect: r(CGRect(x: 22.5, y: 10, width: 5, height: 5)), cornerRadius: 1 * s), with: base)
                ctx.fill(Path(ellipseIn: r(CGRect(x: 4.5, y: 52, width: 5, height: 6))), with: base)
                ctx.fill(Path(ellipseIn: r(CGRect(x: 40.5, y: 52, width: 5, height: 6))), with: base)
                ctx.fill(Path(roundedRect: r(CGRect(x: 15, y: 93.5, width: 8, height: 4)), cornerRadius: 2 * s), with: base)
                ctx.fill(Path(roundedRect: r(CGRect(x: 27, y: 93.5, width: 8, height: 4)), cornerRadius: 2 * s), with: base)
                for shape in shapes {
                    let color: Color
                    if let region = shape.region, hot.contains(region) {
                        color = Theme.blue
                    } else if let region = shape.region, warm.contains(region) {
                        color = Theme.blue.opacity(0.45)
                    } else {
                        color = Theme.figureFaint
                    }
                    let rect = r(shape.rect)
                    let path = shape.oval ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 2.2 * s)
                    ctx.fill(path, with: .color(color))
                }
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// The full "machine placard": animated movement on the left, muscle chart on the right.
struct ExercisePlacard: View {
    let exercise: Exercise

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ExercisePicture(exercise: exercise)
                .frame(maxWidth: .infinity)
            MuscleMapView(primary: exercise.primaryMuscles, secondary: exercise.secondaryMuscles)
                .frame(width: 120, height: 170)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(ExerciseCatalog.all) { ex in
                VStack(alignment: .leading) {
                    Text(ex.name).font(.headline)
                    ExercisePlacard(exercise: ex).frame(height: 200)
                }
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
