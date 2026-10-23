"""
Writes the app's bundled copy of the affirmation catalog, so the game works
before (or without) reaching the server. Same stable ids as the database.

    python -m scripts.export_affirmations

Run it after changing scripts/affirmation_data.py; tests/test_affirmations.py
checks the bundled file matches.
"""
import json
from pathlib import Path

from scripts.affirmation_data import AFFIRMATIONS, THEMES

BUNDLED = Path(__file__).resolve().parents[2] / "CtrlExDelete" / "CtrlExDelete" / "Resources" / "Affirmations.json"


def catalog() -> dict:
    labels = dict(THEMES)
    return {
        "language": "en",
        "affirmations": [
            {"id": affirmation_id, "text": text, "theme": theme, "theme_label": labels[theme]}
            for affirmation_id, theme, text, _note in AFFIRMATIONS
        ],
    }


def main() -> None:
    BUNDLED.write_text(json.dumps(catalog(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(AFFIRMATIONS)} affirmations to {BUNDLED.relative_to(BUNDLED.parents[2])}")


if __name__ == "__main__":
    main()
