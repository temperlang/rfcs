# Labels after panics: generated summary

Written by analyze.py; see ../README.md.

| Library | Labeled today (exported / private) | Labeled after (exported / private) | Private after, via calls only | After, bounds | After, if bug-like `bubble()`s panic too | `orelse panic()` gone / total |
|---|---|---|---|---|---|---|
| Argmas | 8 (1 / 7) | 7 (1 / 6) | 0 | 7 to 7 | 7 (1 / 6) | 12 / 15 |
| Chromarite | 52 (3 / 49) | 38 (3 / 35) | 16 | 26 to 38 | 21 (1 / 20) | 33 / 67 |
| Hrefine | 24 (10 / 14) | 23 (10 / 13) | 2 | 23 to 23 | 23 (10 / 13) | 3 / 91 |
| Kelpto | 49 (25 / 24) | 49 (25 / 24) | 4 | 49 to 49 | 49 (25 / 24) | 216 / 293 |
| Ordable | 0 (0 / 0) | 0 (0 / 0) | 0 | 0 to 0 | 0 (0 / 0) | 13 / 13 |
| Wherewith | 104 (7 / 97) | 104 (7 / 97) | 68 | 104 to 104 | 104 (7 / 97) | 6 / 9 |
| std | 37 (29 / 8) | 25 (19 / 6) | 4 | 13 to 29 | 20 (15 / 5) | 12 / 12 |
| core | 15 (14 / 1) | 6 (5 / 1) | 0 | 6 to 6 | 6 (5 / 1) | 1 / 1 |
| All | 289 (89 / 200) | 252 (70 / 182) | 94 | 228 to 256 | 230 (64 / 166) | 296 / 501 |

- orelse panic() outside tests: 213, gone 163
- orelse panic() gone if bug-like bubble()s panic too: 329
- orelse panic() gone, pessimistic to optimistic: 294 to 330
- other orelse: 95, operand no longer fails (best): 17
- orelse with no failure source found in the operand: 2
- labeled functions with a body but no unhandled source found: 9: Argmas:StringType.parse (override), Chromarite:adjustLch, Chromarite:lchIn, Chromarite:assertConvertColors, std:JsonInt32.asInt32 (override), std:JsonInt32.asInt64 (override), std:JsonInt32.asFloat64 (override), std:JsonInt64.asInt64 (override), std:JsonFloat64.asFloat64 (override)
- labeled function types (not counted): 3: std:testing.temper.md:110, core:core.temper:257, core:core.temper:260
- overrides that can't fail of still-labeled interface methods: 12: Argmas:StringType.parse, std:JsonInt32.asInt32, std:JsonInt32.asInt64, std:JsonInt32.asFloat64, std:JsonInt64.asInt32, std:JsonInt64.asInt64, std:JsonInt64.asFloat64, std:JsonFloat64.asInt32, std:JsonFloat64.asInt64, std:JsonFloat64.asFloat64, std:BooleanJsonAdapter.decodeFromJson, std:StringJsonAdapter.decodeFromJson
- unhandled calls in labeled functions whose outcome depends on the target: 25 at 22 (function, name) pairs

## Ambiguous calls in labeled functions, by target

- Argmas FloatType.parse -> toFloat64 x1: labeled in [Int64,String], plus 1 unlabeled; best: String
- Argmas Int64Type.parse -> toInt64 x1: labeled in [Float64,String], plus 1 unlabeled; best: String
- Argmas IntType.parse -> toInt32 x1: labeled in [Float64,Int64,String], plus 0 unlabeled; best: String
- Chromarite gradientColors -> toFloat64 x4: labeled in [Int64,String], plus 1 unlabeled; best: -
- Chromarite parseHex -> toFloat64 x1: labeled in [Int64,String], plus 1 unlabeled; best: -
- Chromarite toNumber -> toFloat64 x1: labeled in [Int64,String], plus 1 unlabeled; best: String
- Wherewith StatementChecker.count -> toInt64 x1: labeled in [Float64,String], plus 1 unlabeled; best: -
- Wherewith StatementChecker.statement -> statement x1: labeled in [NameCases,StatementChecker], plus 1 unlabeled; best: NameCases
- std Float64JsonAdapter.decodeFromJson -> asFloat64 x1: labeled in [JsonFloat64,JsonInt32,JsonInt64,JsonNumeric,JsonNumericToken], plus 0 unlabeled; best: JsonNumeric
- std Int32JsonAdapter.decodeFromJson -> asInt32 x1: labeled in [JsonFloat64,JsonInt32,JsonInt64,JsonNumeric,JsonNumericToken], plus 0 unlabeled; best: JsonNumeric
- std Int64JsonAdapter.decodeFromJson -> asInt64 x1: labeled in [JsonFloat64,JsonInt32,JsonInt64,JsonNumeric,JsonNumericToken], plus 0 unlabeled; best: JsonNumeric
- std JsonFloat64.asInt32 -> toInt32 x1: labeled in [Float64,Int64,String], plus 0 unlabeled; best: Float64
- std JsonFloat64.asInt64 -> toInt64 x1: labeled in [Float64,String], plus 1 unlabeled; best: Float64
- std JsonInt64.asFloat64 -> toFloat64 x1: labeled in [Int64,String], plus 1 unlabeled; best: Int64
- std JsonInt64.asInt32 -> toInt32 x1: labeled in [Float64,Int64,String], plus 0 unlabeled; best: Int64
- std JsonNumericToken.asFloat64 -> toFloat64 x1: labeled in [Int64,String], plus 1 unlabeled; best: String
- std JsonNumericToken.asInt32 -> toFloat64 x1: labeled in [Int64,String], plus 1 unlabeled; best: String
- std JsonNumericToken.asInt32 -> toInt32 x1: labeled in [Float64,Int64,String], plus 0 unlabeled; best: Float64
- std JsonNumericToken.asInt64 -> toFloat64 x1: labeled in [Int64,String], plus 1 unlabeled; best: String
- std JsonNumericToken.asInt64 -> toInt64 x1: labeled in [Float64,String], plus 1 unlabeled; best: Float64
- std ListJsonAdapter.decodeFromJson -> decodeFromJson x1: labeled in [BooleanJsonAdapter,Date,Float64JsonAdapter,Int32JsonAdapter,Int64JsonAdapter,JsonAdapter,ListJsonAdapter,OrNullJsonAdapter,StringJsonAdapter], plus 0 unlabeled; best: JsonAdapter
- std OrNullJsonAdapter.decodeFromJson -> decodeFromJson x1: labeled in [BooleanJsonAdapter,Date,Float64JsonAdapter,Int32JsonAdapter,Int64JsonAdapter,JsonAdapter,ListJsonAdapter,OrNullJsonAdapter,StringJsonAdapter], plus 0 unlabeled; best: JsonAdapter

## Ambiguous calls in orelse operands (outside labeled functions too)

- Argmas Counter.read -> parse x1: labeled in [ChoiceType,FloatType,Int64Type,IntType,StringType,ValueType]; best: ValueType
- Argmas MaybeValue.read -> parse x1: labeled in [ChoiceType,FloatType,Int64Type,IntType,StringType,ValueType]; best: ValueType
- Argmas Parser.readEnvironment -> parse x1: labeled in [ChoiceType,FloatType,Int64Type,IntType,StringType,ValueType]; best: ValueType
- Argmas TypeChecker.accepts -> parse x1: labeled in [ChoiceType,FloatType,Int64Type,IntType,StringType,ValueType]; best: ValueType
- Argmas Value.read -> parse x1: labeled in [ChoiceType,FloatType,Int64Type,IntType,StringType,ValueType]; best: ValueType
- Argmas Values.read -> parse x1: labeled in [ChoiceType,FloatType,Int64Type,IntType,StringType,ValueType]; best: ValueType
- Argmas completionRequest -> parse x1: labeled in [ChoiceType,FloatType,Int64Type,IntType,StringType,ValueType]; best: ValueType
- Argmas looksLikeNumber -> parse x1: labeled in [ChoiceType,FloatType,Int64Type,IntType,StringType,ValueType]; best: ValueType
- Chromarite intToUnit -> toFloat64 x3: labeled in [Int64,String]; best: -
- Hrefine parseSpecialHosts -> toInt32 x1: labeled in [Float64,Int64,String]; best: String
- Kelpto <top> -> remove x19: labeled in [MapBuilder,MarkdownEditor]; best: MarkdownEditor
- Kelpto <top> -> replace x2: labeled in [MarkdownEditor]; best: MarkdownEditor
- Kelpto <top> -> toDocument x8: labeled in [MarkdownEditor]; best: MarkdownEditor
- Kelpto <top> -> withContent x2: labeled in [Paragraph]; best: Paragraph
- Kelpto <top> -> withText x1: labeled in [Paragraph]; best: Paragraph
- Kelpto editedWith -> toDocument x1: labeled in [MarkdownEditor]; best: MarkdownEditor
- Wherewith commonCheck -> statement x1: labeled in [NameCases,StatementChecker]; best: StatementChecker
- std JsonNumericToken.asInt32 -> toInt32 x1: labeled in [Float64,Int64,String]; best: Float64
- std JsonNumericToken.asInt64 -> toInt64 x1: labeled in [Float64,String]; best: Float64
- std parseJsonNumber -> toFloat64 x4: labeled in [Int64,String]; best: -
- std parseJsonNumber -> toInt64 x3: labeled in [Float64,String]; best: -

## Sample (seed 164)

- Chromarite chromarite/src/matrix.temper.md:50 Matrix.get [private] after=1 (direct) via=[]
- Wherewith wherewith/src/common-expressions.temper.md:812 CommonParser.expectSymbol [private] after=1 (direct) via=[]
- Kelpto kelpto/kelpto-md/walk.temper.md:322 MarkdownEditor.remove [exported] after=1 (calls) via=['blockEditOf']
- std tempest/lib/std/json/json.temper.md:212 JsonObject.propertyValueOrBubble [exported] after=0 (calls) via=[]
- std tempest/lib/std/json/json.temper.md:343 JsonNumericToken.asInt32 [exported] after=1 (direct) via=['String.toFloat64']
- Wherewith wherewith/src/common-statements.temper.md:756 StatementChecker.subquery [private] after=1 (calls) via=['StatementChecker.scoped']
- Hrefine hrefine/src/host.temper.md:103 runHostParser [private] after=1 (direct) via=['parseDomain', 'parseIpv6', 'parseOpaqueHost']
- Chromarite chromarite/src/helpers.temper.md:37 assertConvertColors [private] after=0 (calls) via=[]
- Wherewith wherewith/src/common-statements.temper.md:1140 StatementChecker.itemNames [private] after=1 (calls) via=['CommonChecker.fail', 'StatementChecker.itemNameRefs']
- Wherewith wherewith/src/common-statements.temper.md:882 StatementChecker.derived [private] after=1 (calls) via=['CommonChecker.fail']
- Argmas argmas/src/values.temper.md:87 Int64Type.parse [private] after=1 (direct) via=['String.toInt64', 'integerText']
- Kelpto kelpto/kelpto-md/edit.temper.md:179 firstNodeOf [private] after=1 (direct) via=[]
- Hrefine hrefine/src/url.temper.md:41 checkUrl [exported] after=1 (calls) via=['parseRecord']
- Wherewith wherewith/src/common-expressions.temper.md:831 CommonParser.deep [private] after=1 (direct) via=[]
- Wherewith wherewith/src/common-expressions.temper.md:1195 CommonChecker.like [private] after=1 (calls) via=['CommonChecker.check', 'CommonChecker.escaped', 'CommonChecker.fail', 'CommonChecker.textual']
- Chromarite chromarite/src/mix.temper.md:187 Blend.fixHues [private] after=0 (calls) via=[]
- Wherewith wherewith/src/core.temper.md:133 Dialect.quoteName [exported] after=1 (direct) via=[]
- Chromarite chromarite/src/gamut.temper.md:159 lchIn [private] after=0 (calls) via=[]
- core tempest/lib/core/core.temper:1167 Mapped.get [exported] after=0 (calls) via=[]
- Chromarite chromarite/src/rgb.temper.md:46 parseHex [private] after=1 (direct) via=['hexDigit']
