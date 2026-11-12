import SwiftUI

/// Movement families. Each one has an animated stick-figure drawing, so every exercise has a
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
            let bar = CGPoint(x: 54, y: 12)
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
            let bar = CGPoint(x: 54, y: 12)
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

// MARK: - Views

/// Shows the bundled photo for an exercise if there is one, otherwise the animated drawing.
struct ExercisePicture: View {
    let exercise: Exercise
    var animated: Bool = true

    var body: some View {
        Group {
            if let image = UIImage(named: exercise.photoAssetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ExerciseIllustration(pattern: exercise.pattern, animated: animated)
            }
        }
        .accessibilityLabel("Picture of \(exercise.name)")
    }
}

struct ExerciseIllustration: View {
    let pattern: MovementPattern
    var animated: Bool = true

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
                    figure(anim.start.interpolated(to: anim.end, t: t), props: anim.props)
                }
            } else {
                // Static thumbnail: show the hardest point of the movement.
                figure(anim.start.interpolated(to: anim.end, t: 0.85), props: anim.props)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func figure(_ pose: Pose, props: [Prop]) -> some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 100
            let ox = (size.width - 100 * s) / 2
            let oy = (size.height - 100 * s) / 2
            func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: ox + p.x * s, y: oy + p.y * s) }

            let sk = Skeleton(pose)
            let ink = GraphicsContext.Shading.color(.primary)
            let faint = GraphicsContext.Shading.color(.primary.opacity(0.35))
            let accent = GraphicsContext.Shading.color(.accentColor)
            let equipment = GraphicsContext.Shading.color(.secondary)
            let limb = StrokeStyle(lineWidth: 3.2 * s, lineCap: .round, lineJoin: .round)

            func line(_ pts: [CGPoint], _ shading: GraphicsContext.Shading, width: CGFloat? = nil) {
                var path = Path()
                path.addLines(pts.map(pt))
                ctx.stroke(path, with: shading, style: width.map { StrokeStyle(lineWidth: $0 * s, lineCap: .round, lineJoin: .round) } ?? limb)
            }
            func rect(_ r: CGRect, _ shading: GraphicsContext.Shading) {
                let path = Path(roundedRect: CGRect(x: ox + r.minX * s, y: oy + r.minY * s, width: r.width * s, height: r.height * s), cornerRadius: 1.2 * s)
                ctx.fill(path, with: shading)
            }
            func circle(_ c: CGPoint, r: CGFloat, _ shading: GraphicsContext.Shading, filled: Bool = true) {
                let p = pt(c)
                let path = Path(ellipseIn: CGRect(x: p.x - r * s, y: p.y - r * s, width: 2 * r * s, height: 2 * r * s))
                if filled { ctx.fill(path, with: shading) } else { ctx.stroke(path, with: shading, lineWidth: 2 * s) }
            }

            // Floor
            line([CGPoint(x: 6, y: Skeleton.floorY + 2), CGPoint(x: 94, y: Skeleton.floorY + 2)], equipment, width: 1.2)

            // Equipment behind the body
            for prop in props {
                switch prop {
                case .bench:
                    let left = min(sk.hip.x, sk.shoulder.x) - 6
                    let right = max(sk.hip.x, sk.shoulder.x) + 4
                    let top = max(sk.hip.y, sk.shoulder.y) + 2.5
                    rect(CGRect(x: left, y: top, width: right - left, height: 4), equipment)
                    rect(CGRect(x: left + 3, y: top + 4, width: 2.5, height: Skeleton.floorY + 2 - top - 4), equipment)
                    rect(CGRect(x: right - 5.5, y: top + 4, width: 2.5, height: Skeleton.floorY + 2 - top - 4), equipment)
                case .benchUnderShoulders:
                    let top = sk.shoulder.y + 2.5
                    rect(CGRect(x: sk.shoulder.x - 12, y: top, width: 14, height: Skeleton.floorY + 2 - top), equipment)
                case .seat:
                    let top = sk.hip.y + 2.5
                    rect(CGRect(x: sk.hip.x - 9, y: top, width: 16, height: 3.5), equipment)
                    rect(CGRect(x: sk.hip.x - 2.5, y: top + 3.5, width: 3, height: max(0, Skeleton.floorY + 2 - top - 3.5)), equipment)
                case .cableFromAbove:
                    line([CGPoint(x: sk.handA.x + 2, y: 2), sk.handA], equipment, width: 1)
                case .cableFromFront:
                    line([CGPoint(x: 97, y: sk.handA.y - 2), sk.handA], equipment, width: 1)
                    rect(CGRect(x: 96, y: 4, width: 3, height: Skeleton.floorY - 2), equipment)
                case .bar(let p):
                    line([CGPoint(x: p.x - 14, y: p.y), CGPoint(x: p.x + 14, y: p.y)], equipment, width: 2)
                case .platformAtFeet:
                    let c = CGPoint(x: (sk.ankleA.x + sk.toeA.x) / 2, y: (sk.ankleA.y + sk.toeA.y) / 2)
                    line([CGPoint(x: c.x + 3.5, y: c.y - 9), CGPoint(x: c.x + 3.5 + 6, y: c.y + 9)], equipment, width: 2.5)
                default:
                    break
                }
            }

            // Far limbs (lighter), then torso, then near limbs.
            line([sk.hip, sk.kneeB, sk.ankleB, sk.toeB], faint)
            line([sk.shoulder, sk.elbowB, sk.handB], faint)
            line([sk.hip, sk.shoulder], ink, width: 4)
            circle(sk.head, r: Skeleton.headRadius, ink)
            line([sk.hip, sk.kneeA, sk.ankleA, sk.toeA], ink)
            line([sk.shoulder, sk.elbowA, sk.handA], ink)

            // Equipment in front of the body
            for prop in props {
                switch prop {
                case .barbellAtHands:
                    circle(sk.handA, r: 8, accent, filled: false)
                    circle(sk.handA, r: 1.6, accent)
                case .barbellAtHip:
                    let c = CGPoint(x: sk.hip.x + 1, y: sk.hip.y - 5)
                    circle(c, r: 8, accent, filled: false)
                    circle(c, r: 1.6, accent)
                case .dumbbells:
                    rect(CGRect(x: sk.handA.x - 4, y: sk.handA.y - 2, width: 8, height: 4), accent)
                case .kettlebellAtChest:
                    circle(CGPoint(x: sk.handA.x + 2, y: sk.handA.y + 2), r: 3.6, accent)
                case .padAtShin:
                    let c = CGPoint(x: sk.kneeA.x + (sk.ankleA.x - sk.kneeA.x) * 0.8, y: sk.kneeA.y + (sk.ankleA.y - sk.kneeA.y) * 0.8)
                    circle(c, r: 2.6, accent)
                default:
                    break
                }
            }
        }
    }
}

#Preview {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
            ForEach(ExerciseCatalog.all) { ex in
                VStack {
                    ExercisePicture(exercise: ex)
                        .frame(height: 100)
                    Text(ex.name).font(.caption2)
                }
            }
        }
        .padding()
    }
}
