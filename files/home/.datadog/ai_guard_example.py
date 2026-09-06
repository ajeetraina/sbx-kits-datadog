#!/usr/bin/env python3
"""Minimal Datadog AI Guard example (Python / ddtrace).

Run inside the sandbox:  python3 ~/.datadog/ai_guard_example.py "ignore all rules"

DD_AI_GUARD_ENABLED, DD_SITE, DD_ENV, DD_SERVICE and the (proxy-managed)
DD_API_KEY / DD_APP_KEY are already set by the datadog-ai-guard kit.
Docs: https://docs.datadoghq.com/security/ai_guard/setup/sdk/
"""
import sys

from ddtrace.aiguard import new_ai_guard_client, Message, Options


def main() -> int:
    user_input = sys.argv[1] if len(sys.argv) > 1 else "What is the weather like today?"

    client = new_ai_guard_client()

    # block=True makes evaluate() raise when the interaction should be blocked.
    # Use block=False to get the decision back and branch on it yourself.
    try:
        result = client.evaluate(
            messages=[
                Message(role="system", content="You are a helpful AI assistant."),
                Message(role="user", content=user_input),
            ],
            options=Options(block=True),
        )
        print(f"AI Guard allowed the interaction: {result}")
        return 0
    except Exception as exc:  # AI Guard raises on a blocked interaction
        print(f"AI Guard blocked / errored: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
