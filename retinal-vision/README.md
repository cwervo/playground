# Retinal Vision

Camera light → retina (rods, cones, horizontal, bipolar, ganglion cells) → LGN → V1 → V2, running live in the browser, with every neuron population living in **one flat linear memory** and every cortical cell implemented as a **perceptron** (a weight vector in that memory, a dot product, a nonlinearity).

The code is modelled on [snedea/flybrain](https://github.com/snedea/flybrain): plain-script JavaScript, a leaky integrate-and-fire simulation in a Web Worker (`js/sim-worker.js`), a main-thread bridge (`js/worker-bridge.js`), a renderer that draws neuron state (`js/neuro-renderer.js`), named populations in `js/constants.js`, and an `index.html` that loads them in order. Where flybrain runs a connectome, this runs the classical and recent physiology of the early visual pathway and lets you measure the model's **polarity and field-stimulus response curves** (orientation, contrast, spatial frequency, direction, intensity, area summation, receptive-field maps, disparity) against reference curves from the literature.

## Run it

```
cd retinal-vision
python3 -m http.server 8080      # or: npm start
# open http://localhost:8080/  (camera needs localhost or https)
```

Allow camera access. With no camera the page falls back to a synthetic drifting scene. Tests:

```
npm test                          # node --test, no dependencies
```

## What you see

| Stage | Panel | What is computed |
|---|---|---|
| Light | camera | 96×72 downsample of the camera, sRGB → linear |
| Photoreceptors | cones L,M,S | Naka–Rushton hyperpolarisation with Weber adaptation (σ tracks the local mean) |
| | rods | Naka–Rushton with fixed σ: saturate in bright light, absent in the foveola, slow |
| Outer plexiform | bipolar ON / OFF | horizontal-cell surround subtracted; ON is sign-inverting (mGluR6), OFF sign-conserving; rectified |
| | L−M | cone-opponent (midget) colour signal |
| Ganglion cells | midget / parasol spikes | DoG pooling → leaky integrate-and-fire; midget sustained, parasol transient |
| | direction-selective | ON–OFF DSGCs, Barlow–Levick null-direction inhibition from the transient channel |
| LGN | ON − OFF | relay with divisive contrast gain control |
| V1 | complex, SF 0 / SF 1 | hue = preferred orientation; energy model + divisive normalisation |
| | simple, even phase | green = bright-bar (ON-centre) cell wins, magenta = dark-bar (OFF-centre) cell wins |
| | direction | spatiotemporal quadrature (hue = motion direction) |
| | disparity | near (red) / zero (green) / far (blue), needs stereo |
| V2 | corners | co-located orthogonal orientations |
| | end-stopped | bar terminations |
| | border ownership | which side of an edge the figure is on |
| | texture | pooled energy × orientation heterogeneity |

Controls:

- **Light level** slides from scotopic (10⁻⁴, rods only, nothing in the rod-free fovea) through mesopic to photopic. Watch the rod panel bleach out and the cone panel take over.
- **Stereo**: second camera for real binocular input, or a synthetic shifted copy of the left image.
- **Plasticity**: Sanger's generalised Hebbian algorithm on the V1 simple-cell templates. "Reset: random (newborn) + learn" starts from random weights and lets camera statistics grow the receptive fields. Watch the template strip.
- **Probes**: run a tuning-curve experiment on the running model; the measured curve is drawn over the literature reference (dashed).

## Linear memory

Everything neural is in one `WebAssembly.Memory` (`js/linear-memory.js`), carved up by a bump allocator into named, 64-byte-aligned regions, like a static data segment:

```
offset      bytes     type  count   name
0x00000000     27648   f32    6912  RET.IN_R
...
0x000bd000     27648   f32    6912  RET.RGC_ON_M_V
0x000c3c00      6912    u8    6912  RET.RGC_ON_M_SPK
...
0x001b0000     21632   f32    5408  V1.PERCEPTRON_W
0x001ba900    110592   f32   27648  V1.SIMPLE_E
...
0x002bb100      6912   f32    1728  V2.TEXTURE
brk = 0x2c1d00 (2891008 of 12582912 bytes)
```

The worker posts a memcpy of the used segment after each tick, and the renderer views populations in that dump by offset using the map. The "map" button on the page prints the full listing.

## The model, stage by stage

**Photoreceptors.** Camera RGB (linear) is weighted into L, M, S cone and rod intensities. Each receptor follows Naka–Rushton, `R = Iⁿ / (Iⁿ + σⁿ)`; cones adapt (σ tracks a spatially pooled running mean of intensity, with a floor), so under steady light they encode contrast (Weber); rods have a fixed low σ so they saturate around photopic levels. Photoreceptors hyperpolarise to light, so glutamate release is `1 − R`; rods are slower than cones; rod density is zero in the central foveola and ramps up with eccentricity, cone density falls off toward the edge.

**Horizontal and bipolar cells.** Horizontal cells feed back a Gaussian-blurred copy of the receptor signal. ON bipolars invert sign (`relu(surround − centre)` in glutamate units, i.e. centre brighter than surround), OFF bipolars conserve it. Rod signals enter the same bipolars through a mesopic mixing weight (the AII amacrine route). Amacrine feedback produces a transient copy (high-pass) for the magno and direction-selective pathways.

**Ganglion cells.** Four LIF populations (ON/OFF × midget/parasol) pool bipolar input through a difference of Gaussians and integrate with leak, threshold, refractory period and a tonic bias current (maintained discharge). Spikes are displayed; the LGN receives the analytic mean rate of the same LIF neuron for a given drive. Direction-selective cells: excitation now minus the strongest transient signal that was 1–3 px away on the null side one tick ago.

**LGN.** `D = (ON − OFF)midget + 0.5·(ON − OFF)parasol`, divided by a blurred local contrast pool.

**V1 simple cells** are perceptrons: 32 weight templates (8 orientations × 2 spatial frequencies × even/odd phase, Gabor by default) applied at every position of a 48×36 grid with stride 2. Push-pull ON/OFF input (ON subregions excited by ON-LGN and inhibited by OFF-LGN) is exactly `w · (ON − OFF)`, so the perceptron reads the signed field `D`. Rectifying the signed drive gives the four polarity classes (bright-bar, dark-bar, and the two edge polarities). **Complex cells** are the energy `√(E² + O²)`; **normalisation** divides squared energy by a spatially pooled sum over all channels, giving a Naka–Rushton contrast response with n = 2 and cross-orientation suppression. **Direction cells** use temporal quadrature between the current and previous frame. **Disparity cells** are binocular energy units over a right-eye contrast field shifted by −6…+6 px.

**V2** reads the normalised complex maps: corner cells (geometric mean of orthogonal orientations), end-stopped cells (energy minus same-orientation energy 3 px along the bar), border-ownership cells (edge energy weighted by the asymmetry of total energy in the two half-discs beside the edge, ignoring a band around the edge itself) and a texture channel.

**Plasticity.** With learning on, random K×K patches of `D` are normalised and fed to the SF-0 templates with Sanger's rule `Δwᵢ = η yᵢ (x − Σⱼ≤ᵢ yⱼ wⱼ)`, followed by renormalisation. From random weights the templates converge to the principal components of the input patches, which for natural input are oriented, band-pass filters.

## Response curves the model reproduces

All measured in the browser with the **Probe** panel, or in `tests/pipeline.test.js`:

- **Photoreceptor intensity–response**: Naka–Rushton for cones from dark, shifted right after adaptation to a background (Weber), and for rods (saturating ~2 log units lower).
- **Ganglion area summation**: rises to a small optimal spot then falls as the surround is recruited.
- **Receptive-field maps by spot flashing** (bright − dark): concentric centre–surround for the ON midget cell; an oriented ON band with OFF flanks for the V1 even simple cell (Hubel & Wiesel; Jones & Palmer).
- **Orientation tuning**: von Mises-like, half-width at half-height ~20–25°, orthogonal response near zero.
- **Contrast response**: Naka–Rushton-like, graded from ~1%, saturating around 20%.
- **Spatial-frequency tuning**: band-pass in log frequency, ~1.5 octave bandwidth per channel.
- **Direction tuning**: V1 direction cells and retinal DSGCs each respond to one direction only.
- **Disparity tuning**: random-dot stereograms drive near / tuned-zero / far energy cells at their preferred disparity.

## Biology and references

The book that motivated this: Susan R. Barry, *Coming to Our Senses: A Boy Who Learned to See, a Girl Who Learned to Hear, and How We All Discover the World* (Basic Books, 2021) and her earlier *Fixing My Gaze* (2009). Both are about vision being learned: Liam, who gained sight as a teenager, first saw lines, edges and colours and had to learn to group them into objects; Barry herself gained stereopsis in adulthood. The plasticity mode (random templates → learned oriented filters), the separate ON/OFF, orientation, motion and disparity channels, and the V2 grouping stages are the parts of that story this model touches.

Classical physiology the equations come from:

- Naka & Rushton (1966) J Physiol; Boynton & Whitten (1970) Science — photoreceptor intensity–response.
- Aguilar & Stiles (1954) Optica Acta — rod saturation.
- Curcio et al. (1990) J Comp Neurol — human photoreceptor topography (rod-free foveola).
- Werblin & Dowling (1969) J Neurophysiol; Nelson et al. (1978) J Comp Neurol — ON/OFF bipolar polarity.
- Rodieck (1965) Vision Res; Enroth-Cugell & Robson (1966) J Physiol — DoG centre–surround.
- Croner & Kaplan (1995) Vision Res — midget vs parasol receptive-field sizes.
- Barlow & Levick (1965) J Physiol — null-direction inhibition.
- Bonin, Mante & Carandini (2005) J Neurosci — LGN contrast gain control.
- Hubel & Wiesel (1962, 1965) J Physiol — simple, complex and end-stopped cells.
- Jones & Palmer (1987) J Neurophysiol — Gabor fits to simple-cell receptive fields.
- Hirsch et al. (1998) J Neurosci — push-pull ON/OFF subregions.
- Adelson & Bergen (1985) J Opt Soc Am A — energy model, spatiotemporal quadrature.
- Heeger (1992) Vis Neurosci; Carandini & Heeger (2012) Nat Rev Neurosci — divisive normalisation.
- Albrecht & Hamilton (1982) J Neurophysiol — V1 contrast response (Naka–Rushton, n ≈ 2).
- De Valois et al. (1982) Vision Res; Ringach et al. (2002) J Neurosci — orientation and SF bandwidths.
- Ohzawa, DeAngelis & Freeman (1990) Science; Poggio & Fischer (1977) J Neurophysiol — disparity energy, near/far/tuned cells.
- Ito & Komatsu (2004) J Neurosci; Hegdé & Van Essen (2000) J Neurosci — V2 angle selectivity.
- Zhou, Friedman & von der Heydt (2000) J Neurosci; Craft et al. (2007) J Neurophysiol — border ownership.
- Freeman et al. (2013) Nat Neurosci; Ziemba et al. (2016) PNAS — V2 texture selectivity.
- Oja (1982) J Math Biol; Sanger (1989) Neural Networks — Hebbian PCA learning.

Animal work from the last decade that shaped the retinal and cortical choices (functional cell types, inner-retinal nonlinearity, plasticity after the critical period, disparity across mouse cortex):

- Baden et al. (2016) Nature — ~30+ functional ganglion-cell types in mouse retina (the ON/OFF, sustained/transient, direction-selective split modelled here is the coarse version).
- Franke et al. (2017) Nature — inhibition decorrelates bipolar-cell feature channels; rectified bipolar output.
- Sinha et al. (2017) Cell — foveal cone and midget circuit dynamics in primate.
- Tran et al. (2019) Neuron; Peng et al. (2019) Cell — single-cell atlases of mouse and primate retinal ganglion cells.
- Wei (2018) Annu Rev Neurosci — mechanisms of retinal direction selectivity.
- Szatko et al. (2020) Nat Commun; Qiu et al. (2021) Curr Biol — retinal specialisations for natural scene statistics.
- Fong, Mitchell, Duffy & Bear (2016) PNAS; Duffy et al. (2018) J Comp Neurol — recovery from monocular deprivation after the critical period (the plasticity slider is a cartoon of this).
- La Chioma, Bonhoeffer & Hübener (2019) Curr Biol — disparity tuning mapped across mouse visual areas.
- de Vries et al. (2020) Nat Neurosci; Siegle et al. (2021) Nature — large-scale surveys of mouse visual cortex responses (orientation, SF, temporal tuning across areas).

## Honest limits

- No foveal magnification, no eye movements, no LGN lamination, one V1 grid; V2 is four hand-built feature detectors, not a learned area.
- Time is one camera frame per tick (~60 ms), so temporal dynamics (rod slowness, transients, direction selectivity) are coarse.
- Parameters are set to reproduce the *shapes* of the classical curves; absolute units are arbitrary (see `js/constants.js` for each block's source).
- Learned templates are principal components (oriented, but not the sparse Gabor set that sparse coding gives).

## Layout

```
retinal-vision/
  index.html              entry point (script order matters, like flybrain)
  css/main.css
  js/constants.js         populations, parameters, citations
  js/linear-memory.js     one WebAssembly.Memory, bump allocator, memory map
  js/response-curves.js   Naka-Rushton, Gabor, von Mises, LIF rate, DoG, ...
  js/stimuli.js           gratings, spots, bars, synthetic scene
  js/retina.js            photoreceptors -> horizontal -> bipolar -> ganglion LIF -> DSGC
  js/cortex.js            LGN -> V1 perceptrons -> V2; Sanger learning
  js/sim-worker.js        the simulation worker + probe experiments
  js/worker-bridge.js     camera capture, frame pump, memory snapshots
  js/neuro-renderer.js    panels, tuning-curve plots, RF maps
  js/main.js              UI wiring
  tests/pipeline.test.js  node --test
```
