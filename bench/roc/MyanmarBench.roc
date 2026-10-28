import font.Font
import FontBench

## The shared read/shape benchmark protocol, with the script explicitly
## selected before timing. FontBench's empty-script plan is Latin and would
## measure the generic pipeline rather than this new Myanmar model.
MyanmarBench :: {}.{
	Prepared : FontBench.Prepared
	prepare : List(U8) -> Try(Prepared, Str)
	prepare = |input| {
		prepared = FontBench.prepare(input)?
		match prepared.font {
			Ready(font) => Ok({ ..prepared, plan: Planned(Font.plan(font, Font.ShapeOptions.{ script: "Mymr", language: "my" })) })
			NotRead => Ok(prepared)
		}
	}
	run = FontBench.run
}
