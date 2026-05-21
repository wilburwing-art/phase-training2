# Manual swap review queue

Generated from `db/quality/swap_decisions.jsonl`. 15 borderline swap candidates that the auto-accept rules wouldn't touch. For each one:

- Look at the current image vs the candidate image.
- Edit `YES` or `NO` after `Replace with this candidate?`.
- After editing, run `scripts/quality/apply_manual_swaps.py` to land approved swaps.

## ex 453

Current (score 1): _Athlete holding resistance band but not performing face pull; no pulling motion or external rotation visible._  ![current](PhaseTraining/Resources/ExerciseImages/453.webp)

Candidate (free-exercise-db, license=MIT, score=4/med): _Cable pull visible with arm extension, but angle/rotation clarity unclear from this frame_  ![candidate](db/quality/candidate_thumbs/db7c380e29d27d4959d93e3b4d09b051e349e16a.webp)

- URL: `https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Face_Pull/0.jpg`
- Attribution: free-exercise-db (yuhonas), MIT

- Replace with this candidate? **NO**

---

## ex 659

Current (score 1): _Wide gym shot with athlete in background, no clear exercise demonstration visible_  ![current](PhaseTraining/Resources/ExerciseImages/659.webp)

Candidate (wger, license=CC-BY-SA 4, score=4/med): _Cable row with unilateral stance visible, slight angle makes full form assessment difficult._  ![candidate](db/quality/candidate_thumbs/bb042913f8d1df45995ae465bf9efa235c4e4038.webp)

- URL: `https://wger.de/media/exercise-images/1636/1bf3ee54-207c-4b53-b057-15adc1dd6128.png`
- Attribution: wger.de, CC-BY-SA 4 (author from API: Rottekongen)

- Replace with this candidate? **NO**

---

## ex 564

Current (score 1): _Image shows clay pigeon shooting, not a fitness exercise. No gym context or fitness movement present._  ![current](PhaseTraining/Resources/ExerciseImages/564.webp)

Candidate (free-exercise-db, license=MIT, score=3/med): _Plank-like core stability position visible, but unclear if this is specifically the shotgun mount drill or similar hold._  ![candidate](db/quality/candidate_thumbs/645795fa79a6c2c334475d1747660fb9ae5856b2.webp)

- URL: `https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Shotgun_Row/0.jpg`
- Attribution: free-exercise-db (yuhonas), MIT

- Replace with this candidate? **NO**

---

## ex 851

Current (score 1): _Image shows children playing dodgeball, not a controlled exercise demonstration with medicine ball._  ![current](PhaseTraining/Resources/ExerciseImages/851.webp)

Candidate (free-exercise-db, license=MIT, score=3/med): _Athlete holds medicine ball in athletic stance but unclear if mid-catch/throw or posed. Ambiguous timing._  ![candidate](db/quality/candidate_thumbs/2e219e481a6cef8b9a0979f5476d74dcf0be0df3.webp)

- URL: `https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Catch_and_Overhead_Throw/0.jpg`
- Attribution: free-exercise-db (yuhonas), MIT

- Replace with this candidate? **NO**

---

## ex 889

Current (score 1): _Host face/talking head shot. No exercise demonstration visible. Text overlay dominates._  ![current](PhaseTraining/Resources/ExerciseImages/889.webp)

Candidate (free-exercise-db, license=MIT, score=3/med): _Athlete in rotational stance with implement, but unclear if this is specifically shotgun mount rotation drill versus similar rotational exercise_  ![candidate](db/quality/candidate_thumbs/645795fa79a6c2c334475d1747660fb9ae5856b2.webp)

- URL: `https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Shotgun_Row/0.jpg`
- Attribution: free-exercise-db (yuhonas), MIT

- Replace with this candidate? **NO**

---

## ex 73

Current (score 3): _Shows a lunge-like stretch position, but unclear if this is the complete World's Greatest Stretch sequence._  ![current](PhaseTraining/Resources/ExerciseImages/73.webp)

Candidate (free-exercise-db, license=MIT, score=4/med): _Plank position with leg positioning visible, likely mid-World's Greatest Stretch sequence_  ![candidate](db/quality/candidate_thumbs/ecbeb0e4173e2a4531e21837a93c8def34e2d128.webp)

- URL: `https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Cat_Stretch/0.jpg`
- Attribution: free-exercise-db (yuhonas), MIT

- Replace with this candidate? **NO**

---

## ex 484

Current (score 2): _Dumbbell squat shown, not a weighted carve squat. Similar lower body exercise but wrong movement pattern._  ![current](PhaseTraining/Resources/ExerciseImages/484.webp)

Candidate (free-exercise-db, license=MIT, score=3/med): _Athlete in squat position with dumbbells, but unclear if performing weighted carve squat or standard dumbbell squat._  ![candidate](db/quality/candidate_thumbs/6d48064e3d4cc82c8f07edf390caf0cc054b74ce.webp)

- URL: `https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Weighted_Jump_Squat/1.jpg`
- Attribution: free-exercise-db (yuhonas), MIT

- Replace with this candidate? **NO**

---

## ex 915

Current (score 2): _Athlete in squat rack with dumbbells, not performing barbell snatch. Related but wrong exercise._  ![current](PhaseTraining/Resources/ExerciseImages/915.webp)

Candidate (wikimedia, license=CC-BY-SA-3.0, score=3/med): _Line drawing shows barbell lift posture, but anatomical sketch lacks detail to confirm snatch versus clean or other Olympic lift._  ![candidate](db/quality/candidate_thumbs/bf356a8ddeb0377c77eff42c33b63efaa25e0284.webp)

- URL: `https://upload.wikimedia.org/wikipedia/commons/thumb/7/7f/One-arm-snatch-1.gif/320px-One-arm-snatch-1.gif`
- Attribution: Wikimedia Commons, CC BY-SA 3.0, author: Everkinetic

- Replace with this candidate? **NO**

---

## ex 7

Current (score 4): _Ab wheel rollout clearly shown mid-motion, but text overlay obscures upper body slightly._  ![current](PhaseTraining/Resources/ExerciseImages/7.webp)

Candidate (free-exercise-db, license=MIT, score=4/high): _Plank position on bench, not ab wheel rollout. Related core exercise but wrong equipment/variation._  ![candidate](db/quality/candidate_thumbs/dd64a86e05e638d3a41562dba65e7dd976f862c2.webp)

- URL: `https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Barbell_Ab_Rollout/1.jpg`
- Attribution: free-exercise-db (yuhonas), MIT

- Replace with this candidate? **NO**

---

## ex 120

Current (score 5): _Clear bear crawl position mid-motion on track, proper form with hands and feet elevated, core engaged._  ![current](PhaseTraining/Resources/ExerciseImages/120.webp)

Candidate (free-exercise-db, license=MIT, score=5/high): _Clear bear crawl position mid-motion: hands and feet planted, hips elevated, neutral spine, bodyweight only._  ![candidate](db/quality/candidate_thumbs/fcb69e1201bc2c9aa7776f40d2ec7a856f32eb94.webp)

- URL: `https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Bear_Crawl_Sled_Drags/1.jpg`
- Attribution: free-exercise-db (yuhonas), MIT

- Replace with this candidate? **NO**

---

## ex 420

Current (score 5): _Athlete clearly demonstrates reverse Nordic curl mid-motion, quadriceps engaged, proper form visible._  ![current](PhaseTraining/Resources/ExerciseImages/420.webp)

Candidate (wger, license=CC-BY-SA 4, score=5/high): _Clear anatomical diagram showing reverse Nordic curl progression with proper form and positioning._  ![candidate](db/quality/candidate_thumbs/a4a72b32d9bc58fc6c71f652c5ec76e65e65fd44.webp)

- URL: `https://wger.de/media/exercise-images/909/159222d9-c1e4-46ae-89ee-6a2dfaab978d.png`
- Attribution: wger.de, CC-BY-SA 4 (author from API: karly)

- Replace with this candidate? **NO**

---

## ex 422

Current (score 4): _Athlete performing lateral deceleration drill with cones visible, but text overlay partially obscures view_  ![current](PhaseTraining/Resources/ExerciseImages/422.webp)

Candidate (free-exercise-db, license=MIT, score=4/med): _Athlete demonstrates lateral deceleration with hand contact, likely stopping drill. Minor: unclear if cone placement is optimal._  ![candidate](db/quality/candidate_thumbs/29cfc81bce17f618be2452341860e546965fbccf.webp)

- URL: `https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Linear_Acceleration_Wall_Drill/0.jpg`
- Attribution: free-exercise-db (yuhonas), MIT

- Replace with this candidate? **NO**

---

## ex 601

Current (score 3): _Single-leg squat position visible but unclear if skater squat specifically; arm position and leg extension ambiguous._  ![current](PhaseTraining/Resources/ExerciseImages/601.webp)

Candidate (free-exercise-db, license=MIT, score=3/med): _Athlete using suspension trainer in single-leg stance, but depth and form ambiguous from this angle._  ![candidate](db/quality/candidate_thumbs/40c8e792bacbd42f59d6b61852c3103ad8e7aa44.webp)

- URL: `https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Single-Leg_High_Box_Squat/0.jpg`
- Attribution: free-exercise-db (yuhonas), MIT

- Replace with this candidate? **NO**

---

## ex 936

Current (score 5): _Clear mid-motion hip abduction machine exercise, proper form visible, gym setting evident_  ![current](PhaseTraining/Resources/ExerciseImages/936.webp)

Candidate (wger, license=CC-BY-SA 4, score=5/high): _Clear mid-motion hip abduction on machine, proper form, legs spread apart against resistance._  ![candidate](db/quality/candidate_thumbs/c24b03f1eb3d9af21e93a598b0b0bad200cf668a.webp)

- URL: `https://wger.de/media/exercise-images/1748/923a3ff7-c269-49bd-9f03-697151a40f06.jpg`
- Attribution: wger.de, CC-BY-SA 4 (author from API: Tierrasverdes)

- Replace with this candidate? **NO**

---

## ex 971

Current (score 4): _Bicycle crunch demonstrated clearly, but large text overlay obstructs view slightly._  ![current](PhaseTraining/Resources/ExerciseImages/971.webp)

Candidate (free-exercise-db, license=MIT, score=4/high): _Clearly bicycle crunch position, slight angle awkwardness and gym background clutter minor issues_  ![candidate](db/quality/candidate_thumbs/c69702506d12fcc016761fc4ee08412b62ed320e.webp)

- URL: `https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Cable_Crunch/0.jpg`
- Attribution: free-exercise-db (yuhonas), MIT

- Replace with this candidate? **NO**

---
