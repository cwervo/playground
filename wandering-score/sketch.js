/*
 * Wandering Score
 *
 * Coloured pens wander across a sheet of ruled paper while a playhead sweeps
 * left to right, dropping a black dot wherever it crosses a line. Strokes are
 * born, grow, hold, then erode into fragments and vanish; the sheet clears and
 * a fresh score is drawn.
 *
 * Geometry is in "card-width units" (cwu): the paper is exactly 1.0 wide and
 * CARD_H tall, so everything is resolution independent. The constants below
 * were measured off the reference clip (see README.md) at its native 720x1280.
 */

// ---------------------------------------------------------------- constants

const REF_W = 633; // measured paper width, in source pixels

const PAGE_COL = '#f7f5f3';
const CARD_COL = '#fcfaf8';
const RULE_COL = '#e9e4df';
const PLAY_COL = '#3a3a38';
const DOT_COL = '#1a1a1a';

const CARD_H = 844 / REF_W; // 1.333 — paper is 3:4
const CORNER_R = 12 / REF_W;
const STROKE_W = 8 / REF_W;
const DOT_R = 7.5 / REF_W;
const PLAY_W = 2.2 / REF_W;

// Ruled lines, as a fraction of paper height.
const RULES = [0.191, 0.397, 0.603, 0.809];

const SWEEP_SEC = 4.0; // playhead period, measured exactly
const SEG = 0.0048; // pen step length in cwu (~3px at reference scale)

// The pen roams inside an ellipse a little larger than the paper and steered
// back once it leaves. Following the sheet's proportions rather than using a
// plain circle keeps lines from parking off to one side, while still letting
// them run off an edge and return — which is what makes a single stroke read
// as several disconnected pieces.
const ROAM_MARGIN = 0.22;

// p5's default Perlin barely leaves the middle of its range, which would make
// every voice a gentle arc. Fewer octaves widens it; NOISE_GAIN then stretches
// it so the steering signal genuinely saturates and the pens close their loops.
const NOISE_GAIN = 3.5;

// Each voice is a pen with its own handwriting. Turn rates come from radii
// measured off the reference: the tightest scribble reversals are ~10px at the
// reference scale, the indigo loops ~60px, the green sweeps ~180px.
//   turn  heading change per step at full deflection (radians); the resulting
//         radius of curvature is SEG / turn
//   freq  steering-noise cycles per unit path length, i.e. how often the line
//         changes its mind
//   sharp exponent on the steering signal: 1 is evenly curved, higher gives
//         long straight runs punctuated by abrupt corners
//   spin  if set, the pen curves one way only, hard at two points per lap and
//         barely at all between, tracing a flattened oval; `turn` is ignored
//         and the lap is normalised to close on itself, so `freq` alone sets
//         the leaf's size (one lap is 1/freq long). The value is how much
//         curve the straight stretches keep, 0 to 1; `spinPow` sets how
//         abruptly the two turns arrive, i.e. how narrow the leaf is.
//   speed path length laid down per second, in cwu
//   len   total path length, in cwu
const VOICES = {
  loop: { col: '#7c72de', turn: 0.055, freq: 2.2, sharp: 1, speed: 0.55, len: [3.0, 3.8] },
  arc: { col: '#229c77', turn: 0.03, freq: 0.8, sharp: 1, speed: 0.5, len: [2.4, 3.0] },
  angular: { col: '#e7a641', turn: 0.22, freq: 4.0, sharp: 3, speed: 0.32, len: [3.0, 3.8] },
  wave: { col: '#d97aa7', turn: 0.1, freq: 5.0, sharp: 1, speed: 0.55, len: [1.4, 1.9] },
  scribble: { col: '#d3623d', freq: 3.6, spin: 0.02, spinPow: [2, 3.5], speed: 0.26, len: [0.7, 1.1] },
};

// The score, as timed entries. Times are seconds into the cycle and follow the
// reference clip: one pen at a time, then a flurry of small scribbles.
const SCORE = [
  { t: 0.5, voice: 'loop', n: 1 },
  { t: 5.0, voice: 'arc', n: 1 },
  { t: 12.0, voice: 'angular', n: 1 },
  { t: 21.0, voice: 'scribble', n: 8, every: 1.7 },
  { t: 38.0, voice: 'wave', n: 1 },
];

const DISSOLVE_T = 43.0; // erosion begins
const CYCLE_SEC = 74.0; // sheet is blank again by here, and restarts

// ------------------------------------------------------------------- state

let strokes = [];
let cycleStart = 0; // millis()/1000 when this cycle began
let clock = 0; // seconds into the current cycle
let spawned = 0; // how many scheduled strokes have been released
let paused = false;
let grain; // paper texture, drawn once per resize
let card; // { x, y, w, h } of the paper in screen pixels

// -------------------------------------------------------------------- pen

class Stroke {
  constructor(voiceName, t) {
    const v = VOICES[voiceName];
    this.voice = v;
    this.born = t;
    this.target = random(v.len[0], v.len[1]);
    this.laid = 0; // path length laid down so far

    // Independent noise stream per stroke, plus one for its erosion pattern.
    this.nSeed = random(1000);
    this.eSeed = random(1000);
    this.phase = random(100);
    this.spinDir = random() < 0.5 ? -1 : 1;

    if (v.spin) {
      this.spinPow = random(v.spinPow[0], v.spinPow[1]);
      // Steps per lap, and the mean steering over one lap. Dividing by the
      // mean makes each lap turn exactly one full circle, so successive laps
      // stack into a lens instead of fanning out into a rosette.
      this.lapSteps = 1 / v.freq / SEG;
      let sum = 0;
      for (let i = 0; i < 256; i++) {
        sum += this.swell(i / 256);
      }
      this.spinNorm = TWO_PI / ((sum / 256) * this.lapSteps);
    }

    // Start anywhere on the sheet, so a flurry of scribbles scatters rather
    // than clustering in the middle.
    this.pts = [{ x: random(-0.05, 1.05), y: random(-0.05, CARD_H + 0.05) }];
    this.heading = random(TWO_PI);

    // Erosion thresholds are filled in as the path grows.
    this.thresh = [1];

    this.dissolveAt = DISSOLVE_T + random(0, 3.5);
    this.dissolveFor = random(21, 27);
  }

  // Steering profile for a spinning pen, over one lap: near zero along the
  // straights, rising to a peak at each of the two ends.
  swell(lapFrac) {
    const u = 0.5 + 0.5 * Math.cos(2 * TWO_PI * lapFrac);
    return this.voice.spin + (1 - this.voice.spin) * Math.pow(u, this.spinPow);
  }

  get erosion() {
    return constrain((clock - this.dissolveAt) / this.dissolveFor, 0, 1);
  }

  // Grow to the length this pen should have laid down by time `t`. Working
  // from the stroke's age rather than a per-frame delta keeps the drawing
  // identical at any frame rate, and lets it catch up in one go after the tab
  // has been in the background.
  growTo(t) {
    const v = this.voice;
    const want = min(this.target, max(0, t - this.born) * v.speed);

    while (this.laid + SEG <= want) {
      this.laid += SEG;
      this.phase += v.freq * SEG;

      // Steer. A spinning pen curves one way only, hardest twice per cycle,
      // which traces a flattened oval; everything else steers on noise
      // stretched until it saturates, then shaped by `sharp`.
      let d;
      if (v.spin) {
        this.heading += this.swell(this.phase) * this.spinNorm * this.spinDir;
        // A fast, small wobble: it averages out within a lap, so laps land
        // slightly apart rather than precessing away from each other.
        this.heading += (noise(this.phase * 5, this.nSeed) - 0.5) * 0.055;
      } else {
        d = constrain((noise(this.phase, this.nSeed) - 0.5) * NOISE_GAIN, -1, 1);
        d = Math.sign(d) * Math.pow(Math.abs(d), v.sharp);
        this.heading += d * v.turn;
      }

      // Leash back towards the middle once the pen strays outside the roaming
      // ellipse. `q` is 1 on its boundary.
      const last = this.pts[this.pts.length - 1];
      const dx = 0.5 - last.x;
      const dy = CARD_H / 2 - last.y;
      const q = Math.hypot(dx / (0.5 + ROAM_MARGIN), dy / (CARD_H / 2 + ROAM_MARGIN));
      if (q > 1) {
        let diff = Math.atan2(dy, dx) - this.heading;
        diff = ((diff + PI) % TWO_PI + TWO_PI) % TWO_PI - PI;
        this.heading += diff * min(1, (q - 1) * 3) * 0.1;
      }

      const p = {
        x: last.x + cos(this.heading) * SEG,
        y: last.y + sin(this.heading) * SEG,
      };
      this.pts.push(p);

      // Stretch the noise so thresholds actually reach 0 and 1; otherwise the
      // whole stroke would vanish at once around erosion 0.5.
      const i = this.pts.length;
      const n = noise(i * 0.021, this.eSeed);
      this.thresh.push(constrain((n - 0.5) * 3 + 0.5, 0, 1));
    }
  }

  // Runs of consecutive points that have not yet eroded away.
  visibleRuns() {
    const e = this.erosion;
    if (e >= 1) return [];
    // Before erosion starts the line is whole. Testing thresholds here would
    // punch holes early, since some of them clamp to zero.
    if (e <= 0) return [this.pts];
    const runs = [];
    let run = null;
    for (let i = 0; i < this.pts.length; i++) {
      if (this.thresh[i] > e) {
        if (!run) run = [];
        run.push(this.pts[i]);
      } else if (run) {
        if (run.length > 1) runs.push(run);
        run = null;
      }
    }
    if (run && run.length > 1) runs.push(run);
    return runs;
  }
}

// ------------------------------------------------------------------ cycle

function newCycle() {
  const seed = floor(random(1e9));
  randomSeed(seed);
  noiseSeed(seed);
  strokes = [];
  cycleStart = millis() / 1000;
  clock = 0;
  spawned = 0;
}

// Flatten the score into individual spawn times, then release them in order.
function scheduleFor(i) {
  let k = 0;
  for (const entry of SCORE) {
    const n = entry.n || 1;
    for (let j = 0; j < n; j++) {
      if (k === i) return { t: entry.t + j * (entry.every || 0), voice: entry.voice };
      k++;
    }
  }
  return null;
}

function releaseDue() {
  let next;
  while ((next = scheduleFor(spawned)) && next.t <= clock) {
    strokes.push(new Stroke(next.voice, next.t));
    spawned++;
  }
}

// ------------------------------------------------------------------ layout

function layout() {
  // Paper fills 88% of the window width or 66% of its height, whichever binds,
  // matching the framing of the reference clip.
  const w = min(width * 0.88, (height * 0.66) / CARD_H);
  card = { w, h: w * CARD_H, x: (width - w) / 2, y: (height - w * CARD_H) / 2 };
  makeGrain();
}

function makeGrain() {
  grain = createGraphics(ceil(card.w), ceil(card.h));
  grain.clear();
  grain.noStroke();
  const n = floor((card.w * card.h) / 900);
  for (let i = 0; i < n; i++) {
    grain.fill(120, 100, 80, random(6, 16));
    grain.circle(random(grain.width), random(grain.height), random(0.8, 1.9));
  }
}

// ------------------------------------------------------------------ p5 hooks

function setup() {
  createCanvas(windowWidth, windowHeight);
  pixelDensity(min(2, displayDensity()));
  noiseDetail(3, 0.55); // smoother, wider-swinging noise than the default
  layout();
  newCycle();
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  layout();
}

function draw() {
  const now = millis() / 1000;
  if (paused) {
    cycleStart = now - clock; // hold the clock by sliding the cycle's origin
  } else {
    clock = now - cycleStart;
    if (clock >= CYCLE_SEC) newCycle();
    releaseDue();
    for (const s of strokes) s.growTo(clock);
  }

  background(PAGE_COL);
  drawPaper();

  push();
  clipToCard();
  translate(card.x, card.y);
  scale(card.w); // from here on, one unit == one paper width

  const playX = (clock % SWEEP_SEC) / SWEEP_SEC;
  drawStrokes();
  drawPlayhead(playX);
  pop();
}

function drawPaper() {
  noStroke();
  fill(CARD_COL);
  roundedRect(card.x, card.y, card.w, card.h, CORNER_R * card.w);

  stroke(RULE_COL);
  strokeWeight(max(1, card.w * 0.0016));
  for (const f of RULES) {
    const y = card.y + card.h * f;
    line(card.x, y, card.x + card.w, y);
  }
  noStroke();
  image(grain, card.x, card.y, card.w, card.h);
}

function drawStrokes() {
  noFill();
  strokeWeight(STROKE_W);
  strokeCap(ROUND);
  strokeJoin(ROUND);
  for (const s of strokes) {
    stroke(s.voice.col);
    for (const run of s.visibleRuns()) {
      beginShape();
      for (const p of run) vertex(p.x, p.y);
      endShape();
    }
  }
}

function drawPlayhead(x) {
  stroke(PLAY_COL);
  strokeWeight(max(PLAY_W, 1 / card.w));
  line(x, 0, x, CARD_H);

  noStroke();
  fill(DOT_COL);
  for (const s of strokes) {
    for (const run of s.visibleRuns()) {
      for (let i = 1; i < run.length; i++) {
        const a = run[i - 1];
        const b = run[i];
        if (a.x === b.x) continue;
        if ((a.x - x) * (b.x - x) > 0) continue; // no crossing
        const y = a.y + ((x - a.x) / (b.x - a.x)) * (b.y - a.y);
        if (y < 0 || y > CARD_H) continue;
        circle(x, y, DOT_R * 2);
      }
    }
  }
}

// --------------------------------------------------------------- 2D helpers

function roundedRectPath(ctx, x, y, w, h, r) {
  r = min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

function roundedRect(x, y, w, h, r) {
  const ctx = drawingContext;
  roundedRectPath(ctx, x, y, w, h, r);
  ctx.fillStyle = CARD_COL;
  ctx.fill();
}

function clipToCard() {
  const ctx = drawingContext;
  ctx.save();
  roundedRectPath(ctx, card.x, card.y, card.w, card.h, CORNER_R * card.w);
  ctx.clip();
}

// p5's pop() restores the 2D context too, which lifts the clip.

// ----------------------------------------------------------------- controls

function keyPressed() {
  if (key === ' ') paused = !paused;
  else if (key === 'r' || key === 'R') newCycle();
  else if (key === 's' || key === 'S') saveCanvas('wandering-score', 'png');
}

function mousePressed() {
  newCycle();
}
