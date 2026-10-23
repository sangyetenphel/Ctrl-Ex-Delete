from fastapi import APIRouter, HTTPException, WebSocket, status

from app.ced import chat, limits, providers, voice
from app.dependencies import InstallationId
from app.schemas import CedChatRequest, CedChatResponse

router = APIRouter(prefix="/ced", tags=["ced"])


@router.post(
    "/messages",
    response_model=CedChatResponse,
    responses={
        429: {"description": "Too many messages; see the Retry-After header"},
        503: {"description": "Ced isn't set up on the server"},
        504: {"description": "Ced took too long to answer"},
    },
)
def send_message(payload: CedChatRequest, x_installation_id: InstallationId):
    """
    Ced's reply to the conversation so far. The conversation is not stored:
    the app sends the recent turns each time and forgets them when the chat
    ends. The reply comes as 1–3 bubbles; `support` says which crisis
    resources to show under it (the app never opens them by itself).
    Crisis messages are always answered, even when the AI can't be reached.
    """
    try:
        return chat.respond(x_installation_id, payload)
    except chat.InvalidConversation as error:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, str(error)) from None
    except limits.LimitReached as error:
        detail = (
            "You’ve reached today’s limit for talking with Ced. It resets tomorrow."
            if error.daily else
            "Ced needs a short pause. Please try again in a minute."
        )
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, detail,
                            headers={"Retry-After": str(error.retry_after)}) from None
    except providers.ProviderRateLimited as error:
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS,
                            "Ced is talking with a lot of people right now. Please try again in a minute.",
                            headers={"Retry-After": str(error.retry_after or 30)}) from None
    except providers.ProviderUnavailable:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE,
                            "Ced isn’t available right now. Please try again later.") from None
    except providers.ProviderTimeout:
        raise HTTPException(status.HTTP_504_GATEWAY_TIMEOUT,
                            "Ced is taking too long to answer. Please try again.") from None
    except providers.ProviderError:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY,
                            "Ced couldn’t answer just now. Please try again.") from None


@router.websocket("/voice")
async def voice_call(websocket: WebSocket, x_installation_id: InstallationId):
    """
    A voice call with Ced (Gemini Live), relayed by the server so the key
    never reaches the app. See app/ced/voice.py for the message format.
    """
    await voice.run_call(websocket, x_installation_id)
