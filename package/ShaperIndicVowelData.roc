# HarfBuzz is licensed under the so-called "Old MIT" license.  Details follow.
# For parts of HarfBuzz that are licensed under different licenses see individual
# files names COPYING in subdirectories where applicable.
#
# Copyright © 2010-2022  Google, Inc.
# Copyright © 2015-2020  Ebrahim Byagowi
# Copyright © 2019,2020  Facebook, Inc.
# Copyright © 2012,2015  Mozilla Foundation
# Copyright © 2011  Codethink Limited
# Copyright © 2008,2010  Nokia Corporation and/or its subsidiary(-ies)
# Copyright © 2009  Keith Stribley
# Copyright © 2011  Martin Hosken and SIL International
# Copyright © 2007  Chris Wilson
# Copyright © 2005,2006,2020,2021,2022,2023  Behdad Esfahbod
# Copyright © 2004,2007,2008,2009,2010,2013,2021,2022,2023  Red Hat, Inc.
# Copyright © 1998-2005  David Turner and Werner Lemberg
# Copyright © 2016  Igalia S.L.
# Copyright © 2022  Matthias Clasen
# Copyright © 2018,2021  Khaled Hosny
# Copyright © 2018,2019,2020  Adobe, Inc
# Copyright © 2013-2015  Alexei Podtelezhnikov
#
# For full copyright notices consult the individual files in the package.
#
#
# Permission is hereby granted, without written agreement and without
# license or royalty fees, to use, copy, modify, and distribute this
# software and its documentation for any purpose, provided that the
# above copyright notice and the following two paragraphs appear in
# all copies of this software.
#
# IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE TO ANY PARTY FOR
# DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES
# ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN
# IF THE COPYRIGHT HOLDER HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH
# DAMAGE.
#
# THE COPYRIGHT HOLDER SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING,
# BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
# FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
# ON AN "AS IS" BASIS, AND THE COPYRIGHT HOLDER HAS NO OBLIGATION TO
# PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
#
# UNICODE LICENSE V3
#
# COPYRIGHT AND PERMISSION NOTICE
#
# Copyright © 1991-2026 Unicode, Inc.
#
# NOTICE TO USER: Carefully read the following legal agreement. BY
# DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
# SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
# TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
# DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of data files and any associated documentation (the "Data Files") or
# software and any associated documentation (the "Software") to deal in the
# Data Files or Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, and/or sell
# copies of the Data Files or Software, and to permit persons to whom the
# Data Files or Software are furnished to do so, provided that either (a)
# this copyright and permission notice appear with all copies of the Data
# Files or Software, or (b) this copyright and permission notice appear in
# associated Documentation.
#
# THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
# KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
# THIRD PARTY RIGHTS.
#
# IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
# BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
# OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
# WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
# ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
# FILES OR SOFTWARE.
#
# Except as contained in this notice, the name of a copyright holder shall
# not be used in advertising or otherwise to promote the sale, use or other
# dealings in these Data Files or Software without prior written
# authorization of the copyright holder.

#     MIT License
#
#     Copyright (c) Microsoft Corporation.
#
#     Permission is hereby granted, free of charge, to any person obtaining a copy
#     of this software and associated documentation files (the "Software"), to deal
#     in the Software without restriction, including without limitation the rights
#     to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#     copies of the Software, and to permit persons to whom the Software is
#     furnished to do so, subject to the following conditions:
#
#     The above copyright notice and this permission notice shall be included in all
#     copies or substantial portions of the Software.
#
#     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#     IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#     FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#     AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#     LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#     OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#     SOFTWARE

## Pinned HB14.6 invalid-vowel shaping constraints, with upstream
## minimal-prefix semantics. Generated by tools/ucd/generate-complex.py.
ShaperIndicVowelData :: {}.{
	Rule : { script : U64, first : U64, second : U64, third : U64, length : U64 }
	rules : List(Rule)
	rules = [
		{ script: 0x42656E67, first: 0x985, second: 0x9BE, third: 0x0, length: 2 },
		{ script: 0x42656E67, first: 0x98B, second: 0x9C3, third: 0x0, length: 2 },
		{ script: 0x42656E67, first: 0x98C, second: 0x9E2, third: 0x0, length: 2 },
		{ script: 0x42726168, first: 0x11005, second: 0x11038, third: 0x0, length: 2 },
		{ script: 0x42726168, first: 0x1100B, second: 0x1103E, third: 0x0, length: 2 },
		{ script: 0x42726168, first: 0x1100F, second: 0x11042, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x905, second: 0x93A, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x905, second: 0x93B, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x905, second: 0x93E, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x905, second: 0x945, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x905, second: 0x946, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x905, second: 0x949, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x905, second: 0x94A, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x905, second: 0x94B, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x905, second: 0x94C, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x905, second: 0x94F, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x905, second: 0x956, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x905, second: 0x957, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x906, second: 0x93A, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x906, second: 0x945, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x906, second: 0x946, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x906, second: 0x947, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x906, second: 0x948, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x909, second: 0x941, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x90F, second: 0x945, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x90F, second: 0x946, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x90F, second: 0x947, third: 0x0, length: 2 },
		{ script: 0x44657661, first: 0x930, second: 0x94D, third: 0x907, length: 3 },
		{ script: 0x47756A72, first: 0xA85, second: 0xABE, third: 0x0, length: 2 },
		{ script: 0x47756A72, first: 0xA85, second: 0xAC5, third: 0x0, length: 2 },
		{ script: 0x47756A72, first: 0xA85, second: 0xAC7, third: 0x0, length: 2 },
		{ script: 0x47756A72, first: 0xA85, second: 0xAC8, third: 0x0, length: 2 },
		{ script: 0x47756A72, first: 0xA85, second: 0xAC9, third: 0x0, length: 2 },
		{ script: 0x47756A72, first: 0xA85, second: 0xACB, third: 0x0, length: 2 },
		{ script: 0x47756A72, first: 0xA85, second: 0xACC, third: 0x0, length: 2 },
		{ script: 0x47756A72, first: 0xAC5, second: 0xABE, third: 0x0, length: 2 },
		{ script: 0x47757275, first: 0xA05, second: 0xA3E, third: 0x0, length: 2 },
		{ script: 0x47757275, first: 0xA05, second: 0xA48, third: 0x0, length: 2 },
		{ script: 0x47757275, first: 0xA05, second: 0xA4C, third: 0x0, length: 2 },
		{ script: 0x47757275, first: 0xA72, second: 0xA3F, third: 0x0, length: 2 },
		{ script: 0x47757275, first: 0xA72, second: 0xA40, third: 0x0, length: 2 },
		{ script: 0x47757275, first: 0xA72, second: 0xA47, third: 0x0, length: 2 },
		{ script: 0x47757275, first: 0xA73, second: 0xA41, third: 0x0, length: 2 },
		{ script: 0x47757275, first: 0xA73, second: 0xA42, third: 0x0, length: 2 },
		{ script: 0x47757275, first: 0xA73, second: 0xA4B, third: 0x0, length: 2 },
		{ script: 0x4B686F6A, first: 0x11200, second: 0x1122C, third: 0x0, length: 2 },
		{ script: 0x4B686F6A, first: 0x11200, second: 0x11231, third: 0x0, length: 2 },
		{ script: 0x4B686F6A, first: 0x11200, second: 0x11233, third: 0x0, length: 2 },
		{ script: 0x4B686F6A, first: 0x11206, second: 0x1122C, third: 0x0, length: 2 },
		{ script: 0x4B686F6A, first: 0x1122C, second: 0x11230, third: 0x0, length: 2 },
		{ script: 0x4B686F6A, first: 0x1122C, second: 0x11231, third: 0x0, length: 2 },
		{ script: 0x4B686F6A, first: 0x11240, second: 0x1122E, third: 0x0, length: 2 },
		{ script: 0x4B6E6461, first: 0xC89, second: 0xCBE, third: 0x0, length: 2 },
		{ script: 0x4B6E6461, first: 0xC8B, second: 0xCBE, third: 0x0, length: 2 },
		{ script: 0x4B6E6461, first: 0xC92, second: 0xCCC, third: 0x0, length: 2 },
		{ script: 0x4D6C796D, first: 0xD07, second: 0xD57, third: 0x0, length: 2 },
		{ script: 0x4D6C796D, first: 0xD09, second: 0xD57, third: 0x0, length: 2 },
		{ script: 0x4D6C796D, first: 0xD0E, second: 0xD46, third: 0x0, length: 2 },
		{ script: 0x4D6C796D, first: 0xD12, second: 0xD3E, third: 0x0, length: 2 },
		{ script: 0x4D6C796D, first: 0xD12, second: 0xD57, third: 0x0, length: 2 },
		{ script: 0x4D6F6469, first: 0x11600, second: 0x11639, third: 0x0, length: 2 },
		{ script: 0x4D6F6469, first: 0x11600, second: 0x1163A, third: 0x0, length: 2 },
		{ script: 0x4D6F6469, first: 0x11601, second: 0x11639, third: 0x0, length: 2 },
		{ script: 0x4D6F6469, first: 0x11601, second: 0x1163A, third: 0x0, length: 2 },
		{ script: 0x4F727961, first: 0xB05, second: 0xB3E, third: 0x0, length: 2 },
		{ script: 0x4F727961, first: 0xB0F, second: 0xB57, third: 0x0, length: 2 },
		{ script: 0x4F727961, first: 0xB13, second: 0xB57, third: 0x0, length: 2 },
		{ script: 0x53696E64, first: 0x112B0, second: 0x112E0, third: 0x0, length: 2 },
		{ script: 0x53696E64, first: 0x112B0, second: 0x112E5, third: 0x0, length: 2 },
		{ script: 0x53696E64, first: 0x112B0, second: 0x112E6, third: 0x0, length: 2 },
		{ script: 0x53696E64, first: 0x112B0, second: 0x112E7, third: 0x0, length: 2 },
		{ script: 0x53696E64, first: 0x112B0, second: 0x112E8, third: 0x0, length: 2 },
		{ script: 0x53696E68, first: 0xD85, second: 0xDCF, third: 0x0, length: 2 },
		{ script: 0x53696E68, first: 0xD85, second: 0xDD0, third: 0x0, length: 2 },
		{ script: 0x53696E68, first: 0xD85, second: 0xDD1, third: 0x0, length: 2 },
		{ script: 0x53696E68, first: 0xD8B, second: 0xDDF, third: 0x0, length: 2 },
		{ script: 0x53696E68, first: 0xD8D, second: 0xDD8, third: 0x0, length: 2 },
		{ script: 0x53696E68, first: 0xD8F, second: 0xDDF, third: 0x0, length: 2 },
		{ script: 0x53696E68, first: 0xD91, second: 0xDCA, third: 0x0, length: 2 },
		{ script: 0x53696E68, first: 0xD91, second: 0xDD9, third: 0x0, length: 2 },
		{ script: 0x53696E68, first: 0xD91, second: 0xDDA, third: 0x0, length: 2 },
		{ script: 0x53696E68, first: 0xD91, second: 0xDDC, third: 0x0, length: 2 },
		{ script: 0x53696E68, first: 0xD91, second: 0xDDD, third: 0x0, length: 2 },
		{ script: 0x53696E68, first: 0xD91, second: 0xDDE, third: 0x0, length: 2 },
		{ script: 0x53696E68, first: 0xD94, second: 0xDDF, third: 0x0, length: 2 },
		{ script: 0x54616B72, first: 0x11680, second: 0x116AD, third: 0x0, length: 2 },
		{ script: 0x54616B72, first: 0x11680, second: 0x116B4, third: 0x0, length: 2 },
		{ script: 0x54616B72, first: 0x11680, second: 0x116B5, third: 0x0, length: 2 },
		{ script: 0x54616B72, first: 0x11686, second: 0x116B2, third: 0x0, length: 2 },
		{ script: 0x54616D6C, first: 0xB85, second: 0xBC2, third: 0x0, length: 2 },
		{ script: 0x54656C75, first: 0xC12, second: 0xC4C, third: 0x0, length: 2 },
		{ script: 0x54656C75, first: 0xC12, second: 0xC55, third: 0x0, length: 2 },
		{ script: 0x54656C75, first: 0xC3F, second: 0xC55, third: 0x0, length: 2 },
		{ script: 0x54656C75, first: 0xC46, second: 0xC55, third: 0x0, length: 2 },
		{ script: 0x54656C75, first: 0xC4A, second: 0xC55, third: 0x0, length: 2 },
		{ script: 0x54697268, first: 0x11481, second: 0x114B0, third: 0x0, length: 2 },
		{ script: 0x54697268, first: 0x1148B, second: 0x114BA, third: 0x0, length: 2 },
		{ script: 0x54697268, first: 0x1148D, second: 0x114BA, third: 0x0, length: 2 },
		{ script: 0x54697268, first: 0x114AA, second: 0x114B5, third: 0x0, length: 2 },
		{ script: 0x54697268, first: 0x114AA, second: 0x114B6, third: 0x0, length: 2 },
	]
	no_rule : Rule
	no_rule = { script: 0, first: 0, second: 0, third: 0, length: 0 }

	has_script : U64 -> Bool
	has_script = |script| ShaperIndicVowelData.rules.any(|rule| rule.script == script)

	length : U64, U64, U64, U64 -> U64
	length = |script, first, second, third| {
		var $lo = 0
		var $hi = ShaperIndicVowelData.rules.len()
		while $lo < $hi {
			mid = $lo + ($hi - $lo) // 2
			rule = ShaperIndicVowelData.rules.get(mid) ?? ShaperIndicVowelData.no_rule
			less = rule.script < script or (rule.script == script and (rule.first < first or (rule.first == first and rule.second < second)))
			if less {
				$lo = mid + 1
			} else {
				$hi = mid
			}
		}
		var $found = 0
		var $i = $lo
		var $search = True
		while $i < ShaperIndicVowelData.rules.len() and $search {
			rule = ShaperIndicVowelData.rules.get($i) ?? ShaperIndicVowelData.no_rule
			if rule.script != script or rule.first != first or rule.second != second {
				$search = False
			}
			else {
				if rule.length == 2 or rule.third == third {
					$found = rule.length
				}
				$i = $i + 1
			}
		}
		$found
	}
}
