"""
How Ced says its own name on voice calls: "Ced" rhymes with "red" (like the
word "said"), never "seed" or "Sayeed". Gemini is faked; no real calls.
"""
import asyncio

from app.ced import prompt, voice


def test_the_voice_prompt_says_how_to_pronounce_ced():
    guide = prompt.VOICE_PROMPT
    assert "HOW TO SAY YOUR NAME" in guide
    assert 'like the word "said"' in guide and '"red"' in guide and "/sɛd/" in guide
    for wrong in ('"seed"', '"Sayeed"'):
        assert wrong in guide   # named as what NOT to say


def test_the_live_config_carries_the_pronunciation():
    assert "HOW TO SAY YOUR NAME" in voice.live_config().system_instruction


def test_text_chat_and_the_visible_name_are_unchanged():
    assert "HOW TO SAY YOUR NAME" not in prompt.SYSTEM_PROMPT
    assert prompt.VOICE_PROMPT.startswith(prompt.CHARACTER)   # same Ced, same personality
    assert "You are Ced," in prompt.VOICE_PROMPT               # the name itself is still written Ced
    assert "Sed" not in prompt.CHARACTER


class _RecordingSession:
    def __init__(self):
        self.sent: list[str] = []

    async def send_client_content(self, turns, turn_complete):
        self.sent.append(turns.parts[0].text)


def test_the_greeting_and_the_reconnect_remind_the_model_how_to_say_its_name():
    from google.genai import types

    recorder = _RecordingSession()
    session = voice.GeminiSession(recorder, types)
    asyncio.run(session.greet())
    asyncio.run(session.greet(reconnected=True))
    assert recorder.sent == [prompt.VOICE_GREETING, prompt.VOICE_RECONNECTED]
    assert all('like the word "said"' in text for text in recorder.sent)
    assert "repeat what they last said" in recorder.sent[1]   # reconnect behaviour kept
