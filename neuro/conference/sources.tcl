# sources.tcl — where each instrument in this battery came from, and what the
# literature says about it now.
#
# Written as Tcl data rather than JSON so it loads with `source` and needs no
# parser. Every entry is real and was checked against a live search in August
# 2026; `oa` marks open access, `url` is the most durable link found.
#
# Two lists per test:
#   origin   the 20th-century work that created the measurement
#   modern   what has happened to it since, weighted toward the last three years
#
# The `verdict` line is the editorial judgement this project reached about how
# much weight the measurement can carry in THIS record. It is opinion, and it is
# labelled as opinion.

set SOURCES {}

# ---------------------------------------------------------------------------
dict set SOURCES eeg {
    test    "Resting quantitative EEG"
    origin {
        {key BERGER1929
         cite "Berger H. Über das Elektrenkephalogramm des Menschen. Archiv für Psychiatrie und Nervenkrankheiten. 1929;87:527-570."
         note "The first human EEG. Berger recorded it in 1924 at Jena and sat on the data for five years, terrified of being wrong. He named the alpha and beta waves this battery still reports."
         url  "https://link.springer.com/article/10.1007/BF01797193"
         oa   1
         pdf  "Springer, open access. English: Gloor P, trans. Hans Berger on the EEG of Man. Electroencephalogr Clin Neurophysiol Suppl 28, 1969."}
        {key ADRIAN1934
         cite "Adrian ED, Matthews BHC. The Berger rhythm: potential changes from the occipital lobes in man. Brain. 1934;57(4):355-385."
         note "The replication that made the field believe Berger. Adrian put himself in the chair and showed alpha blocking on eye opening -- the same eyes-open/eyes-closed contrast printed on page 6 of this report."
         url  "https://doi.org/10.1093/brain/57.4.355"
         oa   0
         pdf  ""}
        {key JOHN1977
         cite "John ER, Karmel BZ, Corning WC, et al. Neurometrics: numerical taxonomy identifies different profiles of brain functions within groups of behaviorally similar people. Science. 1977;196(4297):1393-1410."
         note "The origin of the normative-database idea: score a patient's spectrum in z-units against an age-matched reference population. Every head map in this report is a descendant."
         url  "https://doi.org/10.1126/science.867036"
         oa   0
         pdf  ""}
        {key PASCUAL1994
         cite "Pascual-Marqui RD, Michel CM, Lehmann D. Low resolution electromagnetic tomography: a new method for localizing electrical activity in the brain. Int J Psychophysiol. 1994;18(1):49-65."
         note "LORETA. The inverse solution this report tried and failed to run, because 15 usable channels is below its floor."
         url  "https://pubmed.ncbi.nlm.nih.gov/7876038/"
         oa   0
         pdf  ""}
    }
    modern {
        {key TBRMULTI2026
         cite "Theta-Beta Ratio in Attention Deficit Hyperactivity Disorder: A Multiverse Analysis. eLife (reviewed preprint) 111114; medRxiv 2026.01.08.26343676. January 2026."
         note "576 defensible analysis pipelines run across Healthy Brain Network (N=1,499) and an independent validation sample (N=381). The conclusion is that individual alpha peak frequency and aperiodic (1/f) activity shape TBR estimates, and that apparent ADHD-control TBR differences are substantially driven by aperiodic differences rather than by oscillatory theta or beta. This is the single most load-bearing recent citation for this record."
         url  "https://elifesciences.org/articles/111114"
         oa   1
         pdf  "eLife, open access"}
        {key ARNS2013
         cite "Arns M, Conners CK, Kraemer HC. A decade of EEG theta/beta ratio research in ADHD: a meta-analysis. J Atten Disord. 2013;17(5):374-383."
         note "The paper that broke the TBR story: effect sizes declining year on year, consistent with a shrinking true effect or a shifting control population."
         url  "https://journals.sagepub.com/doi/abs/10.1177/1087054712460087"
         oa   0
         pdf  ""}
        {key TBRSOFT2019
         cite "EEG theta/beta ratio calculations differ between various EEG neurofeedback and assessment software packages: clinical interpretation. Appl Psychophysiol Biofeedback. 2019."
         note "Different vendors compute a different number from the same recording. Directly relevant to a report that prints 2.190 against a threshold of 2.1 with no band definition attached to the quotient."
         url  "https://pubmed.ncbi.nlm.nih.gov/31845611/"
         oa   0
         pdf  ""}
    }
    verdict "Berger's measurement is a century old and sound. The normative-database layer on top of it is the weak joint, and this record hits every one of its weak points at once: reduced montage, a threshold whose tables stop at the subject's age, and a ratio the 2026 multiverse work says is confounded by exactly the alpha peak this subject has."
}

# ---------------------------------------------------------------------------
dict set SOURCES erp {
    test    "Event-related potentials (P300a, P300b, N100)"
    origin {
        {key SUTTON1965
         cite "Sutton S, Braren M, Zubin J, John ER. Evoked-potential correlates of stimulus uncertainty. Science. 1965;150(3700):1187-1188."
         note "The discovery of P300. Uncertainty about which modality was coming next produced a large positivity peaking near 300 ms. Everything on page 5 of this report descends from these two pages."
         url  "https://www.science.org/doi/10.1126/science.150.3700.1187"
         oa   0
         pdf  "Paywalled at Science; widely mirrored."}
        {key SQUIRES1975
         cite "Squires NK, Squires KC, Hillyard SA. Two varieties of long-latency positive waves evoked by unpredictable auditory stimuli in man. Electroencephalogr Clin Neurophysiol. 1975;38(4):387-401."
         note "The split this whole record turns on. P3a (~240 ms, frontocentral) fires whether or not the subject attends; P3b (~350 ms, parietal) appears only under active attention. The vendor prints both and never divides one by the other."
         url  "https://pubmed.ncbi.nlm.nih.gov/46819/"
         oa   0
         pdf  "PDF on academia.edu"}
        {key DAVIS1939
         cite "Davis PA. Effects of acoustic stimuli on the waking human brain. J Neurophysiol. 1939;2(6):494-499."
         note "The vertex potential -- the N1/P2 complex that the N100 in this report is the visual cousin of."
         url  "https://doi.org/10.1152/jn.1939.2.6.494"
         oa   0
         pdf  ""}
        {key HALLIDAY1972
         cite "Halliday AM, McDonald WI, Mushin J. Delayed visual evoked response in optic neuritis. Lancet. 1972;299(7758):982-985."
         note "The paper that made pattern-reversal VEP a clinical test. Normal major positivity peaks near 120 ms; in optic neuritis it went to a mean of 155 ms and stayed delayed after acuity recovered. It is the reason a delayed checkerboard response gets attention -- and the reason the check size and luminance used to elicit it are not optional details."
         url  "https://pubmed.ncbi.nlm.nih.gov/4112367/"
         oa   0
         pdf  ""}
        {key ROSVOLD1956
         cite "Rosvold HE, Mirsky AF, Sarason I, Bransome ED, Beck LH. A continuous performance test of brain damage. J Consult Psychol. 1956;20(5):343-350."
         note "The button-press task. Built at NIH as a screen for brain damage, not for attention disorders -- a provenance worth remembering when omission and commission rates are read as an ADHD profile."
         url  "https://pubmed.ncbi.nlm.nih.gov/13367264/"
         oa   0
         pdf  ""}
    }
    modern {
        {key POLICH2007
         cite "Polich J. Updating P300: an integrative theory of P3a and P3b. Clin Neurophysiol. 2007;118(10):2128-2148."
         note "The standard modern synthesis, and open access. P3a = frontal orienting driven by stimulus novelty; P3b = temporal-parietal context updating and memory consolidation. The ratio between them is a statement about where a system's resources stop."
         url  "https://pmc.ncbi.nlm.nih.gov/articles/PMC2715154/"
         oa   1
         pdf  "PMC2715154, free full text"}
        {key P3DEP2021
         cite "A reduced P300 prospectively predicts increased depressive severity in adults with clinical depression. 2021."
         note "P300 amplitude as a prospective predictor rather than a correlate. Relevant because this subject's affective load is the strongest signal in the record."
         url  "https://pubmed.ncbi.nlm.nih.gov/33433019/"
         oa   0
         pdf  ""}
        {key P3DEPANX2015
         cite "Source analysis of P3a and P3b components to investigate interaction of depression and anxiety in attentional systems. Sci Rep. 2015;5:17138."
         note "Depression loaded on P3b -- conscious attention and memory updating -- and not on P3a, the bottom-up orienting component. That is the exact dissociation this record shows, arrived at independently."
         url  "https://www.nature.com/articles/srep17138"
         oa   1
         pdf  "Scientific Reports, open access"}
        {key ERPADHD2025
         cite "The discriminate value of event-related potentials in executive function of ADHD and comorbidity of ADHD and ASD. Sci Rep. 2025."
         note "Recent attempt at ERP-based discrimination; useful mainly for how modest the discriminative performance still is."
         url  "https://www.nature.com/articles/s41598-025-94156-1"
         oa   1
         pdf  "Scientific Reports, open access"}
    }
    verdict "The strongest instrument in the battery and the most under-used. Squires drew the P3a/P3b line in 1975, Polich formalised what it means in 2007, and the vendor states the 50% criterion in prose on the ERP page without ever computing the quotient."
}

# ---------------------------------------------------------------------------
dict set SOURCES hrv {
    test    "Heart rate variability and resting ECG"
    origin {
        {key EINTHOVEN1903
         cite "Einthoven W. Die galvanometrische Registrirung des menschlichen Elektrokardiogramms, zugleich eine Beurtheilung der Anwendung des Capillar-Elektrometers in der Physiologie. Pflügers Arch. 1903;99:472-480."
         note "The string galvanometer. Preliminary report 1901, full description with tracings 1903, Nobel Prize 1924. The P, Q, R, S, T letters on page 4 of this report are Einthoven's."
         url  "https://pmc.ncbi.nlm.nih.gov/articles/PMC2435435/"
         oa   1
         pdf  "History and reproductions: PMC2435435, free full text"}
        {key BAZETT1920
         cite "Bazett HC. An analysis of the time-relations of electrocardiograms. Heart. 1920;7:353-370."
         note "QTc. The formula behind the 393 ms on this subject's 12-lead, and a formula everyone knows over-corrects at high rates and under-corrects at low ones -- worth stating on a tracing recorded at 57 bpm."
         url  "https://doi.org/10.1111/j.1542-474X.1997.tb00325.x"
         oa   0
         pdf  "Reprinted in Ann Noninvasive Electrocardiol 1997;2:177-194."}
        {key WASSERBURGER1961
         cite "Wasserburger RH, Alt WJ. The normal RS-T segment elevation variant. Am J Cardiol. 1961;8(2):184-192."
         note "The paper that named what this subject's 12-lead shows: concave ST elevation with a J-point notch or slur, common in young men, and benign in the form described here."
         url  "https://www.sciencedirect.com/science/article/abs/pii/0002914961902041"
         oa   0
         pdf  ""}
        {key AKSELROD1981
         cite "Akselrod S, Gordon D, Ubel FA, Shannon DC, Barger AC, Cohen RJ. Power spectrum analysis of heart rate fluctuation: a quantitative probe of beat-to-beat cardiovascular control. Science. 1981;213(4504):220-222."
         note "The origin of the VLF/LF/HF decomposition on page 4. It showed that sympathetic and parasympathetic activity make frequency-specific contributions, and -- crucially for this record -- that renin-angiotensin activity strongly modulates the peak near 0.04 Hz, which is the VLF band."
         url  "https://pubmed.ncbi.nlm.nih.gov/6166045/"
         oa   0
         pdf  ""}
        {key TASKFORCE1996
         cite "Task Force of the European Society of Cardiology and the North American Society of Pacing and Electrophysiology. Heart rate variability: standards of measurement, physiological interpretation, and clinical use. Circulation. 1996;93(5):1043-1065."
         note "The standard that says VLF from short recordings is of dubious validity and should be avoided. This report computes a VLF-based flag from a two-minute epoch."
         url  "https://www.ahajournals.org/doi/10.1161/01.CIR.93.5.1043"
         oa   1
         pdf  "Circulation, free"}
    }
    modern {
        {key USUI2017
         cite "Usui H, Nishida Y. The very low-frequency band of heart rate variability represents the slow recovery component after a mental stress task. PLoS One. 2017;12(8):e0182611."
         note "VLF as a slow post-stress recovery component rather than a pure sympathetic index. Open access."
         url  "https://pmc.ncbi.nlm.nih.gov/articles/PMC5555691/"
         oa   1
         pdf  "PMC5555691, free full text"}
        {key VLFIL6_2026
         cite "Relationship between very low frequency heart rate variability and interleukin-6 levels in healthy young individuals. 2026."
         note "IL-6 showed substantial positive associations with 24-hour and night-time VLF, suggesting VLF is a distinctive indicator of serum IL-6 in young adults. The closest thing in the current literature to a mechanism for the vendor's neuroinflammation flag -- and note the recording lengths: 24-hour and night-time, not two minutes."
         url  "https://pubmed.ncbi.nlm.nih.gov/41967146/"
         oa   0
         pdf  ""}
        {key HRVINFLAM2014
         cite "Heart rate variability predicts levels of inflammatory markers: evidence for the vagal anti-inflammatory pathway. Brain Behav Immun. 2015;45:98-105."
         note "Robust inverse relations between HF-HRV and IL-6, CRP and fibrinogen. Supports reading this subject's 11.1% HF fraction as the informative number rather than the VLF absolute."
         url  "https://www.sciencedirect.com/science/article/abs/pii/S0889159114006060"
         oa   0
         pdf  ""}
        {key HRVBRAINHEART2025
         cite "Heart rate variability: a multidimensional perspective from physiological marker to brain-heart axis disorders prediction. Front Cardiovasc Med. 2025;12:1630668."
         note "Current review of the brain-heart axis framing that the vendor's arousal-regulation domain implicitly assumes."
         url  "https://www.frontiersin.org/journals/cardiovascular-medicine/articles/10.3389/fcvm.2025.1630668/full"
         oa   1
         pdf  "Frontiers, open access"}
    }
    verdict "Einthoven and Akselrod are unimpeachable. The application here is not: a 1996 standard says do not compute VLF from short records, and the 2026 IL-6 work that would justify the inflammation reading used 24-hour recordings. The direction survives on the strength of HF fraction and LF/HF; the absolute VLF figure should not be quoted."
}

# ---------------------------------------------------------------------------
dict set SOURCES spt {
    test    "Percutaneous allergy skin testing"
    origin {
        {key BLACKLEY1873
         cite "Blackley CH. Experimental Researches on the Causes and Nature of Catarrhus Aestivus (Hay-Fever or Hay-Asthma). London: Bailliere Tindall & Cox; 1873."
         note "Blackley abraded his own forearm, applied grass pollen, and watched it swell. Every one of the 58 sites on this subject's arm is a repetition of that experiment. Public domain."
         url  "https://archive.org/details/experimentalrese00blac"
         oa   1
         pdf  "Internet Archive, full scan, public domain"}
        {key LEWIS1927
         cite "Lewis T. The Blood Vessels of the Human Skin and their Responses. London: Shaw & Sons; 1927."
         note "The triple response -- red line, flare, wheal. The reason a positive skin test is scored by measuring a wheal in millimetres at all, and the reason the histamine control has to work for the sheet to mean anything."
         url  "https://en.wikipedia.org/wiki/Triple_response_of_Lewis"
         oa   0
         pdf  ""}
        {key LEWISGRANT1924
         cite "Lewis T, Grant RT. Vascular reactions of the skin to injury. Part II: the liberation of a histamine-like substance in injured skin. Heart. 1924;11:209-265."
         note "The first description of the prick method as such."
         url  ""
         oa   0
         pdf  ""}
        {key PEPYS1975
         cite "Pepys J. Skin testing. Br J Hosp Med. 1975;14:412-417."
         note "The modification that turned a research manoeuvre into a routine clinic procedure, and the direct ancestor of the plastic multi-head device that made the marks on this subject's arm."
         url  ""
         oa   0
         pdf  ""}
        {key DREBORG1989
         cite "Dreborg S, ed. Skin tests used in type I allergy testing. Position paper of the EAACI Sub-Committee on Skin Tests. Allergy. 1989;44(Suppl 10):1-59."
         note "Where the >=3 mm positivity threshold and the mandatory positive and negative controls come from. This sheet passes both controls -- histamine 7 mm, glycerin 0 mm -- which is what makes it interpretable at all."
         url  ""
         oa   0
         pdf  ""}
    }
    modern {
        {key WAO2020
         cite "IgE allergy diagnostics and other relevant tests in allergy: a World Allergy Organization position paper. World Allergy Organ J. 2020;13(2):100080."
         note "Current position on what a wheal measurement does and does not establish: sensitisation, not clinical allergy, absent exposure history."
         url  "https://www.worldallergyorganizationjournal.org/article/S1939-4551(19)31236-0/fulltext"
         oa   1
         pdf  "WAO Journal, open access"}
        {key AH_IMPAIR2025
         cite "Impact of antihistamines on sleep, cognition, and daily functioning: evidence from primary and community care. 2025."
         note "Relates blood-brain-barrier penetration, central H1 binding and sedative potential to daytime sleepiness, cognitive failures and functional impairment. The literature that makes this record's blank Medications field a first-order problem rather than an administrative one."
         url  "https://pubmed.ncbi.nlm.nih.gov/42011952/"
         oa   0
         pdf  ""}
        {key AH_DEMENTIA2024
         cite "Cumulative dose effects of H1 antihistamine use on the risk of dementia in patients with allergic rhinitis. J Allergy Clin Immunol Pract. 2024."
         note "Long-horizon signal on cumulative anticholinergic and H1 exposure. Not directly about a single afternoon's reaction time, but it is why 'which antihistamine, at what dose, for how long' is a question worth answering."
         url  "https://www.jaci-inpractice.org/article/S2213-2198(24)00541-5/abstract"
         oa   0
         pdf  ""}
        {key AR_BRAINSTEM2025
         cite "Auditory function and brainstem responses in allergic rhinitis: systematic review and meta-analysis. 2025."
         note "Allergic rhinitis measurably perturbs evoked potential latencies in a sensory modality nobody suspected. Direct precedent for asking whether a 288 ms visual N100 is neurology or nasal mucosa."
         url  "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12533529/"
         oa   1
         pdf  "PMC12533529, free full text"}
    }
    verdict "The oldest technique in the battery and the least contested. 26 of 58 positive with valid controls is a real and substantial finding. What it does not establish on its own is clinical severity, and what it makes urgent is the unanswered medication question."
}

# ---------------------------------------------------------------------------
dict set SOURCES psych {
    test    "Self-report instruments (PHQ-9, GAD-7, PCL-C, vendor screener)"
    origin {
        {key HAMILTON1959
         cite "Hamilton M. The assessment of anxiety states by rating. Br J Med Psychol. 1959;32(1):50-55."
         note "The ancestor of every anxiety scale in clinical use, GAD-7 included."
         url  "https://doi.org/10.1111/j.2044-8341.1959.tb00467.x"
         oa   0
         pdf  ""}
        {key SPITZER1994
         cite "Spitzer RL, Williams JB, Kroenke K, et al. Utility of a new procedure for diagnosing mental disorders in primary care: the PRIME-MD 1000 study. JAMA. 1994;272(22):1749-1756."
         note "PRIME-MD, the instrument PHQ-9 was cut down from."
         url  "https://pubmed.ncbi.nlm.nih.gov/7966923/"
         oa   0
         pdf  ""}
        {key WEATHERS1993
         cite "Weathers FW, Litz BT, Herman DS, Huska JA, Keane TM. The PTSD Checklist (PCL): reliability, validity, and diagnostic utility. Presented at: 9th Annual Meeting of the International Society for Traumatic Stress Studies; October 1993; San Antonio, TX."
         note "The PCL-C. Note that the foundational reference is a conference paper, not a journal article -- unusual provenance for an instrument this widely used, and the reason its cut-off has drifted between 30 and 50 across populations."
         url  "https://www.ptsd.va.gov/professional/assessment/adult-sr/ptsd-checklist.asp"
         oa   1
         pdf  "VA National Center for PTSD, free"}
    }
    modern {
        {key KROENKE2001
         cite "Kroenke K, Spitzer RL, Williams JBW. The PHQ-9: validity of a brief depression severity measure. J Gen Intern Med. 2001;16(9):606-613."
         note "PHQ-9 proper. 10-14 is the moderate band; this subject scores 12. Open access."
         url  "https://pmc.ncbi.nlm.nih.gov/articles/PMC1495268/"
         oa   1
         pdf  "PMC1495268, free full text"}
        {key SPITZER2006
         cite "Spitzer RL, Kroenke K, Williams JBW, Löwe B. A brief measure for assessing generalized anxiety disorder: the GAD-7. Arch Intern Med. 2006;166(10):1092-1097."
         note ">=10 gives sensitivity 0.89 and specificity 0.82 for GAD. This subject scores 13."
         url  "https://jamanetwork.com/journals/jamainternalmedicine/fullarticle/410326"
         oa   0
         pdf  ""}
        {key SCC2015
         cite "Gifford KA, Liu D, Romano R, et al. Development of a subjective cognitive decline questionnaire using item response theory. Alzheimers Dement (Amst). 2015;1(4):429-439."
         note "Part of the large literature showing subjective cognitive complaint tracks affect more closely than it tracks performance -- the central dissociation in this record."
         url  "https://pmc.ncbi.nlm.nih.gov/articles/PMC4671489/"
         oa   1
         pdf  "PMC4671489, free full text"}
        {key ERP_MDD2025
         cite "Event-related potentials and executive control deficits in major depression: evidence from the Attention Network Test. Front Syst Neurosci. 2025."
         note "The current form of the same question: how much of an apparent executive deficit in a depressed subject is executive."
         url  "https://www.frontiersin.org/journals/systems-neuroscience/articles/10.3389/fnsys.2025.1674124/full"
         oa   1
         pdf  "Frontiers, open access"}
    }
    verdict "The best-validated instruments in the battery, and the ones this report treats most casually -- PHQ-9 12, GAD-7 13 and PCL-C 49 appear as a table on page 1 of 3 of the Firefly report and are never reconciled with the electrophysiology they most plausibly explain."
}

# ---------------------------------------------------------------------------
dict set SOURCES photic {
    test    "Photic stimulation and the visual pathway (checkerboard reversal)"
    origin {
        {key ADRIAN1934B
         cite "Adrian ED, Matthews BHC. The interpretation of potential waves in the cortex. J Physiol. 1934;81(4):440-471."
         note "Flicker-driven cortical responses -- the first demonstration that a rhythm imposed on the eye appears in the EEG. The ancestor of every photic-driving protocol."
         url  "https://pmc.ncbi.nlm.nih.gov/articles/PMC1394159/"
         oa   1
         pdf  "PMC1394159, free full text"}
        {key REGAN1966
         cite "Regan D. Some characteristics of average steady-state and transient responses evoked by modulated light. Electroencephalogr Clin Neurophysiol. 1966;20(3):238-248."
         note "The steady-state/transient distinction, and the reason stimulus temporal frequency is a parameter and not a detail."
         url  "https://doi.org/10.1016/0013-4694(66)90088-5"
         oa   0
         pdf  ""}
        {key CAMPBELL1965
         cite "Campbell FW, Green DG. Optical and retinal factors affecting visual resolution. J Physiol. 1965;181(3):576-593."
         note "Why check size and contrast determine what a checkerboard actually stimulates. A pattern-reversal latency quoted without check size, luminance and contrast is an incomplete measurement."
         url  "https://pmc.ncbi.nlm.nih.gov/articles/PMC1357668/"
         oa   1
         pdf  "PMC1357668, free full text"}
        {key PROVENCIO2000
         cite "Provencio I, Rodriguez IR, Jiang G, Hayes WP, Moreira EF, Rollag MD. A novel human opsin in the inner retina. J Neurosci. 2000;20(2):600-605."
         note "Melanopsin, cloned at the very end of the century. Its cells were not shown to be photoreceptors until Berson 2002, which is why this entry sits at the boundary of the period."
         url  "https://www.jneurosci.org/content/20/2/600"
         oa   1
         pdf  "J Neurosci, free"}
    }
    modern {
        {key BERSON2002
         cite "Berson DM, Dunn FA, Takao M. Phototransduction by retinal ganglion cells that set the circadian clock. Science. 2002;295(5557):1070-1073."
         note "ipRGCs. A third class of photoreceptor, peak sensitivity near 480 nm, projecting to the SCN and to arousal circuitry rather than to image formation."
         url  "https://www.science.org/doi/10.1126/science.1067262"
         oa   0
         pdf  ""}
        {key IPRGC2025
         cite "Intrinsically photosensitive retinal ganglion cells and visual processing: ipRGCs beyond non-image-forming functions. Front Neurosci. 2025;19:1635101."
         note "The current position: ipRGCs modulate alertness, sleep/wake, learning and visual perception itself, not only circadian phase. The reason a vision scientist wants to know the light history of a room before reading a 288 ms N100 out of it."
         url  "https://www.frontiersin.org/journals/neuroscience/articles/10.3389/fnins.2025.1635101/full"
         oa   1
         pdf  "Frontiers, open access"}
        {key MELCONTRAST2023
         cite "Enhanced human contrast sensitivity with increased stimulation of melanopsin in intrinsically photosensitive retinal ganglion cells. 2023."
         note "Melanopsin stimulation changes measured contrast sensitivity in humans. If melanopsin state modulates contrast processing, it is not neutral with respect to a contrast-defined evoked potential."
         url  "https://pubmed.ncbi.nlm.nih.gov/37331304/"
         oa   0
         pdf  ""}
    }
    verdict "The line of work that this battery leans on hardest without acknowledging it. A checkerboard-reversal N100 is a measurement of a stimulus as much as of a subject, and the report specifies neither check size, nor luminance, nor contrast, nor the light the subject had been sitting in."
}
