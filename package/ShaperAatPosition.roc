import TableAatKern
import TableAatAnchor
import LayoutGsub

## Bounded AAT positioning over already substituted glyphs. Inputs and
## outputs remain index aligned in the caller's native buffer order.
ShaperAatPosition :: {}.{
	Initial : TableAatKern.Initial
	Context : TableAatKern.Context
	Applied : TableAatKern.Applied
	apply : TableAatKern, TableAatAnchor, List(LayoutGsub.Item), Initial, Context -> Applied
	apply = |table, anchors, items, initial, context| TableAatKern.apply(table, anchors, items, initial, context)
}
