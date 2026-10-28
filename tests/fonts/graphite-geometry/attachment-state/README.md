# Attachment state controls

These 18 original UPL programs pin insertion boundaries and the distinction
between authored metrics and inherited collision movement. The parent builder
and the documented public Graphite2 1.3.14 C ABI are the only construction and
behavior sources. No engine implementation code was opened or used.

Writing InsertBefore (attribute 17) to false or true before attaching retains that value.
The explicit `gr_slot_can_insert_before` result is cached for every slot; an
attachment does not itself clear the boundary. Both native directions are tested.

The ordinary parent-correction control has child advance 601 at relative x = 80 and
root advance 602. A parent collision correction of −220 moves the child to −140,
and the final segment advance becomes 602. A child-only correction keeps 681.
An independent ignored third root with advance 603 makes the first result 1205.
These distinguish inherited collision movement in the right-extent calculation
from own child corrections and authored left rebasing.

A subsequent nonzero-level PushGlyphMetric advance query still returns 681;
left/right queries remain 0/380. Thus queried composite font metrics retain
authored geometry even though final segment advancement includes inherited
collision movement. The explicit two-pass programs preserve that distinction.

Reproduce with the generator's `--check`, then the parent extractor:

```
python tests/fonts/graphite-geometry/record.py --cases attachment-state/cases.jsonc --output attachment-state/records.json --slot-insertion --check
```

Raw reference evidence is independent of a native Roc agreement claim. The
parent directory's UPL license covers these original programs and font files.
