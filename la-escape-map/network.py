"""Hand-coded California highway graph used as the offline drive-time model.

Coordinates are (lon, lat). Routes reference named junctions in PLACES so that
different highways share nodes exactly where they meet. Raw (lon, lat) tuples
may be mixed in for shaping points that are not junctions.

Speeds are *average moving speeds* in mph, not posted limits:

  freeway_rural  68   interstates and freeway-grade routes outside metro areas
  freeway_urban  50   LA basin / Bay Area / San Diego freeways (light traffic)
  highway        52   2-lane state highways, expressway sections
  mountain       38   passes, canyon roads, Big Sur, Sierra crossings
  city           30   surface streets / off-network access (see build.py)

The straight-line distance between consecutive waypoints is multiplied by a
sinuosity factor per class so sparse waypoints do not under-count road length.
"""

SPEEDS = {
    "freeway_rural": (68, 1.08),
    "freeway_urban": (50, 1.06),
    "highway": (52, 1.15),
    "mountain": (38, 1.30),
}

ORIGIN = "dtla"  # downtown Los Angeles, 1st & Main

PLACES = {
    # --- Los Angeles basin ---------------------------------------------------
    "dtla": (-118.2437, 34.0522),
    "eastla_ic": (-118.2200, 34.0330),     # I-5 / I-10 / US-101 / SR-60
    "i10_i710": (-118.1700, 34.0300),
    "i10_i605": (-118.0300, 34.0700),
    "westcovina": (-117.9300, 34.0700),
    "pomona": (-117.7500, 34.0600),        # I-10 / SR-57 / SR-71
    "ontario": (-117.6000, 34.0700),       # I-10 / I-15
    "fontana": (-117.4400, 34.0700),
    "sanbernardino": (-117.3000, 34.0700), # I-10 / I-215
    "redlands": (-117.1800, 34.0600),
    "beaumont": (-116.9800, 33.9300),      # I-10 / SR-60
    "banning": (-116.8800, 33.9300),
    "whitewater": (-116.6500, 33.9300),    # I-10 / SR-62
    "palmsprings_jn": (-116.5500, 33.8600),
    "indio": (-116.2200, 33.7200),         # I-10 / SR-86
    "chiriaco": (-115.7200, 33.6600),
    "desertcenter": (-115.4000, 33.7100),
    "blythe": (-114.6000, 33.6100),        # I-10 / US-95
    "az_i10": (-114.5250, 33.6150),        # Colorado River, I-10

    "i5_commerce": (-118.1500, 33.9900),
    "norwalk": (-118.0700, 33.9000),       # I-5 / I-605 / I-105
    "buenapark": (-118.0000, 33.8600),     # I-5 / SR-91
    "anaheim": (-117.9100, 33.8300),       # I-5 / SR-57
    "santaana": (-117.8700, 33.7500),      # I-5 / SR-55
    "irvine_i5": (-117.8200, 33.6800),
    "eltoro": (-117.7000, 33.6100),        # I-5 / I-405 merge
    "sjc": (-117.6600, 33.5000),
    "sanclemente": (-117.6100, 33.4300),
    "oceanside": (-117.3800, 33.2000),     # I-5 / SR-76 / SR-78
    "carlsbad": (-117.3300, 33.1500),
    "encinitas": (-117.2900, 33.0400),
    "delmar": (-117.2600, 32.9600),
    "lajolla": (-117.2100, 32.8700),       # I-5 / I-805
    "sandiego": (-117.1600, 32.7200),      # I-5 / I-8 downtown
    "chulavista": (-117.0800, 32.6400),
    "sanysidro": (-117.0300, 32.5250),     # I-5 Mexico border
    "sd_i8_i15": (-117.1100, 32.7700),
    "miramar": (-117.1300, 32.9000),
    "escondido": (-117.0800, 33.1200),     # I-15 / SR-78
    "temecula": (-117.1500, 33.4900),      # I-15 / I-215
    "lakeelsinore": (-117.3300, 33.6700),
    "corona": (-117.5500, 33.8700),        # I-15 / SR-91
    "riverside": (-117.3700, 33.9500),     # SR-91 / SR-60 / I-215
    "perris": (-117.2300, 33.7800),
    "morenovalley": (-117.2000, 33.9300),
    "devore": (-117.4000, 34.2200),        # I-15 / I-215
    "cajon": (-117.4500, 34.3300),         # I-15 / SR-138
    "hesperia": (-117.3300, 34.4300),      # I-15 / US-395
    "victorville": (-117.2900, 34.5300),
    "barstow": (-117.0200, 34.9000),       # I-15 / I-40 / SR-58 / SR-247
    "baker": (-116.0700, 35.2700),         # I-15 / SR-127
    "primm": (-115.3900, 35.6100),         # I-15 Nevada border
    "ludlow": (-116.1600, 34.7200),
    "needles": (-114.6100, 34.8500),       # I-40 / US-95
    "topock": (-114.4900, 34.7000),        # I-40 Arizona border
    "us95_nv": (-114.6600, 35.0600),       # US-95 Nevada border
    "vidal_jn": (-114.5100, 34.1700),      # US-95 / SR-62
    "parker_az": (-114.2900, 34.1500),     # SR-62 Arizona border (Earp/Parker)
    "yuccavalley": (-116.4300, 34.1100),   # SR-62 / SR-247
    "twentynine": (-116.0500, 34.1400),
    "lucernevalley": (-116.9700, 34.4400),

    "i405_i5_sylmar": (-118.4700, 34.3100),
    "sherman_oaks": (-118.4700, 34.1550),  # I-405 / US-101
    "westla": (-118.4400, 34.0300),        # I-405 / I-10
    "lax": (-118.3700, 33.9500),           # I-405 / I-105
    "torrance": (-118.2900, 33.8700),      # I-405 / I-110
    "longbeach": (-118.1900, 33.8100),     # I-405 / I-710
    "sealbeach": (-118.0800, 33.7700),     # I-405 / I-605
    "costamesa": (-117.9000, 33.6800),     # I-405 / SR-55
    "irvine_405": (-117.8300, 33.6600),
    "santamonica": (-118.4900, 34.0200),   # I-10 / SR-1
    "burbank": (-118.3100, 34.1700),       # I-5 / SR-134
    "pasadena": (-118.1500, 34.1500),      # I-210 / SR-134
    "azusa": (-117.9000, 34.1300),
    "sandimas": (-117.8000, 34.1100),      # I-210 / SR-57
    "i210_i15": (-117.5800, 34.1300),
    "sb_210": (-117.3000, 34.1300),        # I-210 / I-215
    "hollywood": (-118.3400, 34.1000),
    "woodlandhills": (-118.6000, 34.1700),
    "thousandoaks": (-118.8500, 34.1800),  # US-101 / SR-23
    "camarillo": (-119.0400, 34.2200),
    "oxnard": (-119.2200, 34.2600),        # US-101 / SR-1
    "ventura": (-119.3000, 34.2800),       # US-101 / SR-126 / SR-33
    "santaclarita": (-118.5300, 34.4000),  # I-5 / SR-14 / SR-126
    "castaic": (-118.6200, 34.4900),
    "quail_lake": (-118.7200, 34.7700),    # I-5 / SR-138
    "gorman": (-118.8500, 34.8000),
    "grapevine": (-118.9300, 34.9300),
    "wheelerridge": (-118.9500, 35.0000),  # I-5 / SR-99
    "palmdale": (-118.1200, 34.5800),      # SR-14 / SR-138
    "lancaster": (-118.1300, 34.6900),
    "mojave": (-118.1700, 35.0500),        # SR-14 / SR-58
    "redrock": (-117.9800, 35.3700),
    "inyokern": (-117.8300, 35.6700),      # SR-14 / US-395 / SR-178
    "ridgecrest": (-117.6700, 35.6200),
    "trona": (-117.3700, 35.7600),
    "adelanto": (-117.4100, 34.5800),
    "kramer_jn": (-117.5500, 34.9900),     # US-395 / SR-58
    "johannesburg": (-117.6300, 35.3700),
    "boron": (-117.6500, 35.0000),
    "tehachapi": (-118.4500, 35.1300),
    "bakersfield": (-119.0200, 35.3700),   # SR-99 / SR-58 / SR-178
    "lakeisabella": (-118.4700, 35.6400),
    "walkerpass": (-118.0300, 35.6600),
    "maricopa": (-119.4000, 35.0600),      # SR-166 / SR-33
    "newcuyama": (-119.6900, 34.9500),
    "buttonwillow": (-119.4000, 35.4000),
    "losthills": (-119.6900, 35.6200),     # I-5 / SR-46
    "kettleman": (-119.9600, 36.0100),     # I-5 / SR-41
    "coalinga_jn": (-120.3600, 36.2500),   # I-5 / SR-198
    "losbanos": (-120.8500, 37.0600),
    "santanella": (-121.0200, 37.0900),    # I-5 / SR-152
    "patterson": (-121.1300, 37.4700),
    "tracy": (-121.4300, 37.7400),         # I-5 / I-205 / I-580
    "stockton": (-121.2900, 37.9600),      # I-5 / SR-99 / SR-4
    "lodi": (-121.2800, 38.1300),
    "elkgrove": (-121.3700, 38.4100),
    "sacramento": (-121.4900, 38.5800),    # I-5 / I-80 / US-50 / SR-99
    "woodland": (-121.7700, 38.6800),
    "dunnigan": (-121.9800, 38.8800),      # I-5 / I-505
    "williams": (-122.1500, 39.1500),      # I-5 / SR-20
    "willows": (-122.1900, 39.5200),
    "orland": (-122.1900, 39.7500),
    "corning": (-122.1800, 39.9300),
    "redbluff": (-122.2400, 40.1800),      # I-5 / SR-99 / SR-36
    "redding": (-122.3900, 40.5900),       # I-5 / SR-299 / SR-44
    "lakehead": (-122.3800, 40.9000),
    "dunsmuir": (-122.2700, 41.2100),
    "mtshasta": (-122.3100, 41.3100),
    "weed": (-122.3900, 41.4200),          # I-5 / US-97
    "yreka": (-122.6300, 41.7300),
    "or_i5": (-122.6000, 42.0120),         # I-5 Oregon border
    "dorris": (-121.9200, 41.9700),
    "or_us97": (-121.9300, 42.0120),
    "delano": (-119.2500, 35.7700),
    "tulare": (-119.3400, 36.2100),
    "visalia": (-119.3200, 36.3000),       # SR-99 / SR-198
    "hanford": (-119.6500, 36.3300),
    "kingsburg": (-119.5500, 36.5100),
    "fresno": (-119.7900, 36.7400),        # SR-99 / SR-41 / SR-180
    "madera": (-120.0600, 36.9600),
    "merced": (-120.4800, 37.3000),        # SR-99 / SR-140
    "turlock": (-120.8500, 37.4900),
    "modesto": (-120.9900, 37.6400),       # SR-99 / SR-108 / SR-132
    "manteca": (-121.2200, 37.8000),       # SR-99 / SR-120
    "oakdale": (-120.8500, 37.7700),
    "groveland": (-120.2300, 37.8400),
    "craneflat": (-119.8000, 37.7500),
    "yosemitevalley": (-119.5900, 37.7300),
    "tuolumnemeadows": (-119.3600, 37.8700),
    "leevining": (-119.1200, 37.9600),     # US-395 / SR-120
    "mariposa": (-119.9700, 37.4900),
    "oakhurst": (-119.6500, 37.3300),
    "sonora": (-120.3800, 37.9800),
    "sonorapass_395": (-119.4500, 38.3300),
    "jackson": (-120.7700, 38.3500),
    "carsonpass": (-119.9900, 38.6900),
    "nv_sr88": (-119.6800, 38.8100),       # SR-88 Nevada border
    "atascadero": (-120.6700, 35.4900),    # US-101 / SR-41
    "pasorobles": (-120.6900, 35.6300),    # US-101 / SR-46
    "slo": (-120.6600, 35.2800),           # US-101 / SR-1
    "pismo": (-120.6400, 35.1400),
    "santamaria": (-120.4300, 34.9500),    # US-101 / SR-166
    "buellton": (-120.1900, 34.6100),      # US-101 / SR-154 / SR-246
    "gaviota": (-120.2200, 34.4800),
    "santabarbara": (-119.7000, 34.4200),  # US-101 / SR-154
    "carpinteria": (-119.5200, 34.4000),
    "morrobay": (-120.8500, 35.3700),
    "cambria": (-121.0900, 35.5600),       # SR-1 / SR-46
    "raggedpoint": (-121.3200, 35.7800),
    "bigsur": (-121.8100, 36.2700),
    "carmel": (-121.9200, 36.5500),
    "monterey": (-121.8900, 36.6000),      # SR-1 / SR-68
    "salinas": (-121.6600, 36.6800),       # US-101 / SR-68
    "kingcity": (-121.1300, 36.2100),
    "gilroy": (-121.5700, 37.0000),        # US-101 / SR-152
    "watsonville": (-121.7600, 36.9100),
    "santacruz": (-122.0300, 36.9700),     # SR-1 / SR-17
    "halfmoonbay": (-122.4300, 37.4600),
    "sanjose": (-121.8900, 37.3400),       # US-101 / I-880 / I-280 / SR-17
    "sanfrancisco": (-122.4200, 37.7700),
    "oakland": (-122.2700, 37.8000),       # I-80 / I-580 / I-880
    "livermore": (-121.7700, 37.6800),
    "vallejo": (-122.2500, 38.1000),
    "fairfield": (-122.0400, 38.2500),
    "vacaville": (-121.9800, 38.3600),     # I-80 / I-505
    "davis": (-121.7400, 38.5400),
    "roseville": (-121.2900, 38.7500),
    "auburn": (-121.0800, 38.9000),
    "colfax": (-120.9500, 39.1000),
    "emigrantgap": (-120.6700, 39.2900),   # I-80 / SR-20
    "truckee": (-120.1800, 39.3300),       # I-80 / SR-89 / SR-267
    "nv_i80": (-119.9950, 39.4450),        # I-80 Nevada border
    "placerville": (-120.8000, 38.7300),
    "southlaketahoe": (-119.9800, 38.9400),
    "nv_us50": (-119.9420, 38.9600),       # US-50 Stateline
    "tahoecity": (-120.1400, 39.1700),
    "sanrafael": (-122.5300, 37.9700),
    "novato": (-122.5700, 38.1000),
    "petaluma": (-122.6400, 38.2300),
    "santarosa": (-122.7100, 38.4400),
    "healdsburg": (-122.8700, 38.6100),
    "cloverdale": (-123.0200, 38.8000),
    "ukiah": (-123.2100, 39.1500),         # US-101 / SR-20
    "willits": (-123.3500, 39.4100),
    "laytonville": (-123.4800, 39.6900),
    "leggett": (-123.7200, 39.8700),       # US-101 / SR-1
    "garberville": (-123.8000, 40.1000),
    "fortuna": (-124.1600, 40.6000),
    "eureka": (-124.1600, 40.8000),
    "arcata": (-124.0900, 40.8700),        # US-101 / SR-299
    "trinidad": (-124.1400, 41.0600),
    "orick": (-124.0600, 41.2900),
    "klamath": (-124.0400, 41.5300),
    "crescentcity": (-124.2000, 41.7600),  # US-101 / US-199
    "or_us101": (-124.2100, 42.0120),
    "gasquet": (-123.9700, 41.8500),
    "or_us199": (-123.8200, 42.0120),
    "bodegabay": (-123.0500, 38.3300),
    "jenner": (-123.1100, 38.4500),
    "pointarena": (-123.6900, 38.9100),
    "fortbragg": (-123.8000, 39.4400),
    "clearlake": (-122.6300, 39.0300),
    "yubacity": (-121.6200, 39.1400),      # SR-99 / SR-20 / SR-70
    "grassvalley": (-121.0600, 39.2200),
    "oroville": (-121.5500, 39.5100),
    "chico": (-121.8400, 39.7300),
    "quincy": (-120.9500, 39.9400),
    "hallelujah_jn": (-120.0300, 39.7800), # US-395 / SR-70
    "nv_us395_reno": (-119.9950, 39.7200), # US-395 Nevada border (Reno)
    "susanville": (-120.6500, 40.4200),    # US-395 / SR-36 / SR-44 / SR-139
    "oldstation": (-121.5500, 40.6800),
    "burney": (-121.6600, 40.8800),
    "alturas": (-120.5400, 41.4900),       # US-395 / SR-299 / SR-139
    "or_us395": (-120.3500, 42.0120),
    "cedarville": (-120.1700, 41.5300),
    "nv_sr299": (-119.9990, 41.5200),
    "tulelake": (-121.4800, 41.9500),
    "or_sr139": (-121.4600, 42.0120),
    "weaverville": (-122.9400, 40.7300),
    "willowcreek": (-123.6300, 40.9400),
    "lonepine": (-118.0600, 36.6100),      # US-395 / SR-136
    "olancha": (-118.0000, 36.2800),       # US-395 / SR-190
    "bigpine": (-118.2900, 37.1700),
    "bishop": (-118.4000, 37.3600),        # US-395 / US-6
    "mammoth_jn": (-118.8500, 37.6300),
    "bridgeport": (-119.2300, 38.2600),
    "nv_us395_topaz": (-119.5000, 38.6800),
    "benton": (-118.4800, 37.8200),
    "nv_us6": (-118.0500, 37.9300),
    "panamint": (-117.4700, 36.3400),
    "stovepipe": (-117.1500, 36.6000),
    "furnacecreek": (-116.8700, 36.4600),
    "deathvalleyjn": (-116.4200, 36.3000),
    "nv_sr127": (-116.4100, 36.4900),
    "shoshone": (-116.2700, 35.9700),
    "elcajon": (-116.9600, 32.8000),
    "alpine": (-116.7700, 32.8300),
    "pinevalley": (-116.5300, 32.8200),
    "jacumba": (-116.1900, 32.6200),
    "elcentro": (-115.5600, 32.7900),      # I-8 / SR-86 / SR-111
    "calexico": (-115.5000, 32.6550),      # Mexico border
    "az_i8": (-114.7150, 32.7150),         # I-8 Arizona border (Yuma)
    "brawley": (-115.5300, 33.0000),       # SR-86 / SR-78
    "julian": (-116.6000, 33.0800),
    "simivalley": (-118.7800, 34.2700),
    "moorpark": (-118.8800, 34.2800),
    "fillmore": (-118.9200, 34.4000),
    "malibu": (-118.6800, 34.0300),
}

# (name, class, [waypoints...]) -- waypoints are PLACES keys or (lon, lat).
ROUTES = [
    # --- LA metro freeways -----------------------------------------------------
    ("I-5", "freeway_urban", ["dtla", "eastla_ic", "i5_commerce", "norwalk", "buenapark",
                             "anaheim", "santaana", "irvine_i5", "eltoro"]),
    ("I-5", "freeway_rural", ["eltoro", "sjc", "sanclemente", "oceanside", "carlsbad",
                             "encinitas", "delmar", "lajolla"]),
    ("I-5", "freeway_urban", ["lajolla", "sandiego", "chulavista", "sanysidro"]),
    ("I-5", "freeway_urban", ["dtla", "burbank", "i405_i5_sylmar", "santaclarita"]),
    ("I-5", "freeway_rural", ["santaclarita", "castaic", "quail_lake", "gorman", "grapevine",
                             "wheelerridge", "buttonwillow", "losthills", "kettleman",
                             "coalinga_jn", "losbanos", "santanella", "patterson", "tracy",
                             "stockton", "lodi", "elkgrove", "sacramento", "woodland",
                             "dunnigan", "williams", "willows", "orland", "corning",
                             "redbluff", "redding", "lakehead", "dunsmuir", "mtshasta",
                             "weed", "yreka", "or_i5"]),
    ("I-10", "freeway_urban", ["santamonica", "westla", "dtla", "eastla_ic", "i10_i710",
                              "i10_i605", "westcovina", "pomona", "ontario", "fontana",
                              "sanbernardino", "redlands"]),
    ("I-10", "freeway_rural", ["redlands", "beaumont", "banning", "whitewater",
                              "palmsprings_jn", "indio", "chiriaco", "desertcenter",
                              "blythe", "az_i10"]),
    ("I-405", "freeway_urban", ["i405_i5_sylmar", (-118.47, 34.19), "sherman_oaks",
                               (-118.47, 34.10), "westla", (-118.40, 33.98), "lax",
                               "torrance", "longbeach", "sealbeach", (-117.98, 33.73),
                               "costamesa", "irvine_405", "eltoro"]),
    ("US-101", "freeway_urban", ["dtla", "hollywood", "sherman_oaks", "woodlandhills",
                                (-118.65, 34.15), "thousandoaks", "camarillo", "oxnard",
                                "ventura"]),
    ("US-101", "freeway_rural", ["ventura", "carpinteria", "santabarbara", (-119.83, 34.44),
                                "gaviota", "buellton", "santamaria", "pismo", "slo",
                                "atascadero", "pasorobles", (-120.70, 35.75), "kingcity",
                                "salinas", (-121.62, 36.85), "gilroy"]),
    ("US-101", "freeway_urban", ["gilroy", (-121.70, 37.15), "sanjose", (-122.10, 37.45),
                                "sanfrancisco", "sanrafael", "novato", "petaluma",
                                "santarosa"]),
    ("US-101", "freeway_rural", ["santarosa", "healdsburg", "cloverdale", "ukiah", "willits"]),
    ("US-101", "highway", ["willits", "laytonville", "leggett", "garberville", (-123.95, 40.35),
                          "fortuna", "eureka", "arcata", "trinidad", "orick", "klamath",
                          "crescentcity", "or_us101"]),
    ("I-110", "freeway_urban", ["dtla", (-118.28, 33.96), "torrance", (-118.29, 33.79),
                               (-118.29, 33.74)]),
    ("I-710", "freeway_urban", ["i10_i710", (-118.17, 33.92), "longbeach", (-118.20, 33.77)]),
    ("I-605", "freeway_urban", [(-117.99, 34.13), "i10_i605", "norwalk", "sealbeach"]),
    ("I-105", "freeway_urban", ["lax", (-118.25, 33.93), "norwalk"]),
    ("I-210", "freeway_urban", ["i405_i5_sylmar", (-118.35, 34.25), (-118.25, 34.22),
                               "pasadena", (-118.03, 34.14), "azusa", "sandimas",
                               "i210_i15", (-117.45, 34.13), "sb_210", "redlands"]),
    ("SR-134", "freeway_urban", ["burbank", (-118.25, 34.15), "pasadena"]),
    ("SR-170", "freeway_urban", ["burbank", (-118.38, 34.20), (-118.40, 34.16), "sherman_oaks"]),
    ("SR-60", "freeway_urban", ["eastla_ic", (-118.10, 34.03), (-117.80, 34.00), "ontario",
                               (-117.40, 33.99), "riverside", "morenovalley", "beaumont"]),
    ("SR-91", "freeway_urban", ["torrance", (-118.05, 33.87), "buenapark", (-117.85, 33.86),
                               (-117.78, 33.87), "corona", "riverside"]),
    ("SR-57", "freeway_urban", ["sandimas", "pomona", (-117.88, 33.95), "anaheim",
                               (-117.88, 33.78)]),
    ("SR-55", "freeway_urban", ["santaana", "costamesa"]),
    ("I-15", "freeway_urban", ["ontario", (-117.55, 34.15), "devore"]),
    ("I-15", "freeway_rural", ["devore", "cajon", "hesperia", "victorville", (-117.20, 34.65),
                              "barstow", (-116.60, 35.10), "baker", (-115.75, 35.45), "primm"]),
    ("I-15", "freeway_urban", ["ontario", (-117.57, 33.95), "corona"]),
    ("I-15", "freeway_rural", ["corona", "lakeelsinore", "temecula", (-117.12, 33.30),
                              "escondido", "miramar", "sd_i8_i15"]),
    ("I-215", "freeway_urban", ["devore", "sb_210", "sanbernardino", "riverside", "perris",
                               (-117.20, 33.60), "temecula"]),
    ("I-8", "freeway_urban", ["sandiego", "sd_i8_i15", "elcajon"]),
    ("I-8", "freeway_rural", ["elcajon", "alpine", "pinevalley", "jacumba", (-115.90, 32.75),
                             "elcentro", (-115.10, 32.70), "az_i8"]),
    ("I-805", "freeway_urban", ["lajolla", (-117.15, 32.80), "chulavista"]),
    ("SR-78", "highway", ["oceanside", "escondido", (-116.90, 33.10), "julian",
                         (-116.20, 33.10), "brawley"]),
    ("SR-86", "highway", ["indio", (-115.85, 33.35), "brawley", "elcentro", "calexico"]),
    ("SR-14", "freeway_rural", ["santaclarita", (-118.35, 34.48), "palmdale", "lancaster",
                              (-118.15, 34.90), "mojave"]),
    ("SR-14", "highway", ["mojave", "redrock", "inyokern"]),
    ("SR-138", "highway", ["quail_lake", (-118.45, 34.65), "palmdale", (-117.80, 34.45),
                          "cajon"]),
    ("SR-58", "highway", ["bakersfield", (-118.75, 35.25), "tehachapi", "mojave", "boron",
                         "kramer_jn", (-117.30, 34.92), "barstow"]),
    ("US-395", "highway", ["hesperia", "adelanto", "kramer_jn", "johannesburg", "inyokern",
                          "olancha", "lonepine", (-118.20, 36.90), "bigpine", "bishop",
                          (-118.70, 37.55), "mammoth_jn", "leevining", "bridgeport",
                          (-119.45, 38.50), "nv_us395_topaz"]),
    ("SR-178", "mountain", ["bakersfield", "lakeisabella", "walkerpass", "inyokern"]),
    ("SR-178", "highway", ["inyokern", "ridgecrest", "trona"]),
    ("SR-190", "highway", ["olancha", "panamint", "stovepipe", "furnacecreek", "deathvalleyjn"]),
    ("SR-127", "highway", ["baker", "shoshone", "deathvalleyjn", "nv_sr127"]),
    ("US-6", "highway", ["bishop", "benton", "nv_us6"]),
    ("I-40", "freeway_rural", ["barstow", "ludlow", (-115.50, 34.80), "needles", "topock"]),
    ("US-95", "highway", ["blythe", "vidal_jn", (-114.60, 34.50), "needles", "us95_nv"]),
    ("SR-62", "highway", ["whitewater", "yuccavalley", "twentynine", (-115.50, 34.20),
                         "vidal_jn", "parker_az"]),
    ("SR-247", "highway", ["barstow", "lucernevalley", "yuccavalley"]),
    ("SR-18", "highway", ["victorville", "lucernevalley"]),
    ("SR-99", "freeway_rural", ["wheelerridge", "bakersfield", "delano", "tulare", "visalia",
                              "kingsburg", "fresno", "madera", "merced", "turlock", "modesto",
                              "manteca", "stockton"]),
    ("SR-99", "freeway_rural", ["sacramento", (-121.55, 38.85), "yubacity", (-121.75, 39.45),
                              "chico", "redbluff"]),
    ("SR-166", "highway", ["santamaria", "newcuyama", "maricopa", (-119.15, 35.20),
                          "bakersfield"]),
    ("SR-33", "highway", ["maricopa", (-119.45, 35.35), "buttonwillow"]),
    ("SR-46", "highway", ["cambria", "pasorobles", (-120.20, 35.63), "losthills"]),
    ("SR-41", "highway", ["atascadero", (-120.30, 35.85), "kettleman", (-119.85, 36.30),
                         "fresno"]),
    ("SR-41", "mountain", ["fresno", "oakhurst", "yosemitevalley"]),
    ("SR-198", "highway", ["coalinga_jn", "hanford", "visalia"]),
    ("SR-152", "highway", ["santanella", "losbanos"]),
    ("SR-152", "highway", ["santanella", (-121.30, 37.05), "gilroy", "watsonville"]),
    ("SR-140", "mountain", ["merced", "mariposa", "yosemitevalley"]),
    ("SR-120", "mountain", ["manteca", "oakdale", "groveland", "craneflat", "yosemitevalley"]),
    ("SR-120", "mountain", ["craneflat", "tuolumnemeadows", "leevining"]),
    ("SR-108", "mountain", ["modesto", "sonora", (-119.90, 38.20), "sonorapass_395"]),
    ("US-395", "highway", ["bridgeport", "sonorapass_395"]),
    ("SR-88", "mountain", ["stockton", "jackson", "carsonpass", "nv_sr88"]),
    ("SR-1", "highway", ["santamonica", "malibu", (-118.95, 34.05), "oxnard"]),
    ("SR-1", "highway", ["slo", "morrobay", "cambria"]),
    ("SR-1", "mountain", ["cambria", "raggedpoint", (-121.55, 36.00), "bigsur", "carmel"]),
    ("SR-1", "highway", ["carmel", "monterey", (-121.80, 36.80), "watsonville", "santacruz",
                        (-122.30, 37.20), "halfmoonbay", (-122.48, 37.70), "sanfrancisco"]),
    ("SR-1", "mountain", ["sanrafael", (-122.70, 38.10), "bodegabay", "jenner", (-123.40, 38.65),
                         "pointarena", (-123.75, 39.20), "fortbragg", "leggett"]),
    ("SR-68", "highway", ["monterey", "salinas"]),
    ("SR-17", "highway", ["santacruz", "sanjose"]),
    ("SR-154", "mountain", ["santabarbara", (-119.95, 34.55), "buellton"]),
    ("SR-126", "highway", ["santaclarita", "fillmore", (-119.05, 34.35), "ventura"]),
    ("SR-118", "freeway_urban", ["i405_i5_sylmar", (-118.60, 34.28), "simivalley", "moorpark",
                               (-119.05, 34.28), "camarillo"]),
    ("SR-23", "highway", ["moorpark", "thousandoaks"]),
    ("I-880", "freeway_urban", ["sanjose", (-122.05, 37.55), "oakland"]),
    ("I-80", "freeway_urban", ["sanfrancisco", "oakland", (-122.30, 37.95), "vallejo",
                              "fairfield", "vacaville", "davis", "sacramento", "roseville"]),
    ("I-80", "freeway_rural", ["roseville", "auburn", "colfax", "emigrantgap", (-120.40, 39.32),
                              "truckee", "nv_i80"]),
    ("I-580", "freeway_urban", ["oakland", (-122.00, 37.70), "livermore", "tracy"]),
    ("I-505", "freeway_rural", ["vacaville", "dunnigan"]),
    ("US-50", "freeway_rural", ["sacramento", (-121.10, 38.65), "placerville"]),
    ("US-50", "mountain", ["placerville", (-120.30, 38.80), "southlaketahoe", "nv_us50"]),
    ("SR-89", "mountain", ["truckee", "tahoecity", (-120.10, 39.05), "southlaketahoe"]),
    ("SR-20", "highway", ["williams", (-122.45, 39.05), "clearlake", (-122.90, 39.10), "ukiah"]),
    ("SR-20", "highway", ["yubacity", (-121.30, 39.15), "grassvalley", (-120.85, 39.25),
                         "emigrantgap"]),
    ("SR-70", "highway", ["yubacity", "oroville", (-121.30, 39.70), (-121.00, 39.80), "quincy",
                         (-120.50, 39.85), "hallelujah_jn"]),
    ("US-395", "highway", ["hallelujah_jn", "nv_us395_reno"]),
    ("US-395", "highway", ["hallelujah_jn", (-120.10, 40.05), "susanville", (-120.55, 40.90),
                          (-120.40, 41.20), "alturas", (-120.40, 41.80), "or_us395"]),
    ("SR-36", "mountain", ["redbluff", (-121.70, 40.30), (-121.20, 40.35), "susanville"]),
    ("SR-44", "mountain", ["redding", (-121.90, 40.60), "oldstation", (-121.10, 40.55),
                          "susanville"]),
    ("SR-299", "mountain", ["redding", (-122.00, 40.75), "burney", (-121.20, 41.05),
                           (-120.80, 41.30), "alturas", "cedarville", "nv_sr299"]),
    ("SR-299", "mountain", ["redding", (-122.65, 40.65), "weaverville", (-123.30, 40.80),
                           "willowcreek", (-123.85, 40.90), "arcata"]),
    ("SR-139", "highway", ["susanville", (-120.90, 40.90), (-121.10, 41.30), (-121.40, 41.70),
                          "tulelake", "or_sr139"]),
    ("US-97", "highway", ["weed", (-122.10, 41.65), "dorris", "or_us97"]),
    ("SR-89", "mountain", ["mtshasta", (-122.05, 41.20), "burney"]),
    ("US-199", "mountain", ["crescentcity", "gasquet", "or_us199"]),
    ("SR-96", "mountain", ["willowcreek", (-123.50, 41.30), (-123.20, 41.75), "yreka"]),
]


def resolve(wp):
    """Return (lon, lat, key) for a waypoint spec."""
    if isinstance(wp, str):
        lon, lat = PLACES[wp]
        return lon, lat, wp
    lon, lat = wp
    return lon, lat, "%.4f,%.4f" % (lon, lat)
