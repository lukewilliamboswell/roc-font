import AatFeatures
import AatFeatureData
import AatMorx

## Match caller OpenType feature names to a font's declared Apple
## selectors. Internal. The first active setting selects an exclusive
## feature or an on/off pair, retaining caller text ranges.
AatFeatureSelect :: {}.{

	tag : Str -> U64
	tag = |name| {
		bytes = name.to_utf8()
		var $tag = 0
		for i in 0..<4 {
			$tag = $tag * 256 + (bytes.get(i) ?? 32).to_u64()
		}
		$tag
	}

	requests : AatFeatures, List({ tag : Str, value : U32, start : U64, end : U64 }) -> List(AatMorx.Requested)
	requests = |declarations, features| {
		var $requested = []
		for f in features {
			if f.start < f.end {
				chosen_tag = AatFeatureSelect.tag(f.tag)
				if chosen_tag == 0x61616C74 {
					match AatFeatures.feature(declarations, 17) {
						Present(_) => {
							$requested = $requested.append({ type: 17, setting: f.value.to_u64(), start: f.start, end: f.end, exclusive: True })
						}
						Absent => {}
					}
				} else {
					match AatFeatureData.mappings.find_first(|m| m.tag == chosen_tag) {
						Err(_) => {}
						Ok(mapping) => {
							declared = match AatFeatures.feature(declarations, mapping.type) {
								Absent if mapping.type == 37 and mapping.on == 1 => AatFeatures.feature(declarations, 3)
								other => other
							}
							match declared {
								Absent => {}
								Present(d) => {
									$requested = $requested.append({ type: mapping.type, setting: if (f.value == 0) mapping.off else mapping.on, start: f.start, end: f.end, exclusive: d.exclusive })
								}
							}
						}
					}
				}
			}
		}
		$requested
	}

	tags : AatFeatures -> List(U64)
	tags = |declarations| {
		var $tags = []
		if AatFeatures.feature(declarations, 17) != Absent {
			$tags = $tags.append(0x61616C74)
		}
		for m in AatFeatureData.mappings {
			declared = match AatFeatures.feature(declarations, m.type) {
				Absent if m.type == 37 and m.on == 1 => AatFeatures.feature(declarations, 3)
				other => other
			}
			if declared != Absent {
				$tags = $tags.append(m.tag)
			}
		}
		$tags
	}
}

expect AatFeatureSelect.tag("liga") == 0x6C696761
expect AatFeatureSelect.tag("ab") == 0x61622020
