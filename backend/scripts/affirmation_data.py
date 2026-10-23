"""
The affirmation catalog for the "Grow with Kindness" plant game.

Loaded into the database by scripts/seed_affirmations.py and bundled in the
app (CtrlExDelete/CtrlExDelete/Resources/Affirmations.json, written by
scripts/export_affirmations.py) with the same stable ids. Change the wording
here, then run both scripts.

The sentences are original and research-informed: the sources below shaped
the themes and the way the sentences are phrased. None of them tested these
exact sentences, and neither these sentences nor the game have been validated
for breakup recovery.

Two different research ideas, kept apart on purpose:
- Values-based self-affirmation (e.g. writing about what matters to you) is
  the well-studied intervention (COHEN2014, MCQUEEN2006). The "identity and
  values" theme borrows its idea of turning towards personal values.
- Repeating positive self-statements is different: one set of studies found
  sweeping ones ("I'm a lovable person") lifted mood for people with high
  self-esteem but backfired for people with low self-esteem (WOOD2009). So
  every sentence here is modest and believable: "I can", "I am learning",
  "I can give myself permission", never a claim to already feel fine.
"""

THEMES = [
    ("self_kindness", "Self-kindness"),
    ("identity_values", "Identity and personal values"),
    ("small_steps", "Confidence and small steps"),
    ("boundaries", "Boundaries"),
    ("acceptance", "Acceptance and moving forward"),
]

# Every citation checked against its DOI record (Crossref).
SOURCES = {
    "COHEN2014": {
        "citation": "Cohen, G. L., & Sherman, D. K. (2014). The psychology of change: Self-affirmation and social "
                    "psychological intervention. Annual Review of Psychology, 65, 333–371.",
        "url": "https://doi.org/10.1146/annurev-psych-010213-115137",
        "kind": "values_self_affirmation",
        "finding": "Review: affirming important personal values (usually by writing about them) can reduce "
                   "defensiveness and the sense of threat, with effects that depend on timing and context.",
        "limitations": "About values-affirmation exercises, not repeating sentences; not studied after breakups.",
    },
    "MCQUEEN2006": {
        "citation": "McQueen, A., & Klein, W. M. P. (2006). Experimental manipulations of self-affirmation: A "
                    "systematic review. Self and Identity, 5(4), 289–354.",
        "url": "https://doi.org/10.1080/15298860600805325",
        "kind": "values_self_affirmation",
        "finding": "Systematic review of how self-affirmation is induced in experiments; the most common method "
                   "is reflecting on a personally important value.",
        "limitations": "Describes study methods and their variety; does not evaluate spoken affirmation games.",
    },
    "WOOD2009": {
        "citation": "Wood, J. V., Perunovic, W. Q. E., & Lee, J. W. (2009). Positive self-statements: Power for "
                    "some, peril for others. Psychological Science, 20(7), 860–866.",
        "url": "https://doi.org/10.1111/j.1467-9280.2009.02370.x",
        "kind": "positive_self_statements",
        "finding": "Repeating a sweeping positive self-statement improved mood for people with high self-esteem "
                   "but left people with low self-esteem feeling worse.",
        "limitations": "Small laboratory studies with university students and one statement; it informs our "
                       "cautious wording, it does not test it.",
    },
    "NEFF2003": {
        "citation": "Neff, K. (2003). Self-compassion: An alternative conceptualization of a healthy attitude "
                    "toward oneself. Self and Identity, 2(2), 85–101.",
        "url": "https://doi.org/10.1080/15298860309032",
        "kind": "self_compassion",
        "finding": "Defines self-compassion as self-kindness, a sense of common humanity and mindful awareness "
                   "of painful feelings, and introduces a scale to measure it.",
        "limitations": "A conceptual and measurement paper, not an intervention study.",
    },
    "BREINES2012": {
        "citation": "Breines, J. G., & Chen, S. (2012). Self-compassion increases self-improvement motivation. "
                    "Personality and Social Psychology Bulletin, 38(9), 1133–1143.",
        "url": "https://doi.org/10.1177/0146167212445599",
        "kind": "self_compassion",
        "finding": "In experiments, a self-compassionate stance towards a weakness or mistake increased "
                   "motivation to improve rather than reducing it.",
        "limitations": "Short laboratory inductions with students; not breakup-specific.",
    },
    "SBARRA2012": {
        "citation": "Sbarra, D. A., Smith, H. L., & Mehl, M. R. (2012). When leaving your ex, love yourself: "
                    "Observational ratings of self-compassion predict the course of emotional recovery following "
                    "marital separation. Psychological Science, 23(3), 261–269.",
        "url": "https://doi.org/10.1177/0956797611429466",
        "kind": "breakup_research",
        "finding": "Adults who spoke about their separation with more self-compassion reported less "
                   "separation-related distress over the following months.",
        "limitations": "Correlational, with recently separated or divorced adults; it shows an association, "
                       "not that affirmations cause recovery.",
    },
    "SLOTTER2010": {
        "citation": "Slotter, E. B., Gardner, W. L., & Finkel, E. J. (2010). Who am I without you? The influence "
                    "of romantic breakup on the self-concept. Personality and Social Psychology Bulletin, 36(2), "
                    "147–160.",
        "url": "https://doi.org/10.1177/0146167209352250",
        "kind": "breakup_research",
        "finding": "Breakups can reduce self-concept clarity (a clear sense of who you are), and this loss was "
                   "linked with emotional distress after the breakup.",
        "limitations": "Mostly student samples; describes what happens after breakups, not how to help.",
    },
    "LARSON2015": {
        "citation": "Larson, G. M., & Sbarra, D. A. (2015). Participating in research on romantic breakups "
                    "promotes emotional recovery via changes in self-concept clarity. Social Psychological and "
                    "Personality Science, 6(4), 399–406.",
        "url": "https://doi.org/10.1177/1948550614563085",
        "kind": "breakup_research",
        "finding": "Repeatedly reflecting on a recent breakup during a study went along with a clearer sense of "
                   "self, which in turn predicted less breakup-related distress.",
        "limitations": "The reflection happened through research tasks, not affirmations; a small student sample.",
    },
    "MARSHALL2012": {
        "citation": "Marshall, T. C. (2012). Facebook surveillance of former romantic partners: Associations with "
                    "postbreakup recovery and personal growth. Cyberpsychology, Behavior, and Social Networking, "
                    "15(10), 521–526.",
        "url": "https://doi.org/10.1089/cyber.2012.0125",
        "kind": "breakup_research",
        "finding": "Checking an ex-partner's Facebook page was associated with more distress, longing and "
                   "negative feelings, and with less personal growth.",
        "limitations": "Cross-sectional, so cause and effect are unclear; about online monitoring specifically.",
    },
    "HAYES2006": {
        "citation": "Hayes, S. C., Luoma, J. B., Bond, F. W., Masuda, A., & Lillis, J. (2006). Acceptance and "
                    "commitment therapy: Model, processes and outcomes. Behaviour Research and Therapy, 44(1), "
                    "1–25.",
        "url": "https://doi.org/10.1016/j.brat.2005.06.006",
        "kind": "acceptance",
        "finding": "Describes acceptance (making room for difficult feelings) and values-guided action, and "
                   "reviews outcome studies of the therapy built on them.",
        "limitations": "A therapy delivered by clinicians across many conditions; not breakup-specific and not "
                       "a single-sentence exercise.",
    },
    "BANDURA1977": {
        "citation": "Bandura, A. (1977). Self-efficacy: Toward a unifying theory of behavioral change. "
                    "Psychological Review, 84(2), 191–215.",
        "url": "https://doi.org/10.1037/0033-295X.84.2.191",
        "kind": "self_efficacy",
        "finding": "Theory that confidence to act (self-efficacy) grows most from mastery experiences, such as "
                   "succeeding at small, manageable steps.",
        "limitations": "A theoretical paper; it does not test affirmations.",
    },
}

# Which principle each source supports for a theme, and how it shaped the wording.
WORDING = ("Modest, believable wording", "Sentences say “I can” or “I am learning” instead of "
           "claiming the user already feels confident or healed, because sweeping positive statements can backfire "
           "for people who feel low.")
THEME_SOURCES = [
    ("self_kindness", "NEFF2003", "Self-compassion", "Speaking to yourself with kindness, and remembering that hard "
     "days are part of being human, is the core of self-compassion."),
    ("self_kindness", "BREINES2012", "Kindness and growth", "Being kind about mistakes doesn't stop growth; it can "
     "support the wish to keep trying."),
    ("self_kindness", "SBARRA2012", "Self-compassion after a separation", "Self-compassion when talking about a "
     "separation was linked with less distress over time."),
    ("self_kindness", "WOOD2009", *WORDING),
    ("identity_values", "COHEN2014", "Turning towards personal values", "Values-affirmation research suggests that "
     "reconnecting with what matters to you can ease a sense of threat; these sentences borrow that focus."),
    ("identity_values", "MCQUEEN2006", "Turning towards personal values", "Reflecting on important values is the "
     "most common way self-affirmation is studied, which is why this theme centres values, not praise."),
    ("identity_values", "SLOTTER2010", "Sense of self after a breakup", "Breakups can blur who you are; sentences "
     "invite rediscovering identity and interests outside the relationship."),
    ("identity_values", "LARSON2015", "Self-concept clarity", "A clearer sense of self went along with less "
     "breakup-related distress."),
    ("identity_values", "WOOD2009", *WORDING),
    ("small_steps", "BANDURA1977", "Confidence through small steps", "Confidence grows from small successes, so "
     "sentences focus on single, doable steps rather than big outcomes."),
    ("small_steps", "WOOD2009", *WORDING),
    ("boundaries", "MARSHALL2012", "Limiting contact and checking", "Monitoring an ex's online activity was "
     "associated with more distress, so sentences support choosing what to look at and when."),
    ("boundaries", "NEFF2003", "Self-kindness as protection", "Taking your own needs seriously is a form of "
     "self-kindness; sentences frame space and pauses as care, not punishment."),
    ("boundaries", "WOOD2009", *WORDING),
    ("acceptance", "HAYES2006", "Acceptance and values-guided action", "Making room for feelings while still "
     "moving towards what matters is central to acceptance-based approaches."),
    ("acceptance", "SBARRA2012", "Self-compassion after a separation", "A kinder relationship with painful feelings "
     "was linked with less distress over time; no deadlines are implied."),
    ("acceptance", "WOOD2009", *WORDING),
]

# (id, theme, text, editorial note). Original sentences; the notes are for
# editors only and never shown in the game.
AFFIRMATIONS = [
    ("kindness-01", "self_kindness", "I can be gentle with myself today.", "Self-kindness, limited to today."),
    ("kindness-02", "self_kindness", "I can treat myself like someone I care about.", "Self-kindness as a choice, not a feeling."),
    ("kindness-03", "self_kindness", "I can rest without having to earn it.", "Permission to rest; no productivity condition."),
    ("kindness-04", "self_kindness", "I can make mistakes and still be kind to myself.", "Kindness about mistakes (Breines & Chen)."),
    ("kindness-05", "self_kindness", "I am learning to speak to myself with care.", "“Learning” keeps it believable."),
    ("kindness-06", "self_kindness", "I can be patient with how I feel.", "Patience instead of a recovery deadline."),
    ("values-01", "identity_values", "I can rediscover what matters to me.", "Values focus; suggested example tone."),
    ("values-02", "identity_values", "I am more than one relationship.", "Self-concept beyond the relationship; no claim about the ex."),
    ("values-03", "identity_values", "I can make room for the things I love.", "Interests and identity outside the relationship."),
    ("values-04", "identity_values", "I am learning who I am on my own.", "Self-concept clarity as an ongoing process."),
    ("values-05", "identity_values", "My values can guide my next choice.", "Values-guided action, one choice at a time."),
    ("values-06", "identity_values", "I can lean on people who care about me.", "Connection as part of identity; no pressure to talk."),
    ("steps-01", "small_steps", "I can take this one step at a time.", "Suggested example tone; mastery through small steps."),
    ("steps-02", "small_steps", "One small step still counts.", "Values effort over outcome."),
    ("steps-03", "small_steps", "I can try one new thing today.", "A single doable step."),
    ("steps-04", "small_steps", "I am learning that I can handle hard things.", "Confidence as something learned."),
    ("steps-05", "small_steps", "I can begin before I feel ready.", "Action without first needing to feel confident."),
    ("steps-06", "small_steps", "I can be proud of showing up today.", "Credit for showing up, not for results."),
    ("boundaries-01", "boundaries", "I can give myself permission to pause before I reply.", "A pause, not a rule about contact."),
    ("boundaries-02", "boundaries", "I can choose what I look at and when.", "Choice about checking (Marshall 2012), no prohibition."),
    ("boundaries-03", "boundaries", "I can protect my peace.", "Short and easy to say."),
    ("boundaries-04", "boundaries", "I can say no to what doesn’t feel right.", "Boundaries as self-respect."),
    ("boundaries-05", "boundaries", "I can give myself space when I need it.", "Space framed as care."),
    ("boundaries-06", "boundaries", "My needs are worth respecting.", "Needs as legitimate, without demands on others."),
    ("acceptance-01", "acceptance", "I can miss someone and still move forward.", "Suggested example tone; both feelings allowed."),
    ("acceptance-02", "acceptance", "I can let my feelings come and go.", "Acceptance of feelings without fixing them."),
    ("acceptance-03", "acceptance", "I can accept today as it is.", "Present-moment acceptance; no outcome promised."),
    ("acceptance-04", "acceptance", "I can give myself permission to grieve.", "Grief as allowed; no timeline."),
    ("acceptance-05", "acceptance", "I can carry what I learned into what comes next.", "Growth without needing to forgive or reframe."),
    ("acceptance-06", "acceptance", "I can move forward at my own pace.", "No deadline; the user sets the pace."),
]
