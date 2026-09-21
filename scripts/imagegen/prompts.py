"""Prompt construction for PhaseTraining exercise library images.

One template. Everything that varies comes from the exercise record so the
same code path runs for 10 exercises or 1,150.
"""

ACCENT_HEX = "#D85A30"

SHARED_CONSTRAINTS = """
Hard constraints, apply to every image:
- Exactly one human figure. Never two figures, never a mirrored duplicate,
  never a second view or a ghosted copy of the same figure.
- {framing}
- Androgynous adult build, neutral proportions, approximately 7.5 head heights tall.
- Simple facial features only. No hair styling detail. Plain athletic
  shorts, no logos.
- {background} No room, no gym, no floor, no cast shadow.
- Equipment drawn accurately and in contact with the body where it should be.
  Nothing floating.
- No text, no numbers, no arrows, no watermarks, no logos, no labels.
- Square 1:1 composition.
- Anatomically correct hands with five fingers, and a grip that physically
  matches the implement being held.
""".strip()

# Only a native image API with a `background: transparent` parameter can
# return alpha. Asked for "transparent" in prose, gpt-image and gemini-3-pro
# both painted a Photoshop checkerboard into the pixels (smoke run
# 2026-09-11), so every other route asks for flat white and keys it out later.
BACKGROUND_TRANSPARENT = "Plain transparent background."
BACKGROUND_WHITE = ("Plain solid pure white background, #FFFFFF everywhere "
                    "outside the figure. Never draw a checkerboard or "
                    "transparency pattern.")


FRAMING_FULL = "Full body in frame, feet and head included, even margin on all four sides."
FRAMING_LOWER_LEG = ("Lower legs only in frame, from the knees down to the floor; nothing above "
                     "the knee is drawn, even margin on all four sides.")
FRAMING_FOREARM = ("One forearm and hand only in frame, from the elbow to the fingertips; "
                   "nothing else of the body is drawn, even margin on all four sides.")


def shared_constraints(transparent, framing=FRAMING_FULL):
    return SHARED_CONSTRAINTS.format(
        framing=framing,
        background=BACKGROUND_TRANSPARENT if transparent else BACKGROUND_WHITE)


STYLE_BIBLE = {
    "line_art": f"""
Flat vector line art. Uniform-weight black outlines,
rounded line caps, no cross-hatching, no shading, no gradients, no fill inside
the body. The primary working muscle group is the single exception: draw it as
a solid flat shape in {ACCENT_HEX}. Everything else is line only. The result
should look like a clean icon set, not an illustration.
""".strip(),
    "mannequin": """
Neutral 3D mannequin render. Matte light grey articulated figure with visible
joint spheres at shoulder, elbow, hip, knee and ankle. Soft even studio
lighting from upper front left, gentle form shadow to convey volume, no cast
shadow on the ground. No skin texture, no face beyond a smooth blank head. Mid
grey equipment with a darker value than the figure so it separates cleanly.
""".strip(),
}

# Camera plane by movement pattern. Keys are the 38 `movement_patterns.slug`
# values in db/coach.db (2026-09-11), 40 with the two that hold no exercise yet. An exercise with several patterns uses
# its first; the 106 with none fall to DEFAULT_CAMERA.
_SIDE_HIP = "direct side view, sagittal plane, camera at hip height"
_SIDE_CHEST = "direct side view, sagittal plane, camera at chest height"
_SIDE_FLOOR = "direct side view, sagittal plane, camera at floor height"
_FRONT_CHEST = "direct front view, frontal plane, camera at chest height"
_TQ_CHEST = "three-quarter front view, camera at chest height"
_TQ_HIP = "three-quarter front view, camera at hip height"
# Ankle work: at full-body scale a heel-up and a heel-down frame are the same
# picture (run 4 lost three calf raises to that). Frame the lower leg only.
_SIDE_LOWER_LEG = ("direct side view, sagittal plane, camera at knee height, framed from the "
                   "knees down to the floor so the calves, ankles and feet fill the frame; "
                   "nothing above the knee is drawn")
# Prone scapular work: from the side a T and a W are the same silhouette.
_TOP_DOWN = "view from directly above, camera looking straight down at the floor"
# Hand rehab: the whole figure is the wrong scale for a hook fist.
_FRONT_FOREARM = ("close view of one forearm and hand, palm toward the viewer, framed from "
                  "the elbow to the fingertips; nothing else of the body is drawn")

CAMERA_BY_PATTERN = {
    # lower body, sagittal
    "hip-hinge": _SIDE_HIP,
    "squat": _SIDE_HIP,
    "single-leg-squat": _SIDE_HIP,
    "step-up": _SIDE_HIP,
    "hip-flexion": _SIDE_HIP,
    "calf-raise": _SIDE_LOWER_LEG,
    "jumping-landing": _SIDE_HIP,
    "olympic-derivative": _SIDE_HIP,
    "ground-to-standing": _SIDE_HIP,
    "deceleration": _SIDE_HIP,
    "locomotion": _SIDE_HIP,
    "pedal-stroke": _SIDE_HIP,
    "skating-stride": _SIDE_HIP,
    "terminal-knee-extension": _SIDE_HIP,
    # upper body, sagittal
    "horizontal-push": _SIDE_CHEST,
    "horizontal-pull": _SIDE_CHEST,
    "vertical-push": _SIDE_CHEST,
    "vertical-pull": _SIDE_CHEST,
    "climbing-pull": _SIDE_CHEST,
    "elbow-extension": _SIDE_CHEST,
    "elbow-flexion": _SIDE_CHEST,
    "scapular-retraction": _SIDE_CHEST,
    "scapular-protraction": _SIDE_CHEST,
    # floor work
    "anti-extension": _SIDE_FLOOR,
    "crawling": _SIDE_FLOOR,
    "swim-stroke": _SIDE_FLOOR,
    "breathing-bracing": _SIDE_FLOOR,
    # frontal plane
    "anti-rotation": _FRONT_CHEST,
    "anti-lateral-flexion": _FRONT_CHEST,
    "loaded-carry": _FRONT_CHEST,
    "hip-abduction": _FRONT_CHEST,
    "hip-adduction": _FRONT_CHEST,
    "cutting": _FRONT_CHEST,
    # rotation and sport strikes
    "trunk-rotation": _TQ_CHEST,
    "rotational-strike": _TQ_CHEST,
    "striking": _TQ_CHEST,
    "racquet-swing": _TQ_CHEST,
    "throwing-casting": _TQ_CHEST,
    "paddle-stroke": _TQ_CHEST,
    "takedown-sprawl": _TQ_CHEST,
}
DEFAULT_CAMERA = _TQ_CHEST


# Per-exercise overrides for the few where the pattern's camera is wrong for
# the body's orientation: a supine squeeze drawn "front view at chest height"
# is a figure seen from the feet.
CAMERA_BY_SLUG = {
    "adductor-ball-squeeze": _SIDE_FLOOR,
    # run 5 drew the wall sit from the front as a standing half-squat with no
    # wall; the seat and the wall only read from an angle at hip height
    "rider-wall-sit-squeeze": _TQ_HIP,
    # run 9 (2026-09-21): demoted pairs re-rolled on the camera that shows the
    # movement. A twist or a cross-body reach is invisible from the side.
    "bicycle-crunch": _TOP_DOWN,
    "cross-body-crunch": _TOP_DOWN,
    "russian-twist": _TOP_DOWN,
    "cable-twist": _FRONT_CHEST,
    "dynamic-lock-off": _FRONT_CHEST,
    "external-rotation": _FRONT_CHEST,
    "kitesurf-edge-drop": _FRONT_CHEST,
    "barbell-glute-bridge": _SIDE_FLOOR,
    "oblique-crunch": _SIDE_FLOOR,
    "tibialis-raise": _SIDE_LOWER_LEG,
    # tranche 4 (2026-09-20): floor work whose first pattern is not a floor one
    "judo-bridge-hip-escape": _SIDE_FLOOR,
    "plyo-push-up": _SIDE_FLOOR,
    "plyo-pushup-wrist-prep": _SIDE_FLOOR,
    "scapular-push-up": _SIDE_FLOOR,
    # prone scapular letters read only from above
    "prone-snow-angel": _TOP_DOWN,
    "prone-t-raise": _TOP_DOWN,
    "prone-w-raise": _TOP_DOWN,
    "prone-ytwl-complex": _TOP_DOWN,
    "tendon-nerve-glide-sequence": _FRONT_FOREARM,
    # frontal-plane movements filed under a sagittal pattern
    "deep-water-fall-entry": _FRONT_CHEST,
    "double-under": _FRONT_CHEST,
    "double-unders-ski": _FRONT_CHEST,
    "jump-rope": _FRONT_CHEST,
    "jumping-jack": _FRONT_CHEST,
    "parkour-dyno": _FRONT_CHEST,
    "rope-skip-speed": _FRONT_CHEST,
    "scapular-wall-slide": _FRONT_CHEST,
    "skate-edge-lateral-pushes": _FRONT_CHEST,
    # stances and blocks read from three-quarter, a pack hike from the side
    "karate-kata-flow": _TQ_CHEST,
    "krav-maga-360-defense": _TQ_CHEST,
    "stance-transition-drill": _TQ_CHEST,
    "casting-practice-drill": _SIDE_CHEST,
    "weighted-pack-hike": _SIDE_HIP,
    # Olympic lifts with no movement pattern row
    "hang-clean": _SIDE_HIP,
    "push-jerk": _SIDE_HIP,
    "push-press": _SIDE_HIP,
    # The model draws an overhead-squat catch and a high pull from the front
    # whatever the start frame's camera (run 8, twice each); give it the
    # front for both frames.
    "deadlift-high-pull-barbell": _FRONT_CHEST,
    "power-snatch": _FRONT_CHEST,
    "snatch": _FRONT_CHEST,
    "sumo-deadlift-high-pull-barbell": _FRONT_CHEST,
}

FRAMING_BY_CAMERA = {_SIDE_LOWER_LEG: FRAMING_LOWER_LEG, _FRONT_FOREARM: FRAMING_FOREARM}


def camera_for(exercise):
    if exercise.get("id") in CAMERA_BY_SLUG:
        return CAMERA_BY_SLUG[exercise["id"]]
    return CAMERA_BY_PATTERN.get(exercise.get("movement_pattern"), DEFAULT_CAMERA)


def framing_for(exercise):
    return FRAMING_BY_CAMERA.get(camera_for(exercise), FRAMING_FULL)


def build_start_prompt(exercise, style, transparent=False):
    """The pose comes first: run 1 buried it under the style bible and both
    Gemini models drew the exercise's iconic mid-rep pose as the start."""
    return f"""Subject: the START position of the exercise "{exercise['name']}".
This is the setup moment before any movement has happened. Nothing has been
lifted, pulled, pressed, raised or hinged yet. If the exercise is a hold
(plank, bridge, carry), draw the body at rest before the hold begins, not the
hold itself.

Body position to draw, follow this precisely and do not improvise the joint
angles:
{exercise['start_position']}

Camera: {camera_for(exercise)}. Use this exact camera for this image.
Equipment: {exercise['equipment']}.
Primary working muscles: {exercise['primary_muscles']}.

{STYLE_BIBLE[style]}

{shared_constraints(transparent, framing_for(exercise))}
"""


def build_hold_prompt(exercise, style, transparent=False):
    """Single frame for an isometric exercise: the hold itself, drawn from
    the end position text (the start text describes the setup before it)."""
    return f"""Subject: the exercise "{exercise['name']}", held in its working position.
This is an isometric hold, so draw the position that is held, not the setup
before it.

Body position to draw, follow this precisely and do not improvise the joint
angles:
{exercise.get('end_position') or exercise['start_position']}

Camera: {camera_for(exercise)}. Use this exact camera for this image.
Equipment: {exercise['equipment']}.
Primary working muscles: {exercise['primary_muscles']}.

{STYLE_BIBLE[style]}

{shared_constraints(transparent, framing_for(exercise))}
"""


def build_end_prompt(exercise, style, transparent=False):
    """Prompt for the second frame. Always sent with the approved start frame
    attached as a reference image so the figure carries over. Run 1 showed
    the reference dominating: several end frames came back as the start
    unchanged, so the movement is stated before the preservation rules."""
    return f"""The attached reference image is the START position of "{exercise['name']}".
Produce the END position of the same repetition. The end position must be
clearly different from the reference: the joints named below have moved.
Never return the reference pose unchanged.

Body position to draw, follow this precisely and do not improvise the joint
angles:
{exercise['end_position']}

This must read as the same figure one moment later. Preserve exactly: figure
identity, limb proportions, body scale within the frame, line weight or render
treatment, colour values, camera position, camera height and framing. Do not
re-centre, do not zoom, do not change the viewing angle.

Camera: {camera_for(exercise)}. Unchanged from the reference.
Equipment: {exercise['equipment']}.
Primary working muscles: {exercise['primary_muscles']}.

{STYLE_BIBLE[style]}

{shared_constraints(transparent, framing_for(exercise))}
"""


# Ten exercises chosen to break things: a loaded hinge, a single-leg pattern,
# an anti-rotation press, a multi-stage floor movement, a hanging position, a
# small-range isolation, an asymmetric half-kneeling press, a side-lying
# position, a supine contralateral pattern, and a loaded vertical pull.
BAKEOFF_EXERCISES = [
    {
        "id": "barbell-romanian-deadlift",
        "name": "Barbell Romanian deadlift",
        "movement_pattern": "hip-hinge",
        "equipment": "barbell held in both hands at arms length",
        "primary_muscles": "hamstrings and glutes",
        "start_position": (
            "Standing tall, feet hip width, knees softly bent about 10 degrees. "
            "Barbell resting against the front of the thighs, arms straight, "
            "overhand grip just outside the hips. Spine neutral, shoulders back."
        ),
        "end_position": (
            "Hips pushed back behind the heels, torso hinged forward to roughly "
            "45 degrees below horizontal, spine still flat and neutral with no "
            "rounding at the lower back. Knee angle unchanged from the start. "
            "Barbell has travelled down the shins and sits just below the knees, "
            "arms still straight and vertical. Weight over the midfoot."
        ),
    },
    {
        "id": "bulgarian-split-squat",
        "name": "Bulgarian split squat",
        "movement_pattern": "single-leg-squat",
        "equipment": "two dumbbells held at the sides, one bench behind the figure",
        "primary_muscles": "quadriceps and glutes",
        "start_position": (
            "Front leg standing, knee nearly straight. Rear foot laced on top of "
            "a bench behind, rear knee slightly bent, rear shin roughly "
            "horizontal. Torso upright. A dumbbell hanging at arms length beside "
            "each hip."
        ),
        "end_position": (
            "Front knee bent to 90 degrees, front thigh parallel to the floor, "
            "front shin close to vertical with the knee tracking over the toes. "
            "Rear knee lowered to just above the floor, rear thigh near vertical. "
            "Torso upright with a slight forward lean. Dumbbells still hanging at "
            "arms length."
        ),
    },
    {
        "id": "pallof-press",
        "name": "Cable Pallof press",
        "movement_pattern": "anti-rotation",
        "equipment": "cable machine with a handle, cable running horizontally to the figure's left side",
        "primary_muscles": "obliques and deep core",
        "start_position": (
            "Standing side-on to a cable machine, feet shoulder width, knees "
            "soft. Both hands clasped on a single handle held tight against the "
            "sternum. Elbows tucked in at the sides. Shoulders and hips square to "
            "the camera, resisting the sideways pull of the cable."
        ),
        "end_position": (
            "Both arms fully extended straight out from the sternum toward the "
            "camera, hands still clasped on the handle at chest height. Shoulders "
            "and hips still perfectly square, no rotation toward the cable, no "
            "side bend. Feet unmoved."
        ),
    },
    {
        "id": "turkish-get-up-to-elbow",
        "name": "Turkish get-up, roll to elbow",
        "movement_pattern": "ground-to-standing",
        "equipment": "one kettlebell pressed overhead in the right hand",
        "primary_muscles": "shoulders and core",
        "start_position": (
            "Lying supine on the floor. Right arm pressed straight up vertically "
            "with a kettlebell, the bell resting on the back of the forearm. "
            "Right knee bent with right foot flat on the floor. Left leg straight "
            "on the floor at about 45 degrees out. Left arm on the floor at about "
            "45 degrees, palm down. Eyes on the bell."
        ),
        "end_position": (
            "Torso rolled up and propped on the left forearm, left elbow directly "
            "under the left shoulder, chest open. Right arm still locked out "
            "vertically overhead with the kettlebell, right shoulder packed. Right "
            "foot still flat, right knee bent. Left leg still straight on the "
            "floor. Eyes still on the bell."
        ),
    },
    {
        "id": "hanging-knee-raise",
        "name": "Hanging knee raise",
        "movement_pattern": "anti-extension",
        "equipment": "horizontal pull-up bar overhead",
        "primary_muscles": "lower abdominals and hip flexors",
        "start_position": (
            "Hanging at full stretch from a horizontal bar, overhand grip "
            "shoulder width, arms straight, shoulders active and slightly "
            "depressed. Legs straight and together, toes pointed, body in a "
            "straight vertical line."
        ),
        "end_position": (
            "Both knees drawn up together to hip height or slightly above, hips "
            "flexed to 90 degrees, knees bent to 90 degrees, shins horizontal. "
            "Pelvis tucked slightly posterior with a flat lower back. Arms still "
            "straight, no swing, torso still vertical."
        ),
    },
    {
        "id": "single-leg-calf-raise",
        "name": "Single-leg calf raise",
        "movement_pattern": "calf-raise",
        "equipment": "one step or low box, figure holding a wall for light balance",
        "primary_muscles": "gastrocnemius and soleus",
        "start_position": (
            "Balanced on the ball of one foot on the edge of a step, heel dropped "
            "below the level of the step into a deep stretch. Other leg bent with "
            "the foot lifted behind. Standing leg straight. One hand lightly "
            "touching a wall for balance."
        ),
        "end_position": (
            "Risen to the top of the ball of the foot, heel lifted as high as it "
            "goes, ankle fully plantarflexed. Standing leg still straight, hips "
            "level, no side lean. Other leg still bent and lifted behind. Same "
            "hand still touching the wall."
        ),
    },
    {
        "id": "half-kneeling-landmine-press",
        "name": "Half-kneeling landmine press",
        "movement_pattern": "vertical-push",
        "equipment": "barbell with one end anchored in a landmine at floor level, other end held in the right hand",
        "primary_muscles": "shoulders and upper chest",
        "start_position": (
            "Half-kneeling, left knee down on the floor, right foot flat in front "
            "with the right knee at 90 degrees. Torso tall and vertical, glutes "
            "engaged. Right hand gripping the end of an angled barbell held at "
            "the front of the right shoulder, right elbow tucked down and forward."
        ),
        "end_position": (
            "Right arm pressed out and up along the angle of the bar, elbow fully "
            "extended, hand finishing above and slightly in front of the head. "
            "Right shoulder blade rotated upward. Torso still vertical with no "
            "lean back and no rib flare. Both knees unmoved."
        ),
    },
    {
        "id": "copenhagen-plank",
        "name": "Copenhagen plank",
        "movement_pattern": "anti-lateral-flexion",
        "isometric": True,
        "equipment": "one bench, top leg resting on the bench",
        "primary_muscles": "adductors and obliques",
        "start_position": (
            "Side-lying on the floor, propped on the bottom forearm with the "
            "elbow directly under the shoulder. Top leg resting on a bench with "
            "the inner side of the knee or ankle on the bench surface. Hips still "
            "resting on the floor. Bottom leg on the floor."
        ),
        "end_position": (
            "Hips lifted so the body forms one straight line from the top of the "
            "head through the shoulder, hip and bottom ankle. Weight supported "
            "only by the bottom forearm and the top leg on the bench. Bottom leg "
            "lifted clear of the floor and held alongside the top leg. No hip sag, "
            "no forward rotation of the chest toward the floor."
        ),
    },
    {
        "id": "dead-bug",
        "name": "Dead bug",
        "movement_pattern": "anti-extension",
        "equipment": "bodyweight only",
        "primary_muscles": "deep core and transverse abdominis",
        "start_position": (
            "Lying supine. Both arms reaching straight up vertically toward the "
            "ceiling. Both hips and knees bent to 90 degrees, shins horizontal, "
            "knees stacked over hips. Lower back flat against the floor."
        ),
        "end_position": (
            "Right arm lowered overhead to just above the floor and left leg "
            "extended straight out to just above the floor. Left arm still "
            "vertical, right knee still stacked at 90 degrees. Lower back still "
            "flat on the floor with no arch, ribcage down."
        ),
    },
    {
        "id": "weighted-pull-up",
        "name": "Weighted pull-up",
        "movement_pattern": "vertical-pull",
        "equipment": "horizontal pull-up bar overhead, one weight plate hanging from a dip belt at the waist",
        "primary_muscles": "latissimus dorsi and biceps",
        "start_position": (
            "Hanging at full stretch from a horizontal bar, overhand grip slightly "
            "wider than shoulder width, arms fully straight, shoulders at full "
            "elevation. A dip belt around the waist with a single weight plate "
            "hanging on a short chain between the legs. Legs straight, ankles "
            "crossed."
        ),
        "end_position": (
            "Pulled up until the chin clears the bar, elbows driven down and back "
            "toward the ribs, chest close to the bar, shoulder blades retracted "
            "and depressed. Weight plate still hanging on the belt between the "
            "legs, ankles still crossed, minimal body swing."
        ),
    },
]
