"""
Turns Ced's reply into 1–3 short chat bubbles, the way a friend would text.

The model is asked to do this itself; this makes sure of it. Splits happen
only between paragraphs or sentences, never mid-sentence or by length alone.
"""
import re

MAX_BUBBLES = 3
MAX_SENTENCES_PER_BUBBLE = 3

# A sentence ends with . ! ? or … (optionally followed by a closing quote or
# bracket) and the next one starts with a capital, a quote or a bracket.
_SENTENCE_BREAK = re.compile(r"(?<=[.!?…])[\"”’)]?\s+(?=[\"“‘(A-Z])")
# Short words that end with a period but don't end a sentence.
_ABBREVIATION = re.compile(r"\b(?:mr|mrs|ms|dr|st|vs|etc|e\.g|i\.e)\.$", re.IGNORECASE)


def _sentences(paragraph: str) -> list[str]:
    parts, current = [], ""
    for piece in _SENTENCE_BREAK.split(paragraph):
        current = f"{current} {piece}".strip() if current else piece.strip()
        if not _ABBREVIATION.search(current):
            parts.append(current)
            current = ""
    if current:
        parts.append(current)
    return [p for p in parts if p]


def _chunk(sentences: list[str]) -> list[str]:
    """Groups sentences into bubbles of at most 3, as evenly as possible."""
    if len(sentences) <= MAX_SENTENCES_PER_BUBBLE:
        return [" ".join(sentences)]
    count = -(-len(sentences) // MAX_SENTENCES_PER_BUBBLE)  # ceiling division
    size = -(-len(sentences) // count)
    return [" ".join(sentences[i:i + size]) for i in range(0, len(sentences), size)]


def split(parts: list[str]) -> list[str]:
    """1–3 bubbles from the model's parts (or a single block of text)."""
    bubbles: list[str] = []
    for part in parts:
        for paragraph in re.split(r"\n\s*\n|\n", part.strip()):
            paragraph = re.sub(r"\s+", " ", paragraph).strip()
            if paragraph:
                bubbles.extend(_chunk(_sentences(paragraph)))
    if len(bubbles) > MAX_BUBBLES:
        # Too many: keep the order and join the extras into the last bubble.
        bubbles = bubbles[:MAX_BUBBLES - 1] + [" ".join(bubbles[MAX_BUBBLES - 1:])]
    return bubbles
