from typing import Annotated
from uuid import UUID

from fastapi import Header

# FastAPI turns x_installation_id into the "X-Installation-ID" header.
# Typing it as UUID means anything that isn't a valid UUID gets rejected (422).
InstallationId = Annotated[UUID, Header()]
