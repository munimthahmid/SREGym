def mark_fault_injected(method=None, *, strict=True):
    """Update fault state only after success; propagate recovery errors by default."""
    if method is None:
        return lambda wrapped: mark_fault_injected(wrapped, strict=strict)

    def wrapper(self, *args, **kwargs):
        try:
            result = method(self, *args, **kwargs)
        except Exception as e:
            if method.__name__ == "inject_fault" or strict:
                # A failed recovery must reach the conductor's cleanup accounting.
                raise
            else:
                print(f"[{method.__name__}] Warning: encountered error: {e!r}")
                return None

        self.fault_injected = method.__name__ == "inject_fault"
        return result

    return wrapper
