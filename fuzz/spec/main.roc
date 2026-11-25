app [target] {
	build: "../../tests/support/main.roc",
	font: "../../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
}

import fuzz.Fuzz
import AxisMapping
import Budgets
import ClassPairs
import ClusterRanges
import Cmap
import CmapSpan
import Collection
import Composite
import Context
import ContextEncodings
import DeltaMap
import Direction
import FeatureVariations
import Features
import Fractions
import Gpos
import Gsub
import LookupFiltering
import Math
import MathVariants
import MetricVariations
import Metrics
import Names
import Outlines
import Reverse
import SpaceWidths
import Tracing
import WidthBounds

target = Fuzz.suite([Cmap.target, Context.target, Gpos.target, Gsub.target])

expect AxisMapping.check({})
expect Budgets.check({})
expect ClassPairs.check({})
expect ClusterRanges.check({})
expect CmapSpan.check({})
expect Collection.check({})
expect Composite.check({})
expect ContextEncodings.check({})
expect DeltaMap.check({})
expect Direction.check({})
expect FeatureVariations.check({})
expect Features.check({})
expect Fractions.check({})
expect LookupFiltering.check({})
expect Math.check({})
expect MathVariants.check({})
expect MetricVariations.check({})
expect MetricVariations.wide_check({})
expect Metrics.check({})
expect Names.check({})
expect Outlines.check({})
expect Reverse.check({})
expect SpaceWidths.check({})
expect Tracing.check({})
expect WidthBounds.check({})
