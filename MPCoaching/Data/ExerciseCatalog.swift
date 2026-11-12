import Foundation

/// The built-in exercise library.
enum ExerciseCatalog {
    static func exercise(_ id: String) -> Exercise? { byID[id] }

    /// Name for any id, including ids from a future version the app does not know yet.
    static func name(_ id: String) -> String { byID[id]?.name ?? id }

    static let byID: [String: Exercise] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static let all: [Exercise] = [
        // MARK: Legs
        Exercise(
            id: "barbell-back-squat", name: "Barbell back squat", category: .legs,
            primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: ["Adductors", "Lower back", "Core"],
            equipment: [.barbell],
            steps: [
                "Set the bar in the rack at mid-chest height. Step under it and rest it on your upper back, not your neck.",
                "Grip the bar just outside your shoulders, brace your core, and walk it out two or three steps.",
                "Feet about shoulder-width, toes slightly out. Take a big breath and hold it.",
                "Sit down and slightly back, knees tracking over your toes, until your hip crease is at or below your knee.",
                "Drive up through the whole foot, keeping your chest up, and breathe out at the top.",
            ],
            mistakes: ["Knees caving inward", "Heels lifting off the floor", "Cutting depth short as the weight goes up", "Losing the brace at the bottom"],
            pattern: .squat, incrementLbs: 5),
        Exercise(
            id: "goblet-squat", name: "Goblet squat", category: .legs,
            primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: ["Core", "Upper back"],
            equipment: [.dumbbell, .kettlebell],
            steps: [
                "Hold one dumbbell or kettlebell vertically against your chest, elbows pointing down.",
                "Stand with feet a little wider than shoulder-width, toes slightly out.",
                "Squat down between your legs, keeping the weight tight to your chest and your torso upright.",
                "Let your elbows brush the inside of your knees at the bottom, then stand back up.",
            ],
            mistakes: ["Letting the weight drift away from the chest", "Rounding the upper back", "Rising onto the toes"],
            pattern: .gobletSquat, incrementLbs: 5),
        Exercise(
            id: "romanian-deadlift", name: "Romanian deadlift", category: .legs,
            primaryMuscles: ["Hamstrings", "Glutes"], secondaryMuscles: ["Lower back", "Grip"],
            equipment: [.barbell, .dumbbell],
            steps: [
                "Stand tall holding the bar at your thighs, hands just outside your legs.",
                "Unlock your knees slightly and keep them at that angle the whole set.",
                "Push your hips back and slide the bar down your thighs, keeping your back flat.",
                "Stop when you feel a strong hamstring stretch (usually just below the knee).",
                "Drive your hips forward to stand back up and squeeze your glutes at the top.",
            ],
            mistakes: ["Turning it into a squat by bending the knees more", "Rounding the lower back to reach lower", "Letting the bar drift away from the legs"],
            pattern: .romanianDeadlift, incrementLbs: 5),
        Exercise(
            id: "deadlift", name: "Deadlift", category: .legs,
            primaryMuscles: ["Glutes", "Hamstrings", "Lower back"], secondaryMuscles: ["Quads", "Upper back", "Grip"],
            equipment: [.barbell],
            steps: [
                "Stand with the bar over the middle of your feet, feet about hip-width.",
                "Hinge down and grip the bar just outside your legs. Shins come forward to touch the bar.",
                "Pull your chest up and your shoulders down to flatten your back. Take a big breath and brace.",
                "Push the floor away, keeping the bar against your legs, until you stand fully upright.",
                "Lower it with control the same way: hips back first, then bend the knees once the bar passes them.",
            ],
            mistakes: ["Rounding the back off the floor", "Hips shooting up before the bar moves", "Jerking the bar instead of taking the slack out", "Leaning back at lockout"],
            pattern: .deadlift, incrementLbs: 10),
        Exercise(
            id: "lunge", name: "Lunges", category: .legs,
            primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: ["Adductors", "Hamstrings", "Calves"],
            equipment: [.dumbbell, .bodyweight],
            steps: [
                "Stand tall with a dumbbell in each hand (or no weight to start).",
                "Take a long step forward and lower your back knee toward the floor.",
                "Keep your front knee over the middle of your foot and your torso upright.",
                "Push through the front heel to return to standing. Do all reps on one leg, then switch.",
            ],
            mistakes: ["Steps that are too short, putting all the load on the knee", "Front knee caving in", "Slamming the back knee into the floor"],
            pattern: .lunge, incrementLbs: 5),
        Exercise(
            id: "leg-press", name: "Leg press", category: .legs,
            primaryMuscles: ["Quads", "Glutes"], secondaryMuscles: ["Adductors"],
            equipment: [.machine],
            steps: [
                "Sit with your back flat against the pad and feet shoulder-width on the platform.",
                "Release the safeties and lower the platform until your knees are around 90 degrees or deeper.",
                "Press back up without locking your knees out hard at the top.",
            ],
            mistakes: ["Lower back peeling off the pad at the bottom", "Locking the knees out violently", "Very short reps with a lot of weight"],
            pattern: .legPress, incrementLbs: 10),
        Exercise(
            id: "hip-thrust", name: "Barbell hip thrust", category: .legs,
            primaryMuscles: ["Glutes"], secondaryMuscles: ["Hamstrings"],
            equipment: [.barbell, .bench],
            steps: [
                "Sit on the floor with your upper back against a bench and a padded bar over your hips.",
                "Plant your feet flat, about hip-width, so your shins are vertical at the top.",
                "Drive through your heels and lift your hips until your body is flat from shoulders to knees.",
                "Pause and squeeze your glutes, then lower with control.",
            ],
            mistakes: ["Arching the lower back instead of extending the hips", "Feet too far away (hamstrings take over)", "Rushing the top position"],
            pattern: .hipThrust, incrementLbs: 10),
        Exercise(
            id: "leg-curl", name: "Seated leg curl", category: .legs,
            primaryMuscles: ["Hamstrings"], secondaryMuscles: ["Calves"],
            equipment: [.machine],
            steps: [
                "Adjust the machine so your knees line up with its pivot and the pad sits above your heels.",
                "Lock the thigh pad down snugly.",
                "Curl your heels down and back as far as you can, pause, then return slowly.",
            ],
            mistakes: ["Swinging the weight", "Short range of motion", "Hips lifting off the seat"],
            pattern: .legCurl, incrementLbs: 5),
        Exercise(
            id: "leg-extension", name: "Leg extension", category: .legs,
            primaryMuscles: ["Quads"], secondaryMuscles: [],
            equipment: [.machine],
            steps: [
                "Sit with your knees lined up with the machine's pivot and the pad on your lower shins.",
                "Hold the handles and straighten your legs fully.",
                "Squeeze your quads at the top, then lower slowly.",
            ],
            mistakes: ["Kicking the weight up with momentum", "Dropping the weight on the way down"],
            pattern: .legExtension, incrementLbs: 5),
        Exercise(
            id: "calf-raise", name: "Standing calf raise", category: .legs,
            primaryMuscles: ["Calves"], secondaryMuscles: [],
            equipment: [.machine, .dumbbell, .bodyweight],
            steps: [
                "Stand with the balls of your feet on a step or plate, heels hanging off.",
                "Lower your heels as far as they go and pause for a second in the stretch.",
                "Rise up as high as you can onto your toes, pause, and repeat.",
            ],
            mistakes: ["Bouncing out of the bottom", "Bending the knees to help", "Half reps"],
            pattern: .calfRaise, incrementLbs: 10),

        // MARK: Push
        Exercise(
            id: "barbell-bench-press", name: "Barbell bench press", category: .push,
            primaryMuscles: ["Chest", "Triceps"], secondaryMuscles: ["Front delts"],
            equipment: [.barbell, .bench],
            steps: [
                "Lie on the bench with your eyes under the bar, feet flat on the floor.",
                "Grip the bar a little wider than shoulder-width. Pull your shoulder blades back and down.",
                "Unrack and hold the bar over your shoulders with straight arms.",
                "Lower it to your lower chest with elbows about 45 to 70 degrees from your sides.",
                "Press back up to straight arms. Keep your butt on the bench.",
            ],
            mistakes: ["Bouncing the bar off the chest", "Elbows flared straight out to the sides", "Feet floating or butt lifting", "Wrists bent far back"],
            pattern: .benchPress, incrementLbs: 5),
        Exercise(
            id: "dumbbell-bench-press", name: "Dumbbell bench press", category: .push,
            primaryMuscles: ["Chest", "Triceps"], secondaryMuscles: ["Front delts"],
            equipment: [.dumbbell, .bench],
            steps: [
                "Sit on the bench with the dumbbells on your thighs, then lie back and bring them to your chest.",
                "Press them up over your chest with palms facing your feet.",
                "Lower them until they are level with your chest, elbows at about 45 to 60 degrees.",
                "Press back up, bringing the dumbbells slightly together at the top.",
            ],
            mistakes: ["Lowering only halfway", "Letting the dumbbells drift toward the face", "Clanging the dumbbells together"],
            pattern: .dumbbellBench, incrementLbs: 5),
        Exercise(
            id: "close-grip-dumbbell-bench-press", name: "Close-grip dumbbell bench press", category: .push,
            primaryMuscles: ["Triceps", "Chest"], secondaryMuscles: ["Front delts"],
            equipment: [.dumbbell, .bench],
            steps: [
                "Lie on the bench holding two dumbbells over your chest with palms facing each other.",
                "Keep the dumbbells close together, almost touching.",
                "Lower them to your lower chest with your elbows tucked close to your sides.",
                "Press back up to straight arms.",
            ],
            mistakes: ["Elbows flaring out", "Bouncing off the chest", "Shoulders rolling forward at the top"],
            pattern: .dumbbellBench, incrementLbs: 5),
        Exercise(
            id: "incline-dumbbell-press", name: "Incline dumbbell press", category: .push,
            primaryMuscles: ["Upper chest", "Front delts"], secondaryMuscles: ["Triceps"],
            equipment: [.dumbbell, .bench],
            steps: [
                "Set a bench to about 30 degrees and lie back with a dumbbell in each hand at your shoulders.",
                "Press the dumbbells up over your upper chest.",
                "Lower them under control until they are level with your chest, then press again.",
            ],
            mistakes: ["Bench set too steep (turns into a shoulder press)", "Arching to make it flat"],
            pattern: .dumbbellBench, incrementLbs: 5),
        Exercise(
            id: "push-up", name: "Push-up", category: .push,
            primaryMuscles: ["Chest", "Triceps"], secondaryMuscles: ["Front delts", "Core"],
            equipment: [.bodyweight],
            steps: [
                "Hands a little wider than your shoulders, body in a straight line from head to heels.",
                "Squeeze your glutes and brace your core.",
                "Lower your chest to just above the floor, elbows about 45 degrees from your body.",
                "Push back up to straight arms.",
            ],
            mistakes: ["Hips sagging", "Head poking forward", "Partial reps"],
            pattern: .pushUp, incrementLbs: 5),
        Exercise(
            id: "dip", name: "Dip", category: .push,
            primaryMuscles: ["Chest", "Triceps"], secondaryMuscles: ["Front delts"],
            equipment: [.bodyweight],
            steps: [
                "Support yourself on parallel bars with straight arms.",
                "Lean slightly forward and lower until your shoulders are just below your elbows.",
                "Press back up to straight arms.",
            ],
            mistakes: ["Dropping too deep with sore shoulders", "Shrugging the shoulders up to the ears", "Swinging the legs"],
            pattern: .dip, incrementLbs: 5),

        // MARK: Shoulders
        Exercise(
            id: "overhead-dumbbell-press", name: "Overhead dumbbell press", category: .shoulders,
            primaryMuscles: ["Front delts", "Side delts"], secondaryMuscles: ["Triceps", "Upper chest", "Core"],
            equipment: [.dumbbell],
            steps: [
                "Stand with feet hip-width, dumbbells at shoulder height, palms forward or facing in.",
                "Brace your core and squeeze your glutes so your lower back does not arch.",
                "Press the dumbbells straight up until your arms are locked out overhead.",
                "Lower them back to your shoulders with control.",
            ],
            mistakes: ["Leaning back to press", "Pressing the dumbbells forward instead of up", "Stopping short of lockout"],
            pattern: .overheadPress, incrementLbs: 5),
        Exercise(
            id: "seated-shoulder-press", name: "Seated shoulder press", category: .shoulders,
            primaryMuscles: ["Front delts", "Side delts"], secondaryMuscles: ["Triceps"],
            equipment: [.dumbbell, .bench],
            steps: [
                "Sit on a bench set upright, back against the pad, dumbbells at shoulder height.",
                "Press the dumbbells overhead until your arms are straight.",
                "Lower them back down to about ear level and press again.",
            ],
            mistakes: ["Arching off the pad", "Bouncing out of the bottom"],
            pattern: .seatedPress, incrementLbs: 5),
        Exercise(
            id: "upright-row", name: "Upright row", category: .shoulders,
            primaryMuscles: ["Side delts", "Traps"], secondaryMuscles: ["Biceps"],
            equipment: [.dumbbell, .barbell],
            steps: [
                "Stand holding the weight in front of your thighs with a grip a little wider than shoulder-width.",
                "Lead with your elbows and pull the weight up along your body.",
                "Stop when your elbows reach shoulder height. Do not go higher.",
                "Lower slowly.",
            ],
            mistakes: ["Narrow grip that pinches the shoulders", "Pulling the elbows above shoulder height", "Swinging"],
            pattern: .uprightRow, incrementLbs: 5),
        Exercise(
            id: "lateral-raise", name: "Dumbbell lateral raise", category: .shoulders,
            primaryMuscles: ["Side delts"], secondaryMuscles: ["Traps"],
            equipment: [.dumbbell],
            steps: [
                "Stand holding light dumbbells at your sides with a slight bend in the elbows.",
                "Raise your arms out to the sides until they are about shoulder height.",
                "Lower slowly and repeat without resting at the bottom.",
            ],
            mistakes: ["Going too heavy and swinging", "Shrugging the weight up with the traps"],
            pattern: .lateralRaise, incrementLbs: 2.5),
        Exercise(
            id: "face-pull", name: "Face pull", category: .shoulders,
            primaryMuscles: ["Rear delts", "Upper back"], secondaryMuscles: ["Rotator cuff"],
            equipment: [.cable],
            steps: [
                "Set a rope on a cable at upper-chest to face height.",
                "Hold the rope with thumbs toward you and step back so the arms are straight.",
                "Pull the rope toward your face, splitting the ends and driving your elbows out and back.",
                "Pause, then return slowly.",
            ],
            mistakes: ["Leaning back to move more weight", "Pulling to the chest instead of the face"],
            pattern: .facePull, incrementLbs: 5),

        // MARK: Pull
        Exercise(
            id: "lat-pulldown", name: "Lat pulldown", category: .pull,
            primaryMuscles: ["Lats"], secondaryMuscles: ["Biceps", "Rear delts", "Mid back"],
            equipment: [.cable, .machine],
            steps: [
                "Sit with your thighs snug under the pads and grip the bar a little wider than your shoulders.",
                "Lean back slightly and pull your shoulders down away from your ears.",
                "Pull the bar to your upper chest, driving your elbows down toward your back pockets.",
                "Let the bar rise slowly until your arms are straight and you feel a stretch in your lats.",
            ],
            mistakes: ["Leaning way back and turning it into a row", "Pulling the bar behind the neck", "Not letting the arms straighten at the top"],
            pattern: .latPulldown, incrementLbs: 5),
        Exercise(
            id: "pull-up", name: "Pull-up", category: .pull,
            primaryMuscles: ["Lats"], secondaryMuscles: ["Biceps", "Mid back", "Core"],
            equipment: [.pullUpBar],
            steps: [
                "Hang from the bar with hands a little wider than shoulder-width, palms facing away.",
                "Pull your shoulders down, then pull your chest toward the bar.",
                "Get your chin over the bar, then lower all the way to straight arms.",
            ],
            mistakes: ["Kipping or swinging", "Half reps that never reach straight arms", "Chin poking forward to reach the bar"],
            pattern: .pullUp, incrementLbs: 5),
        Exercise(
            id: "barbell-row", name: "Barbell row", category: .pull,
            primaryMuscles: ["Mid back", "Lats"], secondaryMuscles: ["Rear delts", "Biceps", "Lower back"],
            equipment: [.barbell],
            steps: [
                "Hold the bar with an overhand grip just outside your legs.",
                "Hinge forward until your torso is around 45 degrees, knees soft, back flat.",
                "Pull the bar to your lower ribs, driving your elbows back.",
                "Lower it until your arms are straight, keeping your torso still.",
            ],
            mistakes: ["Standing up more with every rep", "Using the hips to heave the bar", "Rounding the back"],
            pattern: .bentOverRow, incrementLbs: 5),
        Exercise(
            id: "one-arm-dumbbell-row", name: "One-arm dumbbell row", category: .pull,
            primaryMuscles: ["Lats", "Mid back"], secondaryMuscles: ["Rear delts", "Biceps"],
            equipment: [.dumbbell, .bench],
            steps: [
                "Place one hand and knee on a bench, other foot on the floor, back flat.",
                "Hold the dumbbell straight down under your shoulder.",
                "Row it toward your hip, keeping your elbow close to your body.",
                "Lower it until your arm is straight and feel the stretch. Finish all reps, then switch sides.",
            ],
            mistakes: ["Twisting the torso to lift the weight", "Pulling to the chest instead of the hip"],
            pattern: .bentOverRow, incrementLbs: 5),
        Exercise(
            id: "seated-cable-row", name: "Seated cable row", category: .pull,
            primaryMuscles: ["Mid back", "Lats"], secondaryMuscles: ["Biceps", "Rear delts"],
            equipment: [.cable],
            steps: [
                "Sit with your feet on the platform, knees slightly bent, holding the handle with straight arms.",
                "Sit tall. Pull the handle to your stomach, squeezing your shoulder blades together.",
                "Let the handle go forward until your arms are straight and your shoulders reach forward slightly.",
            ],
            mistakes: ["Rocking the torso back and forth", "Shrugging the shoulders up"],
            pattern: .cableRow, incrementLbs: 5),

        // MARK: Arms
        Exercise(
            id: "barbell-curl", name: "Barbell curl", category: .arms,
            primaryMuscles: ["Biceps"], secondaryMuscles: ["Forearms"],
            equipment: [.barbell],
            steps: [
                "Stand holding the bar with an underhand grip at shoulder-width.",
                "Keep your elbows at your sides and curl the bar up to your shoulders.",
                "Lower slowly until your arms are fully straight.",
            ],
            mistakes: ["Swinging the hips to lift the bar", "Elbows drifting forward", "Not straightening the arms"],
            pattern: .curl, incrementLbs: 5),
        Exercise(
            id: "hammer-curl", name: "Dumbbell hammer curl", category: .arms,
            primaryMuscles: ["Biceps", "Brachialis"], secondaryMuscles: ["Forearms"],
            equipment: [.dumbbell],
            steps: [
                "Stand with dumbbells at your sides, palms facing in.",
                "Curl the dumbbells up while keeping your palms facing each other.",
                "Lower slowly to straight arms.",
            ],
            mistakes: ["Swinging", "Shoulders rolling forward at the top"],
            pattern: .curl, incrementLbs: 5),
        Exercise(
            id: "triceps-pushdown", name: "Triceps pushdown", category: .arms,
            primaryMuscles: ["Triceps"], secondaryMuscles: [],
            equipment: [.cable],
            steps: [
                "Stand at a high cable with a rope or bar, elbows pinned to your sides.",
                "Push the handle down until your arms are fully straight.",
                "Let it come back up until your forearms pass parallel to the floor.",
            ],
            mistakes: ["Elbows drifting forward", "Leaning over the handle to push with bodyweight"],
            pattern: .tricepsPushdown, incrementLbs: 5),
        Exercise(
            id: "overhead-triceps-extension", name: "Overhead triceps extension", category: .arms,
            primaryMuscles: ["Triceps"], secondaryMuscles: [],
            equipment: [.dumbbell, .cable],
            steps: [
                "Hold one dumbbell overhead with both hands, arms straight.",
                "Keep your elbows pointing up and lower the weight behind your head.",
                "Straighten your arms to lift it back up.",
            ],
            mistakes: ["Elbows flaring wide", "Arching the lower back"],
            pattern: .overheadExtension, incrementLbs: 5),

        // MARK: Core and carries
        Exercise(
            id: "farmers-carry", name: "Farmer's carry", category: .core,
            primaryMuscles: ["Grip", "Traps", "Core"], secondaryMuscles: ["Glutes", "Calves"],
            equipment: [.dumbbell, .kettlebell],
            steps: [
                "Pick up a heavy dumbbell or kettlebell in each hand.",
                "Stand tall with your shoulders back and down.",
                "Walk with short, quick steps for the set distance or time.",
                "Log the weight in one hand, and use reps for seconds or steps.",
            ],
            mistakes: ["Leaning to one side", "Shrugging the weights up", "Long, sloppy strides"],
            pattern: .carry, incrementLbs: 5),
        Exercise(
            id: "plank", name: "Plank", category: .core,
            primaryMuscles: ["Abs", "Core"], secondaryMuscles: ["Shoulders", "Glutes"],
            equipment: [.bodyweight],
            steps: [
                "Rest on your forearms and toes, elbows under your shoulders.",
                "Make a straight line from head to heels. Squeeze your glutes and brace.",
                "Hold for time. Log seconds as reps.",
            ],
            mistakes: ["Hips sagging", "Hips piked up high", "Holding the breath"],
            pattern: .plank, incrementLbs: 5),
        Exercise(
            id: "hanging-knee-raise", name: "Hanging knee raise", category: .core,
            primaryMuscles: ["Abs", "Hip flexors"], secondaryMuscles: ["Grip"],
            equipment: [.pullUpBar],
            steps: [
                "Hang from a bar with straight arms.",
                "Curl your knees up toward your chest, rolling your pelvis up at the top.",
                "Lower slowly without swinging.",
            ],
            mistakes: ["Swinging for momentum", "Only lifting the thighs without curling the pelvis"],
            pattern: .hangingKneeRaise, incrementLbs: 5),
        Exercise(
            id: "dead-bug", name: "Dead bug", category: .core,
            primaryMuscles: ["Abs", "Core"], secondaryMuscles: ["Hip flexors"],
            equipment: [.bodyweight],
            steps: [
                "Lie on your back, arms pointing at the ceiling, knees bent at 90 degrees over your hips.",
                "Press your lower back into the floor.",
                "Slowly reach one arm overhead and straighten the opposite leg, keeping your back flat.",
                "Return and switch sides. Each side counts as one rep.",
            ],
            mistakes: ["Lower back arching off the floor", "Moving too fast"],
            pattern: .deadBug, incrementLbs: 5),
        Exercise(
            id: "pallof-press", name: "Pallof press", category: .core,
            primaryMuscles: ["Obliques", "Core"], secondaryMuscles: ["Shoulders"],
            equipment: [.cable],
            steps: [
                "Stand side-on to a cable set at chest height, holding the handle at your chest.",
                "Brace and press the handle straight out in front of you.",
                "Hold for a breath without letting the cable twist you, then bring it back.",
                "Do all reps, then face the other way.",
            ],
            mistakes: ["Letting the torso rotate", "Standing too close to the stack"],
            pattern: .pallofPress, incrementLbs: 5),
    ]
}
