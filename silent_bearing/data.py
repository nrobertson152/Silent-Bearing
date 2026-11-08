"""Navies, boats, torpedoes and target warships.

Boat and torpedo figures are rounded from published wartime specifications.
Target hit points are a game balance choice, loosely based on how many
torpedo hits each ship historically took (or would plausibly need).
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class TorpedoSpec:
    name: str
    kn: float          # running speed in knots
    range_m: float     # running range in metres at that speed
    dud: float         # chance a hit fails to explode
    wake: bool         # leaves a visible bubble track


@dataclass(frozen=True)
class Target:
    id: str
    name: str
    nation: str
    type: str          # bb battleship, cv carrier, ca cruiser
    length: float
    beam: float
    kn: float          # cruising speed in this scenario
    hp: int            # torpedo hits to sink
    escorts: int
    tod: str           # day, dusk or night
    zig: bool          # zigzags while unalerted
    historical: bool
    credit: str
    note: str


@dataclass(frozen=True)
class Nation:
    id: str
    name: str
    boat: str
    sub_kn: float
    surf_kn: float
    test: float        # test depth, metres
    crush: float       # crush depth, metres
    tubes: int
    torps: int
    torp: TorpedoSpec
    blurb: str
    targets: tuple


PREFIX = {"us": "USS ", "uk": "HMS ", "jp": "", "de": ""}

ESCORT_NAMES = {
    "jp": ["Isokaze", "Yukikaze", "Hamakaze", "Urakaze", "Hatsukaze"],
    "uk": ["Legion", "Laforey", "Hesperus", "Vanoc", "Walker"],
    "us": ["Hammann", "Balch", "Benham", "Gwin", "Monssen"],
    "de": ["Z23", "Z28", "Z30", "Z33", "T7"],
}


def T(*args):
    return Target(*args)


NATIONS = {
    "us": Nation(
        "us", "United States", "Gato-class fleet boat",
        sub_kn=9, surf_kn=20, test=90, crush=150, tubes=6, torps=24,
        torp=TorpedoSpec("Mk 14", 46, 4100, 0.15, True),
        blurb="Long-legged Pacific boat with a deep magazine of torpedoes. "
              "The Mk 14 was notorious for duds until late 1943.",
        targets=(
            T("shinano", "Shinano", "jp", "cv", 266, 36, 20, 4, 3, "night", True, True,
              "USS Archerfish, 29 Nov 1944",
              "Archerfish shadowed her through the night off Honshu and hit with four "
              "torpedoes. Ten days after commissioning, she became the largest warship "
              "ever sunk by a submarine."),
            T("kongo", "Kongo", "jp", "bb", 222, 31, 16, 3, 2, "night", True, True,
              "USS Sealion, 21 Nov 1944",
              "Sealion's night attack in the Formosa Strait made Kongo the only Japanese "
              "battleship sunk by a submarine. The destroyer Urakaze went down in the same attack."),
            T("taiho", "Taiho", "jp", "cv", 260, 30, 22, 2, 3, "day", True, True,
              "USS Albacore, 19 Jun 1944",
              "One torpedo during the Battle of the Philippine Sea cracked her fuel lines. "
              "Vapour spread through the ship and exploded hours later."),
            T("shokaku", "Shokaku", "jp", "cv", 257, 26, 22, 3, 2, "day", True, True,
              "USS Cavalla, 19 Jun 1944",
              "Cavalla hit the Pearl Harbor veteran with at least three torpedoes on the "
              "same morning Taiho was struck."),
            T("yamato", "Yamato", "jp", "bb", 263, 39, 22, 8, 4, "day", True, False,
              "Never sunk by a submarine",
              "USS Skate torpedoed her in December 1943 but she shrugged it off. Carrier "
              "aircraft sank her in April 1945. Here, it's up to you."),
        )),
    "uk": Nation(
        "uk", "United Kingdom", "T-class patrol submarine",
        sub_kn=9, surf_kn=15, test=90, crush=150, tubes=6, torps=16,
        torp=TorpedoSpec("Mk VIII", 45, 4570, 0.04, True),
        blurb="Rugged patrol boat with a heavy bow salvo. The Mk VIII was a famously "
              "dependable torpedo.",
        targets=(
            T("karlsruhe", "Karlsruhe", "de", "ca", 174, 15, 15, 2, 2, "dusk", True, True,
              "HMS Truant, 9 Apr 1940",
              "Truant hit her off Kristiansand during the invasion of Norway. Too badly "
              "damaged to save, she was scuttled by her own escort."),
            T("ashigara", "Ashigara", "jp", "ca", 204, 21, 16, 3, 1, "day", True, True,
              "HMS Trenchant, 8 Jun 1945",
              "In the shallow Bangka Strait, Trenchant fired eight torpedoes at the heavy "
              "cruiser and hit with five."),
            T("kuma", "Kuma", "jp", "ca", 162, 14, 14, 2, 1, "day", True, True,
              "HMS Tally-Ho, 11 Jan 1944",
              "Tally-Ho caught the light cruiser off Penang and sank her with two hits."),
            T("prinz", "Prinz Eugen", "de", "ca", 207, 22, 22, 3, 3, "day", True, False,
              "Damaged by HMS Trident, Feb 1942",
              "Trident's torpedo wrecked her stern off Norway, but she survived the war "
              "and ended her days as an atomic bomb target at Bikini Atoll."),
            T("tirpitz", "Tirpitz", "de", "bb", 251, 36, 20, 7, 3, "dusk", True, False,
              "Never sunk by a submarine",
              "British X-craft midget submarines crippled her in her fjord in 1943. RAF "
              "Lancasters finally sank her in November 1944."),
        )),
    "de": Nation(
        "de", "Germany", "Type VIIC U-boat",
        sub_kn=7.6, surf_kn=17.7, test=220, crush=260, tubes=4, torps=14,
        torp=TorpedoSpec("G7e (electric)", 30, 5000, 0.08, False),
        blurb="The workhorse of the Atlantic. Slow underwater but can dive very deep, "
              "and the electric G7e leaves no bubble wake.",
        targets=(
            T("royaloak", "Royal Oak", "uk", "bb", 190, 27, 0, 3, 1, "night", False, True,
              "U-47, 14 Oct 1939",
              "Gunther Prien slipped U-47 into the fleet anchorage at Scapa Flow and "
              "torpedoed the battleship at anchor. More than 800 of her crew were lost."),
            T("courageous", "Courageous", "uk", "cv", 240, 27, 16, 2, 2, "dusk", True, True,
              "U-29, 17 Sep 1939",
              "Sunk southwest of Ireland two weeks into the war, the first major British "
              "warship lost in the conflict."),
            T("arkroyal", "Ark Royal", "uk", "cv", 244, 29, 18, 1, 4, "day", True, True,
              "U-81, 13 Nov 1941",
              "A single torpedo off Gibraltar flooded her boiler rooms. She capsized under "
              "tow the next day with the loss of just one man."),
            T("barham", "Barham", "uk", "bb", 196, 32, 17, 3, 4, "day", True, True,
              "U-331, 25 Nov 1941",
              "U-331 slipped through the destroyer screen off Egypt. Three hits set off a "
              "magazine explosion that was caught on newsreel film."),
            T("hood", "Hood", "uk", "bb", 262, 32, 22, 3, 3, "day", True, False,
              "Never sunk by a submarine",
              "The pride of the Royal Navy blew up under Bismarck's guns in May 1941. "
              "Here, you meet her at sea first."),
        )),
    "jp": Nation(
        "jp", "Japan", "Type B1 cruiser submarine",
        sub_kn=8, surf_kn=23.5, test=100, crush=160, tubes=6, torps=17,
        torp=TorpedoSpec("Type 95", 49, 9000, 0.03, False),
        blurb="Big, fast ocean raider. The oxygen-fuelled Type 95 runs far, fast "
              "and nearly wakeless.",
        targets=(
            T("yorktown", "Yorktown", "us", "cv", 247, 33, 2, 2, 5, "day", False, True,
              "I-168, 6 Jun 1942",
              "Crippled at Midway and under tow, she was hit by I-168, which also sank the "
              "destroyer Hammann alongside. Yorktown rolled over the next morning."),
            T("wasp", "Wasp", "us", "cv", 225, 33, 16, 3, 3, "day", True, True,
              "I-19, 15 Sep 1942",
              "A single spread from I-19 sank Wasp and also hit the battleship North "
              "Carolina and the destroyer O'Brien."),
            T("indianapolis", "Indianapolis", "us", "ca", 186, 20, 17, 2, 0, "night", False, True,
              "I-58, 30 Jul 1945",
              "Sailing alone after delivering atomic bomb components to Tinian, she was hit "
              "by two torpedoes and sank in about twelve minutes."),
            T("juneau", "Juneau", "us", "ca", 165, 16, 13, 1, 2, "day", True, True,
              "I-26, 13 Nov 1942",
              "Already damaged off Guadalcanal, she blew apart after a single hit. The five "
              "Sullivan brothers were among the dead."),
            T("enterprise", "Enterprise", "us", "cv", 247, 33, 22, 5, 4, "day", True, False,
              "Never sunk",
              "The 'Big E' fought in nearly every major Pacific carrier battle and survived "
              "the war as the most decorated US warship."),
        )),
}

NATION_ORDER = ["us", "uk", "de", "jp"]
