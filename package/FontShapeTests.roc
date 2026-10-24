import FontShape

## In-package tests of `FontShape` for what `Font` never lets reach it. The
## behaviour callers see is tested through the public API in `tests/api/`.
## Test-only: `main.roc` does not import this module. Run with
## `roc test package/FontShapeTests.roc`.
FontShapeTests :: {}.{}

# A table too short for its header is refused by the reader itself; `Font`
# refuses such a table before reading it, so only a direct call reaches
# this check.
expect FontShape.read([]).is_err()
expect FontShape.read(List.repeat(0, 9)).is_err()
