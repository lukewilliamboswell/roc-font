import LayoutGsub

## In-package tests of `LayoutGsub` for what `Font` never lets reach it. The
## behaviour callers see is tested through the public API in `tests/api/`.
## Test-only: `main.roc` does not import this module. Run with
## `roc test package/LayoutGsubTests.roc`.
LayoutGsubTests :: {}.{}

# A table too short for its header is refused by the reader itself; `Font`
# refuses such a table before reading it, so only a direct call reaches
# this check.
expect LayoutGsub.read([]).is_err()
expect LayoutGsub.read(List.repeat(0, 9)).is_err()
