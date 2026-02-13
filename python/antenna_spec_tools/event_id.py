
from __future__ import annotations

import copy
import hashlib
from typing import Any, Dict

from .canonicalize import canonicalize

STRIP_FIELDS = ("id", "auth", "thread", "metadata")

def strip_event_for_id(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Return a deep-copied event object with fields removed for deterministic hashing.

    Fields removed:
    - id       (self-referential)
    - auth     (can vary; not part of content-address)
    - thread   (root posts often set thread == id)
    - metadata (non-normative hints; allows derived fields like replyTopic without recursion)
    """
    e = copy.deepcopy(event)
    for k in STRIP_FIELDS:
        e.pop(k, None)
    return e

def compute_event_id(event: Dict[str, Any]) -> str:
    """
    Compute event.id = 0x + SHA-256(JCS(event without id/auth/thread/metadata)).
    """
    stripped = strip_event_for_id(event)
    canon = canonicalize(stripped)
    digest = hashlib.sha256(canon.encode("utf-8")).hexdigest()
    return "0x" + digest
