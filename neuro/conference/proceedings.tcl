# proceedings.tcl — the simulated working conference.
#
# ===========================================================================
# THIS IS A SIMULATION. IT IS NOT A MEDICAL CONSULTATION.
# ===========================================================================
# The five participants are invented composite characters. They are not real
# people, they are not modelled on real people, and their institutional
# affiliations are fictional. No real clinician has reviewed this record. The
# arguments they make are drawn from the published literature catalogued in
# sources.tcl, and where they reach a conclusion it is the conclusion that
# literature supports -- but it is a conclusion reached by a piece of software
# putting words in imaginary mouths, and it carries exactly that much weight.
#
# The device is used because a battery like this one produces claims that
# nobody in the actual chain of custody is positioned to argue with. The
# vendor's software cannot be cross-examined. Writing down what five differently
# trained readers would push on is a way of making the disagreements visible
# that a single signed report hides.
#
# Inline link syntax:  [[L-001|the highlighted phrase]]
# which the renderer turns into a yellow highlight, a gutter stub, and a ley
# line to the region named in LINKS.
# ===========================================================================

# ---------------------------------------------------------------------------
# Participants
# ---------------------------------------------------------------------------
set PEOPLE {}
dict set PEOPLE AR {
    name    "Dr. Alma Reyes-Okonkwo, MD"
    role    "Internal medicine"
    where   "912 Columbus Clinic, New York"
    colour  "#B4531E"
    initials "AR"
    bio     "Sees the patient every eight months for twelve minutes. Ordered none of this and has to explain all of it. Wants to know what changes on Monday."
}
dict set PEOPLE NF {
    name    "Dr. Nathan Feldstein, MD PhD"
    role    "Clinical neurophysiology; chair"
    where   "Columbia Neurology, New York"
    colour  "#2F5FA8"
    initials "NF"
    bio     "Runs an epilepsy monitoring unit and reads EEG for a living. Instinctively asks whether a recording would survive a departmental conference, not whether it produced a number."
}
dict set PEOPLE IV {
    name    "Dr. Ingrid Vásárhelyi, MD"
    role    "Consultant clinical neurophysiologist"
    where   "Sankt Alban University Hospital, Basel"
    colour  "#3C7A5A"
    initials "IV"
    bio     "Chairs a national standards committee. Reads every commercial report as a regulatory document first and a clinical one second. Blunt about it."
}
dict set PEOPLE KM {
    name    "Dr. Kenji Morisawa, MD PhD"
    role    "Neurology and evoked potentials"
    where   "Kitasawa University Hospital, Tokyo"
    colour  "#6B4E9E"
    initials "KM"
    bio     "Thirty years of ERP work in a department where the averaging is still checked by hand. Speaks rarely and almost always about measurement rather than interpretation."
}
dict set PEOPLE PR {
    name    "Dr. Priya Raghunathan, PhD"
    role    "Visual neuroscience; photic sensing and nerve signalling"
    where   "Coastal Institute for Visual Neuroscience, La Jolla"
    colour  "#A8306B"
    initials "PR"
    bio     "Works on retinal ganglion cell phototransduction. The only participant who is not a physician and the only one who asks what the stimulus was."
}

# ---------------------------------------------------------------------------
# Annotation targets in the back-matter report pages.
# box is {x y w h} in fractions of the figure image.
# ---------------------------------------------------------------------------
set REGIONS {}
proc region {id fig box label} {
    global REGIONS
    dict set REGIONS $id [dict create fig $fig box $box label $label]
}

region R-01 EyesOpen_EEG-RawTrace       {0.000 0.213 0.175 0.062} \
    "FZ (rejected) -- the midline frontal electrode, one of four dropped channels"
region R-02 EyesOpen_EEG-HeadMaps       {0.000 0.000 1.000 0.072} \
    "Theta : Beta Ratio  2.190  against a reference of < 2.1"
region R-03 EyesClosed_EEG-HeadMaps     {0.000 0.000 1.000 0.072} \
    "Peak Alpha Frequency (PAF)  11.10 Hz  against 8.9 - 11 Hz"
region R-04 EyesClosed_EEG-HeadMaps     {0.235 0.330 0.185 0.115} \
    "the 12 Hz eyes-closed map -- the largest single deviation printed anywhere in the record"
region R-05 GoNoGo_ERP-P300a-Cz         {0.395 0.040 0.235 0.560} \
    "P300a at Cz: 17.26 uV, peaking at 468 ms"
region R-06 GoNoGo_ERP-P300b-Pz         {0.395 0.040 0.235 0.620} \
    "P300b at Pz: 6.6 uV, peaking at 380 ms -- 38.2% of the P3a"
region R-07 GoNoGo_ERP-N100-O2          {0.300 0.280 0.205 0.620} \
    "N100 at O2: trough at 288 ms against a < 250 ms ceiling"
region R-08 Resting_HRV-PowerSpectrum   {0.115 0.030 0.200 0.880} \
    "VLF 1115 ms^2 -- the tallest bar, computed from a two-minute epoch"
region R-09 Resting_HRV-PowerSpectrum   {0.660 0.430 0.200 0.480} \
    "HF 258 ms^2 -- 11.1% of total power, the vagal brake"
region R-10 Resting_ECG-12Lead          {0.300 0.020 0.290 0.955} \
    "the V1-V3 column: concave ST elevation with a J-point notch"
region R-11 Resting_ECG-12Lead          {0.560 0.930 0.440 0.070} \
    "the footer: a Print Date, and no Reviewed By"
region R-12 Percutaneous_SPT-40Panel    {0.000 0.430 0.500 0.310} \
    "Tray B trees: black walnut 15, shagbark hickory 15, eastern oak 15 mm"
region R-13 Percutaneous_SPT-40Panel    {0.500 0.560 0.500 0.085} \
    "B28 / B29, the two dust-mite rows -- the only low-confidence transcription on the sheet"
region R-14 SelfReport_Screener-Domains {0.110 0.155 0.320 0.115} \
    "Executive & Attention: 8 out of 100"
region R-15 GoNoGo_Result-Gauges        {0.000 0.845 1.000 0.150} \
    "P300b amplitude -- the only Poor in the brain-biomarker block"
region R-16 Resting_HRV-Tachogram       {0.000 0.000 1.000 1.000} \
    "the 60 seconds of RR intervals the whole spectrum was computed from"
region R-17 Resting_ECG-Waveform        {0.000 0.000 1.000 1.000} \
    "5 s of single-lead ECG, sinus rhythm at 56 bpm"

# ---------------------------------------------------------------------------
# Links: transcript anchor -> report region
# ---------------------------------------------------------------------------
set LINKS {}
proc link {id region} { global LINKS ; dict set LINKS $id $region }

link L-001 R-01 ; link L-002 R-01 ; link L-003 R-02 ; link L-004 R-03
link L-005 R-03 ; link L-006 R-02 ; link L-007 R-04 ; link L-008 R-02
link L-009 R-05 ; link L-010 R-06 ; link L-011 R-06 ; link L-012 R-15
link L-013 R-07 ; link L-014 R-07 ; link L-015 R-07 ; link L-016 R-05
link L-017 R-08 ; link L-018 R-16 ; link L-019 R-09 ; link L-020 R-08
link L-021 R-12 ; link L-022 R-13 ; link L-023 R-10 ; link L-024 R-11
link L-025 R-14 ; link L-026 R-14 ; link L-027 R-15 ; link L-028 R-06
link L-029 R-17 ; link L-030 R-09 ; link L-031 R-04 ; link L-032 R-12
link L-033 R-11 ; link L-034 R-14 ; link L-035 R-07 ; link L-036 R-03

# ---------------------------------------------------------------------------
# The week
# ---------------------------------------------------------------------------
set DAYS {}
proc day {n title subtitle turns} {
    global DAYS
    lappend DAYS [dict create n $n title $title subtitle $subtitle turns $turns]
}

# ===========================================================================
day 1 "Provenance" "What each of these machines is, and where it came from" {
 {NF "I want to spend the first day on instruments rather than results, because four of us are going to spend the rest of the week arguing about numbers and I would like us to agree first on what produced them. Five documents, one afternoon, five different measurement traditions, the oldest of which is a hundred and fifty years old."}

 {IV "Then let us start with the oldest and work forward, because the age is not a curiosity. Blackley scratched pollen into his own forearm in 1865 and published in 1873. Lewis described the triple response in 1927. That is the entire theoretical content of the skin sheet in this folder: a wheal, measured in millimetres, fifteen minutes after a lancet. It has barely changed because it has barely needed to."}

 {AR "And it is the only test in the folder I would have ordered."}

 {NF "Say more."}

 {AR "The patient came in saying they cannot concentrate. Somebody sent them for a brainwave battery. I would have asked what they were taking, whether they were sleeping, and whether their nose had been blocked since April. The skin test answers the third question with real evidence. The rest of this folder answers a question nobody asked."}

 {KM "The EEG is also old and also sound. Berger, 1929, Archiv für Psychiatrie, volume 87. He had the recording in 1924 and did not publish for five years because he could not believe it was cerebral rather than an artefact of his equipment. Adrian and Matthews replicated it in Brain in 1934 and showed alpha blocking on eye opening -- which is the same eyes-open, eyes-closed contrast printed on page six of this report."}

 {PR "It is worth saying out loud that Adrian did the photic driving work in the same year, in the Journal of Physiology. Flicker imposed on the eye appearing in the cortical record. That is the ancestor of the checkerboard on page five, and I will have a great deal to say about it on Wednesday."}

 {NF "Noted, and dreaded."}

 {IV "The instrument is old and sound. The layer on top of it is neither. Everything that turns this recording into a report -- the z-scores, the head maps, the thresholds -- descends from Neurometrics, John and colleagues in Science in 1977. Score a patient against an age-matched reference population. That idea is fifty years old and it is where every argument this week is going to live."}

 {KM "Because the reference population is not in the folder."}

 {IV "Because the reference population is never in the folder."}

 {NF "Before we get there. The data quality floor, which I want on the record on day one so that nothing said later floats free of it. [[L-001|Nineteen electrodes, four rejected]]. FZ, T8, P3, P8. Fifteen usable against an eighteen-channel minimum for the vendor's own source localisation, which was therefore not performed, on either condition."}

 {IV "Which the report states plainly, to its credit, twice."}

 {NF "It does. And then it spends eleven further pages making regional claims. Anterior cingulate. Frontal lobe dysfunction. Vertex. Those are statements about where, and there is no inverse solution in this record to support a statement about where."}

 {KM "[[L-002|The rejected set includes FZ]]. That is the one that matters. Not because four channels is a lot, but because that particular channel is the midline frontal electrode, and the anterior-cingulate story the report tells about attention rests on exactly that region. It is the electrode you would least like to lose for the claim being made."}

 {AR "Is that bad luck or is that something about the recording?"}

 {KM "It is usually a bad connection under the cap. Occasionally it is a subject who cannot stop frowning. Neither is in the record."}

 {PR "Nor is the room. I have read this folder four times and I cannot tell you what the ambient illuminance was, what the subject had been looking at for the previous hour, or what time of day relative to their own sleep. Given that one of the two conditions is defined by whether the eyes are open, that is not a small omission."}

 {NF "Einthoven, briefly, so it is on the record: string galvanometer, preliminary 1901, full description with tracings in Pflügers Archiv in 1903, Nobel in 1924. The letters P, Q, R, S and T on page four are his. Bazett gave us QTc in Heart in 1920, and the 393 milliseconds on this twelve-lead is his formula, which everyone knows over-corrects at fast rates and under-corrects at slow ones -- and this tracing was recorded at fifty-seven."}

 {AR "Which is the sort of thing that never makes it into the printout."}

 {IV "And Akselrod, Science, 1981, for the frequency decomposition on page four. Sympathetic and parasympathetic contributions at specific frequencies. What is generally forgotten is the other half of that paper: the peak near 0.04 hertz -- the VLF band -- is strongly modulated by renin-angiotensin activity. It was never a clean sympathetic index. It was reported as a mixed one in the paper that invented it."}

 {NF "That is Thursday. Tomorrow, the EEG claims."}
}

# ===========================================================================
day 2 "The ratio" "Theta over beta, and what a threshold is for" {
 {NF "Two flags on the EEG. [[L-003|Theta to beta ratio, 2.190, against a reference of less than 2.1]]. And [[L-004|peak alpha frequency, 11.10 hertz, against 8.9 to 11]]. Both flagged high. Dr. Vásárhelyi, you asked to open."}

 {IV "I asked to open because I want to be finished with the theta-beta ratio by lunch and I think that is achievable. The number is 2.190. The threshold is 2.1. That is four per cent. The report itself, on the same page, states that Monastra's normative tables are not available for this age group -- the subject is thirty-one years and two months, the tables stop at thirty-one. So we have a four per cent exceedance of a threshold the report concedes does not apply to this patient."}

 {AR "Then why is it printed in a box?"}

 {IV "Because the software prints what it computes."}

 {KM "There is a worse problem, and it is arithmetic rather than normative. A ratio has a denominator. [[L-006|An elevated theta-beta ratio can mean elevated theta, or it can mean depressed beta]], and the two have opposite clinical readings. The report acknowledges this in prose on the Firefly page -- it says explicitly that an elevated value may be a false positive when beta power is low and theta is normal."}

 {NF "And in this subject?"}

 {KM "Central beta1 z is plus 1.92. Beta is high, not low. So the denominator artefact is not what is happening here."}

 {IV "Which is worse, not better."}

 {KM "Which is worse. If theta were elevated we would have a slowing story. If beta were depressed we would have an artefact story. What we have is theta at z equals 0.29 -- unremarkable -- and beta elevated, and a ratio nonetheless over the line. That is a ratio that has stopped describing anything."}

 {PR "May I ask something naive."}

 {NF "Please."}

 {PR "What is the boundary between theta and beta in this report?"}

 {IV "Which report?"}

 {PR "That is my question. The Evoke head maps band theta as four to seven and beta1 as thirteen to eighteen. The Firefly page bands theta as three and a half to seven and a half and beta1 as twelve point five to twenty-five. Those are different quantities with the same names, printed nine pages apart, and the ratio is quoted once without saying which."}

 {KM "That is not naive. That is the finding."}

 {IV "There is a 2019 paper in Applied Psychophysiology and Biofeedback which did exactly this: same recordings, several commercial packages, different theta-beta ratios out the other end. It is not a scandal, it is a definition problem. But it means a quotient printed to three decimal places against a threshold quoted to two is theatre."}

 {NF "I want to bring in the January paper, because it changes the register of this conversation. The multiverse analysis, out in eLife this year. Five hundred and seventy-six defensible analysis pipelines, run across the Healthy Brain Network sample -- about fifteen hundred children -- and an independent validation set of three hundred and eighty-one."}

 {IV "And the conclusion."}

 {NF "That individual alpha peak frequency and aperiodic activity shape theta-beta ratio estimates, and that the apparent ADHD-control difference is substantially driven by the aperiodic component -- the one-over-f background -- rather than by oscillatory theta or beta at all."}

 {KM "Then say the rest of it."}

 {NF "The rest of it is that this subject's [[L-005|peak alpha frequency is 11.10 hertz]], at the very top of the normative band. And a high alpha peak pushes the alpha shoulder up into the region where a fixed thirteen-hertz beta boundary sits."}

 {IV "So the confound the January paper identifies is not hypothetical in this record. It is present, it is measured, and it is printed two boxes to the right of the ratio it invalidates."}

 {AR "Let me make sure I have this. The one number in this folder that the referring question was actually about -- the ADHD number -- is four per cent over a line, from tables that do not cover this patient's age, computed from bands that are defined two different ways in the same folder, and the specific thing that this year's largest reanalysis says corrupts it is also measured in this patient and is also flagged."}

 {IV "Yes."}

 {AR "And the vendor's own conclusion was that the ADHD screen is negative."}

 {NF "At ninety per cent stated confidence, yes."}

 {AR "Then the software reached the right answer and printed a red box anyway."}

 {PR "Which is the thing I would want a patient never to see without this conversation attached to it."}

 {KM "I would like to speak for the other flag before we close. Eleven point one hertz. The threshold is eleven. That is nine hundredths of a hertz. If the spectrum is estimated in one-hertz bins -- and the head maps in this report are printed in one-hertz bins, two through thirty -- then the reported precision of the peak exceeds the resolution of the display it is printed next to."}

 {IV "It will have been interpolated."}

 {KM "Certainly. And an interpolated peak on a two-minute eyes-closed record has a standard error that nobody has printed. Eleven point one against eleven is not a finding. It is a rounding."}

 {PR "There is a reading of the high alpha peak that is not a rounding, though, and I would like it on the record for Wednesday. A high individual alpha frequency is associated in the literature both with good semantic memory and with central over-arousal, insomnia and hypervigilance. The report says this. It is one of the few places where it hedges honestly."}

 {NF "And which is it here?"}

 {PR "Ask me after we have talked about the heart. Nothing in the EEG alone will tell you."}

 {KM "[[L-007|One map on this page is not a rounding]]. Twelve hertz, eyes closed, central. Alpha2 z of plus 2.18. It is the only band in the record past two standard deviations and it is the darkest field on either sheet. If we are going to spend a day on a four per cent ratio exceedance we should spend ten minutes on the finding that is actually there."}

 {IV "[[L-008|Agreed, and note what it does to the ratio]]. Elevated alpha2 sits at ten to twelve and a half hertz on the Firefly banding. That is immediately below the beta boundary. It is the same confound the multiverse paper describes, showing up as a positive z-score in the same subject."}

 {NF "Tomorrow, evoked potentials. Dr. Raghunathan has been extremely patient."}
}

# ===========================================================================
day 3 "The stimulus" "Evoked potentials, and what a checkerboard is" {
 {PR "I want to start somewhere unhelpful. I have read every page of this folder and I cannot tell you what the subject was looking at."}

 {NF "A checkerboard."}

 {PR "That is not a stimulus specification. What check size? What mean luminance? What contrast? What reversal rate? What field size, what fixation distance, what refresh? Halliday's 1972 Lancet paper made pattern-reversal a clinical test precisely because it is a stable measurement -- normal major positivity near a hundred and twenty milliseconds, delayed to a mean of a hundred and fifty-five in optic neuritis. It is stable because those parameters are controlled. Vary check size alone and you move the latency by tens of milliseconds in a normal eye."}

 {KM "In our department the stimulus parameters are printed on the report."}

 {IV "In mine they are required to be. It is in the IFCN guidance."}

 {PR "So when this report tells me [[L-013|the N100 is at 288 milliseconds against a ceiling of 250]] -- a thirty-eight millisecond delay, the largest single deviation in the entire evoked-potential set -- I cannot tell whether I am looking at a nervous system or at a smaller check on a dimmer monitor."}

 {AR "Is that a real possibility or is that an academic point?"}

 {PR "It is a real possibility. And there is a second one that I think matters more, and it is the reason I accepted this invitation. Campbell and Green, Journal of Physiology, 1965: optical and retinal factors set the resolution limit. A checkerboard reversal is a contrast stimulus. And since 2002 we have known that the retina contains a third photoreceptor class -- Berson's intrinsically photosensitive ganglion cells, expressing the melanopsin that Provencio cloned in 2000, peak sensitivity near four hundred and eighty nanometres."}

 {NF "Which drive circadian entrainment."}

 {PR "Which drive circadian entrainment, and pupil, and alertness, and -- this is the recent part -- image-forming vision itself. There is 2023 work showing that increasing melanopsin stimulation measurably enhances human contrast sensitivity. And a Frontiers review this year arguing the ipRGC contribution to visual processing goes well beyond the non-image-forming functions we assigned them twenty years ago."}

 {KM "So the melanopic content of the display alters the contrast the cortex receives."}

 {PR "And this subject's pupil size, which nobody recorded, sets how much of it gets in. A late N100 in an over-aroused subject in an unspecified light environment on an unspecified display is four unknowns and one number."}

 {IV "Then it should not be flagged."}

 {PR "It should be flagged and it should be repeated. I am not saying the finding is false. I am saying it is the single cheapest thing in this folder to nail down and nobody nailed it down."}

 {NF "Let us move to the part I think is the actual finding. Squires, Squires and Hillyard, 1975. Two varieties of long-latency positive wave. P3a at around two hundred and forty milliseconds, frontocentral, present whether or not the subject attends. P3b at around three hundred and fifty, parietal, present only under active attention. Polich's 2007 synthesis: P3a is stimulus-driven orienting, P3b is context updating and memory consolidation."}

 {KM "And in this record."}

 {NF "[[L-009|P3a at Cz: 17.26 microvolts]]. The floor is six. It is nearly three times the floor."}

 {AR "That is good, yes? That is a brain that notices things."}

 {NF "That is a very healthy orienting response. [[L-010|P3b at Pz: 6.6 microvolts]]. The floor is also six."}

 {IV "So it passes."}

 {NF "It passes the first criterion. The report states a second criterion, in prose, on the ERP page: the P300b must also exceed fifty per cent of the P300a power."}

 {KM "Six point six over seventeen point two six."}

 {NF "[[L-011|Thirty-eight point two per cent]]."}

 {KM "..."}

 {IV "Say it."}

 {KM "It fails. The report states the criterion and does not evaluate it. I have looked. In seventeen pages across three documents, that quotient is not printed anywhere."}

 {AR "Then what does it mean? In words I can say to a patient."}

 {KM "P3a is the orienting response. Something changed, look at it. P3b is what happens after: the categorisation, the update to the working model, the commitment of the event to memory. This subject's orienting is loud and their updating is quiet. The system is very good at being interrupted and comparatively poor at consolidating what interrupted it."}

 {AR "That is the complaint. That is what the patient said. Not 'I cannot pay attention' -- 'I get pulled at things and then I have lost the thread.'"}

 {PR "And it is not what got flagged."}

 {NF "It is not. [[L-012|The report does mark the P300b amplitude as Poor on the summary gauge]], for reasons I cannot reconstruct, since 6.6 exceeds the stated floor of 6. [[L-027|The gauge and the table disagree with each other]] and the ratio that would reconcile them is absent."}

 {IV "That is a software defect, not a clinical finding."}

 {NF "It may be a software defect that accidentally reached the right answer."}

 {KM "There is a caution I want attached to this, because I think we are about to over-invest in it. P3b amplitude is reduced in depression. That is well established -- there is a 2015 Scientific Reports source-analysis paper showing depression loading on P3b and specifically not on P3a, and a 2021 prospective study where a reduced P300 predicted subsequent depressive severity. This subject has a PHQ-9 of twelve."}

 {NF "So the ratio may be a mood finding."}

 {KM "The ratio may be a mood finding wearing an attention finding's clothes. Which -- and I want to be precise -- would still make it the most informative measurement in this folder. It would just point at a different clinic."}

 {PR "[[L-014|And the N100 delay is upstream of both of them]]. If the first cortical response is late by thirty-eight milliseconds, then every latency downstream inherits some of that. The P3a at four hundred and sixty-eight is eighteen milliseconds over its own ceiling. Take thirty-eight off the front and it is comfortably inside."}

 {KM "That is not how latency propagation works in general, but as a first approximation it is worth the sentence."}

 {PR "It is worth the sentence because it changes what you would test. [[L-015|If the delay enters at the retina or the optic nerve, it is one problem]]. If it enters at the cortex, it is another. And you distinguish them with an electroretinogram and a properly specified pattern VEP, both of which are routine, neither of which was done."}

 {AR "How much do those cost?"}

 {PR "Less than this folder did."}

 {NF "[[L-016|One last thing on the P3a before we close]]. Seventeen microvolts with a commission error rate of two point four five per cent. Whatever is wrong with this patient, it is not inhibitory control. I would like that sentence to survive to Friday."}
}

# ===========================================================================
day 4 "The body" "Autonomic, cardiac, immune, and the empty medication field" {
 {AR "I have been waiting all week for today, so I am going to be rude and go first. There is a field on the front page of this report that says Medications. It says UNKNOWN."}

 {IV "Yes."}

 {AR "On the eighteenth of August. In New York. On the same afternoon that this patient had [[L-021|twenty-six of fifty-eight allergens come back positive]], with black walnut, shagbark hickory, eastern oak and Timothy grass all at fifteen millimetres. Ragweed season. Mugwort at nine millimetres. This is a person who was, with very high probability, symptomatic and medicated on the day their reaction time was measured."}

 {NF "And the reaction time was five hundred and eighty-eight milliseconds."}

 {AR "Against a ceiling of five hundred. Eighty-eight milliseconds slow. There is a 2025 paper out of primary care linking antihistamine blood-brain-barrier penetration and central H1 binding to daytime sleepiness, cognitive failures and functional impairment. There is a 2025 meta-analysis showing allergic rhinitis alone perturbs brainstem evoked-response latencies -- in a modality nobody was even looking at."}

 {PR "That last one is the citation I wanted yesterday. If untreated rhinitis shifts auditory brainstem latencies, the prior that it does nothing to a visual N100 is not a strong prior."}

 {AR "So the two headline abnormalities in this entire battery -- slow reaction time and a late first visual response -- are both textbook effects of a drug class this patient was probably taking, on a day chosen to prove they are allergic to the outdoors, and nobody wrote down whether they had taken one."}

 {IV "In my hospital that report would be returned unsigned."}

 {NF "In mine it would be signed and the field would still be empty."}

 {KM "May I move to the heart, because I think there is a similar problem there and it is quieter."}

 {NF "Please."}

 {KM "SDNN eighty-two milliseconds, inside range. Total power two thousand three hundred and twenty-four, inside range. The report scores arousal regulation as normal, and on those two numbers it is right. Then it flags neuroinflammation on the basis of a VLF value of one point one seven against a threshold of nought point five, and does not say anywhere what that value is."}

 {IV "It is VLF over LF. Eleven fifteen over nine fifty-one."}

 {KM "It is. I checked it too. But we had to check it. And here is my difficulty. [[L-017|The VLF band was computed from a two-minute recording]]."}

 {AR "[[L-029|The strip they printed is five seconds long]]. Sinus, regular, unremarkable. I am not disputing the rhythm. I am disputing that you can get a frequency decomposition with a band centred at four hundredths of a hertz out of the two minutes that strip came from."}

 {IV "The Task Force standard is explicit. 1996, Circulation. VLF from short-term recordings is of dubious validity and should be avoided."}

 {KM "Thirty years ago, and it has not been overturned. [[L-018|Two minutes contains perhaps seven cycles at 0.04 hertz]]. You cannot resolve a spectral band from seven cycles in the presence of a slow trend, and a resting recording is nothing but slow trend."}

 {AR "Then is the inflammation flag wrong?"}

 {KM "The flag is not supportable from the number it cites. Whether the underlying claim is wrong is a separate question."}

 {IV "And I think the underlying claim survives, for a reason nobody in the report gives. There are two other numbers, both independent of the VLF estimate. LF over HF is three point six nine. And [[L-019|the high-frequency band is eleven point one per cent of total power]]."}

 {NF "Against a nominal floor of fifteen."}

 {IV "High frequency is respiratory sinus arrhythmia. It is the cleanest non-invasive vagal index we have, it sits in a frequency range that two minutes can actually resolve, and it is low. That is the finding. [[L-030|The VLF ratio is a poor proxy for a thing measured better one bar to the right on the same chart]]."}

 {KM "I accept that."}

 {PR "There is a 2026 paper -- I looked it up after Tuesday -- relating VLF to interleukin-6 in healthy young adults. Substantial positive associations. It is the closest thing in the current literature to a mechanism for the vendor's inflammation flag."}

 {IV "And the recording length in that study?"}

 {PR "Twenty-four hour and night-time."}

 {IV "Thank you."}

 {PR "I raise it because it cuts both ways. The mechanism is real. The measurement here cannot support it. Those are different sentences and the report merges them."}

 {AR "[[L-020|Which is my complaint about this whole folder in one bar of one chart]]. The direction is probably right. The number quoted for it is not defensible. And the patient gets the number."}

 {NF "The twelve-lead. Briefly, because I do not think it is interesting and I want to be sure we agree it is not interesting."}

 {AR "Sinus bradycardia at fifty-seven in a thirty-one-year-old. PR one thirty-six, QRS eighty-eight, QTc three ninety-three. [[L-023|Anterolateral ST elevation, read by the machine as a repolarisation variant]]. Wasserburger and Alt described it in the American Journal of Cardiology in 1961 -- concave elevation with a J-point notch, common in young men, benign in the form described."}

 {IV "The machine reading is PROBABLY NORMAL."}

 {AR "And I agree with the machine. [[L-024|What I do not agree with is the comment field, which reads Unconfirmed Report]]. There is a Print Date. There is no Reviewed By and no Review Date. Somebody needs to sign it. That is not cardiology, it is administration, and it is the single easiest item on the entire list to close."}

 {NF "Anyone disagree that the twelve-lead is benign?"}

 {IV "No. I would like the signature."}

 {KM "No. I would like the signature."}

 {PR "I am not qualified and I would like the signature."}

 {AR "One more thing on the skin sheet before we close, because I noticed something in the transcription notes. [[L-022|The two dust-mite rows are marked low confidence]] -- pteronyssinus at zero and farinae at eleven. Those are usually concordant. A zero-eleven split is unusual."}

 {IV "Does it change anything?"}

 {AR "Not the burden figure, no -- one of the two is positive either way. It changes whether I tell this patient to buy mattress covers. Which is a real decision that gets made on a real Tuesday, and I would like the sheet re-read before I make it."}
}

# ===========================================================================
day 5 "The gap" "Synthesis, dissent, and what to do on Monday" {
 {NF "I want to close on the largest single number in the folder, which we have circled all week and not landed on. [[L-025|Self-reported executive and attention function: eight out of a hundred]]."}

 {AR "[[L-026|Eight]]."}

 {NF "Against a reference of sixty-one or above. That is eighty-six per cent below threshold. It is the third-largest deviation in the entire record after the allergen burden and the questionnaires."}

 {IV "And the objective measures."}

 {NF "Commission errors two point four five per cent, inside range. Omission errors eight point five seven per cent, inside range. P3a amplitude nearly three times its floor."}

 {KM "So the subjective and the objective are not merely different. They are opposite."}

 {PR "How big is that gap, quantitatively? Somebody has computed this."}

 {NF "Roughly three units on a common half-band axis, in the same direction, across all three attention constructs. It is the largest structured disagreement in the record and no document in the folder prints it."}

 {AR "I want to be careful here, because there is a version of this conversation that ends with somebody telling a patient that their problem is imaginary, and I have seen that conversation and it does harm."}

 {IV "That is not what the data says."}

 {AR "I know it is not. I am saying it is what the data will be heard as."}

 {KM "Then let us be precise about what it does say. It says the distress is real and the deficit it names is not the one the instruments find. Those are compatible. The literature on subjective cognitive complaint is very clear that it tracks affect more closely than it tracks performance. This subject has a PHQ-9 of twelve, a GAD-7 of thirteen, a PCL-C of forty-nine."}

 {PR "Forty-nine against a conventional cut of fifty."}

 {KM "One point below a cut-off is not evidence of absence. The normal ceiling on that instrument is twenty-nine. Forty-nine is sixty-seven per cent above the normal ceiling. The cut-off is a decision rule for a different purpose."}

 {NF "Weathers, 1993. And note the provenance -- it is a conference presentation at the International Society for Traumatic Stress Studies, not a journal article. That is unusual for an instrument this widely used, and it is part of why the cut-off has drifted between thirty and fifty depending on population."}

 {IV "Then may I state the finding as I would write it. This is a strongly atopic thirty-one-year-old with moderate depression, moderate anxiety and substantial post-traumatic symptomatology, tested in pollen season on unrecorded medication, whose electrophysiology shows preserved capacity with degraded timing, and no support for the diagnosis the battery was ordered to find."}

 {AR "I would sign that."}

 {KM "I would sign it with one addition. [[L-028|The P3b to P3a ratio of 0.382]] is the only measurement in the folder that independently describes the presenting complaint, and it appears in no document. If we recommend one thing, it should be that this number be computed and tracked."}

 {NF "Seconded. Dr. Raghunathan, you asked to file a dissent."}

 {PR "Not a dissent from the conclusion. A dissent from the confidence."}

 {NF "Go on."}

 {PR "Four of the five of us are clinicians and you have spent the week arguing about what these numbers mean. I have spent it asking what produced them, and I have not received an answer to a single one of my questions. I do not know the check size. I do not know the luminance. I do not know the contrast. I do not know the light the subject sat in beforehand, or their pupil size, or the time of day relative to their own circadian phase. [[L-035|And the measurement I am most suspicious of is the one you have all treated as most solid]] -- the thirty-eight millisecond N100 delay -- because it is the one most sensitive to every parameter I just listed."}

 {IV "That is fair."}

 {PR "[[L-036|And the same objection applies to the alpha peak]]. Eleven point one hertz. Individual alpha frequency moves with arousal, with time of day, with light exposure in the preceding hours, and with whether the subject is actually resting or performing mental arithmetic behind closed eyes. We have treated it as a trait. On a single two-minute epoch it is a state."}

 {KM "I have made that argument for thirty years and I am glad to hear it from a retina."}

 {PR "So my dissent is this: I think the pattern you have described is probably correct and I think this record cannot establish it. The concordance is with the literature, not with the measurement. If the measurement had come out differently the literature would still be there."}

 {NF "That is the sharpest thing anyone has said this week."}

 {IV "It is also an argument for repeating the battery under controlled conditions rather than for discarding it."}

 {PR "Yes. That is exactly what it is an argument for."}

 {AR "Then let me try to write Monday, because that is my job and none of the rest of you have to do it."}

 {NF "Please."}

 {AR "One. Somebody signs the twelve-lead. [[L-033|It is benign and it is unsigned and that takes one phone call]]."}

 {AR "Two. Find out what this patient takes. Not 'do you take anything' -- the bottle, the dose, the last date. If it is a sedating antihistamine we repeat the cognitive block off it and out of season, and I would predict the reaction time and the N100 both move."}

 {AR "Three. The PHQ-9 is twelve and the report recommends a risk assessment and I have not heard anybody in this room mention item nine all week."}

 {NF "..."}

 {AR "Item nine. That is the one that asks about self-harm. It is the only thing in this folder that is time-sensitive and we have spent five days on spectral banding."}

 {IV "That is a fair rebuke."}

 {AR "It is not a rebuke, it is a running order. Four. Treat the mood and the sleep, and re-measure reaction time and reaction-time variability in three months. If the strongest pattern in this record is real, they move. If they do not move, we were wrong and we will know."}

 {AR "Five. [[L-032|The tree pollen and grass results are real and actionable]] regardless of everything else we have argued about. Immunotherapy conversation, allergist, environmental controls. That does not wait for the neurology."}

 {KM "And six, if I may. [[L-031|Recompute the theta-beta ratio with the band edges stated]], recompute it with the aperiodic component removed as the January paper does, and see whether it is still over the line. My expectation is that it is not."}

 {NF "Mine as well. Anything else for the record."}

 {IV "One sentence. Everything we have concluded this week is available from the documents the patient was already given. It required someone to divide one printed number by another printed number, to notice which page a threshold came from, and to read a footer. That is not sophistication. That is attention, and it should not have taken five of us a week."}

 {NF "[[L-034|Then let the record show that the loudest number in the folder was a self-report]], the quietest was a quotient nobody computed, and that the second one is the one we would act on. We are adjourned."}
}
