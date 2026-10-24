"""
Ced's room messages, by pattern (the rules are in app/room_messages.py).

Short, warm and sincere: they acknowledge today's answers without claiming
certainty, offer choices rather than commands, and only mention things the app
really has (today's activities, the phone for "Say it here first", the
check-in). No forced positivity, deadlines, assumptions about the ex, or
claims about how someone is healing. Loaded by scripts/seed_room_messages.py.
"""

MESSAGES = {
    "before_check_in": [
        "How are you arriving today? Let’s check in together.",
        "Good to see you. Want to start with a quick check-in?",
        "There’s no right way to feel today. Let’s check in when you’re ready.",
        "Whenever you’re ready, a short check-in helps us find today’s small step.",
    ],
    "strong_urge": [
        "That pull can feel strong. Let’s pause and make a little space for you.",
        "Wanting to reach out makes sense. If it helps, you can say it on the phone here first.",
        "Strong urges rise and fall. A short, gentle step might help this one pass.",
        "You noticed a strong pull today, and that matters. We can take the next few minutes slowly.",
    ],
    "heavy_low_energy": [
        "Today might feel heavy. We can start with something gentle.",
        "Some days ask for less. Let’s keep today soft and simple.",
        "Heavy days can be tiring. One gentle thing is enough for today.",
        "It sounds like a low-energy day. Resting can be a small step too.",
    ],
    "low_energy": [
        "Your energy is low today, and that’s okay. We can keep things gentle.",
        "A quieter day can still hold one small step, if you’d like.",
        "Today’s ideas are gentle ones, whenever you feel ready.",
        "Small and slow is welcome here. Let’s go easy today.",
    ],
    "lonely": [
        "Feeling lonely is hard. A small moment of connection might help, if it feels right.",
        "You don’t have to carry today alone. Reaching out to someone kind is one option.",
        "Loneliness can feel loud. We can look for a gentle way to feel a little less alone.",
        "If connection feels possible today, even a small hello can count.",
    ],
    "heavy_some_energy": [
        "You don’t have to feel better before taking one small step.",
        "It’s a hard day, and you still have a little energy. Let’s use it kindly.",
        "Thoughts can feel loud today. Something for your hands or feet might help.",
        "Heavy feelings can come along. We can still choose one small thing together.",
    ],
    "lighter_with_energy": [
        "There’s a little room to explore today. What sounds good to you?",
        "Today might feel a bit lighter. Want to try something new?",
        "You have some energy today. Let’s put it toward something that feels like you.",
        "Lighter moments are worth noticing. What would you like to do with today?",
    ],
    "general": [
        "Thanks for checking in. Let’s choose one small thing together.",
        "One step at a time is a good way to move. What feels doable today?",
        "You showed up today, and that counts. Let’s find something that fits.",
        "Today can be whatever it needs to be. A small step is ready when you are.",
    ],
}

# Stable ids: "<pattern with dashes>-01" … in the order above.
CATALOG = [
    (f"{pattern.replace('_', '-')}-{number:02d}", pattern, text)
    for pattern, texts in MESSAGES.items()
    for number, text in enumerate(texts, start=1)
]
