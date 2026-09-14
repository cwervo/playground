/* constants.js -- shared parameters for the retina -> LGN -> V1 -> V2 model.
 *
 * Every population in the model is a named region of ONE flat linear memory
 * (see linear-memory.js).  Region naming convention, in the spirit of the
 * flybrain connectome groups (VIS_R1R6, VIS_ME, ...):
 *
 *   RET.PR_L / PR_M / PR_S / PR_ROD   photoreceptors (L, M, S cones; rods)
 *   RET.HC                            horizontal cells
 *   RET.BP_ON / BP_OFF                bipolar cells (sign-inverting / sign-conserving)
 *   RET.RGC_<ON|OFF>_<M|P>_*          ganglion cells, midget (parvo) / parasol (magno)
 *   RET.DS_<0..3>                     ON-OFF direction-selective ganglion cells
 *   LGN.*                             geniculate relay + contrast gain control
 *   V1.*                              simple / complex / direction / disparity cells
 *   V2.*                              corners, end-stopping, border ownership, texture
 *
 * Numbers below are chosen from the literature cited in README.md; each
 * block says where it comes from.  Units: linear light intensity where a
 * white camera pixel at light level 1.0 == 1.0 ("photopic"); space is in
 * retinal-grid pixels; time is in simulation ticks (one camera frame).
 */

(function (root) {
	'use strict';

	var RV = {};

	/* ---------- geometry ---------- */
	RV.GRID_W = 96;              /* retinal grid (camera downsampled to this) */
	RV.GRID_H = 72;
	RV.V1_STRIDE = 2;            /* V1 hypercolumns sample the LGN every 2 px */
	RV.V1_W = RV.GRID_W / RV.V1_STRIDE;
	RV.V1_H = RV.GRID_H / RV.V1_STRIDE;
	RV.V1_K = 13;                /* receptive-field (perceptron) kernel size, odd */

	/* ---------- memory ---------- */
	RV.MEMORY_BYTES = 12 * 1024 * 1024;   /* one WebAssembly.Memory, fixed size */

	/* ---------- photoreceptors ----------
	 * Naka-Rushton (Naka & Rushton 1966; Boynton & Whitten 1970):
	 *   R = I^n / (I^n + sigma^n)
	 * Cones: sigma tracks the local mean intensity (Weber adaptation) with a
	 * floor, so cones never saturate under steady light.  Rods: sigma is
	 * pinned low, so rods saturate at photopic levels (Aguilar & Stiles 1954).
	 * Photoreceptors HYPERPOLARISE to light: glutamate release g = 1 - R
	 * (dark = depolarised = high release).  Rods are slower than cones.
	 */
	RV.PR = {
		coneN: 1.0,
		coneSigmaFloor: 0.02,
		coneAdaptRate: 0.2,      /* per tick, tracks blurred mean intensity */
		coneAdaptBlur: 4.0,      /* px, spatial pooling of the adaptation signal */
		coneTemporal: 0.7,       /* per-tick update fraction (fast) */
		rodN: 1.0,
		rodSigma: 0.006,         /* fixed -> saturates around I ~ 0.05 */
		rodTemporal: 0.3,        /* slow integration (visual persistence in dim light) */
		rodMixSigma: 0.02,       /* mesopic hand-over: rods dominate below this mean */
		foveaRodFreeRadius: 4.0, /* px, rod-free foveola */
		foveaRodRampRadius: 14.0,/* px, rod density reaches peripheral value here */
		coneEdgeDensity: 0.45,   /* cone density at the grid edge relative to fovea */
		noise: 0.0               /* photon/dark noise amplitude (0 for probes) */
	};

	/* sRGB (linear) -> LMS, Hunt-Pointer-Estevez normalised to D65
	 * (as used by Reinhard et al. 2001).  Rod row is an approximation of the
	 * scotopic luminosity function V'(lambda), peak 507 nm. */
	RV.RGB_TO_LMS = [
		0.3811, 0.5783, 0.0402,
		0.1967, 0.7244, 0.0782,
		0.0241, 0.1288, 0.8444
	];
	RV.RGB_TO_ROD = [0.05, 0.65, 0.30];

	/* ---------- outer plexiform layer / bipolar cells ----------
	 * Horizontal cells feed back a spatially blurred copy of the cone signal
	 * (surround).  ON bipolars invert sign through mGluR6, OFF bipolars keep
	 * it through AMPA/kainate receptors (Werblin & Dowling 1969; Nelson et
	 * al. 1978).  Output is rectified at the ribbon synapse (nonlinear
	 * subunits; Demb 2008; Franke et al. 2017).  Amacrine feedback makes a
	 * transient copy (magno / parasol pathway, DS pathway).
	 */
	RV.OPL = {
		horizontalSigma: 2.5,
		horizontalGain: 1.0,     /* full surround subtraction: no tonic bias on ON vs OFF */
		bipolarGain: 4.0,
		transientRate: 0.35,     /* per-tick low-pass that is subtracted -> high-pass */
		colorBlur: 1.2
	};

	/* ---------- ganglion cells ----------
	 * Difference-of-Gaussians centre/surround (Rodieck 1965; Enroth-Cugell &
	 * Robson 1966).  Midget (parvo): small, sustained; parasol (magno):
	 * ~2-3x larger, transient (Croner & Kaplan 1995).  Ganglion cells are
	 * leaky integrate-and-fire (same form as flybrain's sim-worker.js).
	 */
	RV.RGC = {
		midget:  {centerSigma: 0.9, surroundSigma: 2.8, surroundGain: 0.8},
		parasol: {centerSigma: 1.8, surroundSigma: 5.5, surroundGain: 0.8},
		lifLeak: 0.6,            /* V *= leak each tick */
		lifGain: 20.0,           /* V += gain * drive */
		lifBias: 0.012,          /* tonic drive: steady state 0.6 x threshold (maintained discharge) */
		lifThreshold: 1.0,
		lifRefractory: 1,        /* ticks */
		rateFilter: 0.3,         /* display firing-rate estimate */
		dsNullShifts: 3,         /* px: null-direction inhibition arrives from 1..3 px away */
		dsNullGain: 1.4
	};

	/* ---------- LGN ----------
	 * Relay with divisive contrast gain control (Bonin, Mante & Carandini 2005).
	 * Contrast signal handed to V1: parvo (ON - OFF) + magnoWeight * magno (ON - OFF).
	 */
	RV.LGN = {
		gainSigma: 2.0,          /* large: only strong local contrast compresses */
		gainBlur: 4.0,
		magnoWeight: 0.5
	};

	/* ---------- V1 ----------
	 * Simple cells: Gabor receptive fields (Jones & Palmer 1987) applied as
	 * perceptrons with push-pull ON/OFF input (Hirsch et al. 1998).
	 * Complex cells: energy model (Adelson & Bergen 1985).
	 * Contrast response: divisive normalisation (Heeger 1992; Carandini &
	 * Heeger 2012) -> Naka-Rushton in contrast with n = 2 (Albrecht &
	 * Hamilton 1982).  Orientation half-width at half-height ~20-25 deg in
	 * cat/monkey (De Valois et al. 1982; Ringach et al. 2002).
	 */
	RV.N_ORI = 8;
	RV.SF_LAMBDA = [5, 10];      /* px on the retinal grid */
	RV.GABOR_SIGMA_PER_LAMBDA = 0.4;   /* ~1.5 octave bandwidth */
	RV.GABOR_ASPECT = 0.8;
	RV.V1 = {
		normSigma50: 0.7,        /* semi-saturation of the normalisation pool -> c50 ~ 20% */
		normPoolBlur: 3.0,       /* px on the V1 grid */
		temporal: 0.5,
		refHWHH: 22.0,           /* deg, reference orientation tuning */
		refC50: 0.2,             /* reference contrast response */
		refN: 2.0,
		refSFBandwidthOct: 1.5
	};

	/* ---------- binocular disparity ----------
	 * Disparity energy model (Ohzawa, DeAngelis & Freeman 1990); tuned-
	 * excitatory / near / far classes (Poggio & Fischer 1977).  The "right
	 * eye" is a second camera if you have one, or a horizontally shifted copy
	 * of the left image (synthetic) for demonstration.
	 */
	RV.DISP_MAX = 6;             /* px on the retinal grid */
	RV.N_DISP = 2 * RV.DISP_MAX + 1;

	/* ---------- V2 ----------
	 * Angle / corner selectivity (Ito & Komatsu 2004; Hegde & Van Essen 2000),
	 * end-stopping (Hubel & Wiesel 1965), border ownership (Zhou, Friedman &
	 * von der Heydt 2000; Craft et al. 2007), texture (Freeman et al. 2013;
	 * Ziemba et al. 2016).
	 */
	RV.V2 = {
		endStopOffset: 3,        /* V1-grid px along the bar */
		endStopGain: 1.0,
		boRadius: 8,             /* half-disc radius, V1-grid px */
		boBand: 1.5,             /* ignore energy within this distance of the edge line */
		boGain: 1.0,
		textureBlur: 3.0
	};

	/* ---------- plasticity ----------
	 * Sanger's generalised Hebbian algorithm (Sanger 1989; Oja 1982) on the
	 * V1 simple-cell weight templates.  With random initial weights the
	 * templates develop from camera statistics -- a toy of the visual
	 * "learning to see" that Susan Barry describes in Coming to Our Senses
	 * (2021) and Fixing My Gaze (2009).
	 */
	RV.PLASTICITY = {
		rate: 0.002,
		patchesPerTick: 48
	};

	RV.TICK_MEMORY_SNAPSHOT = true;

	root.RV = RV;
	if (typeof module !== 'undefined' && module.exports) module.exports = RV;
})(typeof self !== 'undefined' ? self : globalThis);
