| Library | Sites | Public | Internal | Library calls | Builtins | `/` `%` | `as` | Functions with a site / bubbling functions |
|---|---|---|---|---|---|---|---|---|
| Argmas | 5 | 0 | 5 | 2 | 3 | 0 | 0 | 3 / 7 |
| Chromarite | 140 | 2 | 138 | 119 | 2 | 19 | 0 | 38 / 52 |
| Hrefine | 36 | 10 | 26 | 26 | 0 | 10 | 0 | 19 / 24 |
| Kelpto | 52 | 30 | 22 | 52 | 0 | 0 | 0 | 35 / 49 |
| Ordable | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 / 0 |
| Wherewith | 365 | 1 | 364 | 365 | 0 | 0 | 0 | 89 / 104 |
| std | 32 | 22 | 10 | 12 | 13 | 0 | 7 | 22 / 32 |
| **All** | **630** | **65** | **565** | 576 | 18 | 29 | 7 | 206 / 268 |

tail calls (no `?` in Rust): 82

206 functions with sites; total 630
top 1: 28 (4%)
top 3: 63 (10%)
top 5: 93 (15%)
top 10: 149 (24%)
top 20: 224 (36%)
functions holding half the sites: 37
distribution (sites per function: count): [(1, 89), (2, 37), (3, 21), (4, 22), (5, 10), (6, 8), (7, 7), (10, 3), (11, 2), (12, 2), (14, 1), (16, 1), (17, 1), (18, 1), (28, 1)]

Top 15:
| Wherewith | `CommonChecker.check` | internal | 28 |
| Wherewith | `StatementChecker.select` | internal | 18 |
| Chromarite | `fitContrastRows` | internal | 17 |
| Wherewith | `StatementParser.select` | internal | 16 |
| Wherewith | `CommonChecker.call` | internal | 14 |
| Chromarite | `parseCssColor` | internal | 12 |
| Wherewith | `CommonChecker.binary` | internal | 12 |
| Wherewith | `CommonParser.primary` | internal | 11 |
| Wherewith | `NameCases.statement` | internal | 11 |
| Wherewith | `CommonChecker.caseKind` | internal | 10 |
| Wherewith | `StatementParser.insert` | internal | 10 |
| Wherewith | `NameCases.select` | internal | 10 |
| Chromarite | `mapToGamut` | internal | 7 |
| Chromarite | `gradientColors` | internal | 7 |
| Wherewith | `CommonParser.predicate` | internal | 7 |
Argmas: 3 functions, top 5 hold 5/5 (100%); max 2 in IntType.parse
Chromarite: 38 functions, top 5 hold 49/140 (35%); max 17 in .fitContrastRows
Hrefine: 19 functions, top 5 hold 19/36 (53%); max 6 in .punycodeDecode
Kelpto: 35 functions, top 5 hold 18/52 (35%); max 4 in .editAll
Wherewith: 89 functions, top 5 hold 88/365 (24%); max 28 in CommonChecker.check
std: 22 functions, top 5 hold 12/32 (38%); max 4 in Date.fromIsoString
