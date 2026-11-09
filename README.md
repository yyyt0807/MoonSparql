# MoonSparql

MoonSparql is a bounded, in-process RDF query engine written in MoonBit.
It extends existing RDF IO libraries with query execution: joins, optional facts,
aggregates and paths return bindings or a derived graph.

Install `yyyt0807/moonsparql@0.2.0` from Mooncakes. The source is maintained at
[yyyt0807/MoonSparql](https://github.com/yyyt0807/MoonSparql).
Repository owner and maintenance commit identity: `yyyt0807`.

```sh
moon add yyyt0807/moonsparql@0.2.0
```

## Run

Requires MoonBit 0.10.16 or newer and a C compiler for the Native CLI.

```sh
moon update
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
moon run examples/asset_inventory --target native
moon run examples/catalog_discovery --target native
moon run examples/research_summary --target native
moon run examples/scale --target native --release
moon run cmd/main --target native -- examples/data/catalog.ttl examples/data/catalog.rq json
```

On Windows, Moon 20261016 may pass extended DOS paths rejected by its OCaml
compiler. Run `./tools/windows/moon.ps1` instead of `moon` for these commands;
the adapter builds with MSVC and invokes the installed official compiler.
It changes process-local overrides only.

CI uses the validated official compiler/core pair `0.10.16+b1a0e846e` on
Ubuntu and Windows. For independent common-profile verification after building
the Native CLI:

```sh
python -m venv .venv
# Activate the environment; on Windows use .venv/Scripts/python.exe.
python -m pip install -r scripts/requirements-interop.txt
python scripts/compare_rdflib.py _build/native/debug/build/cmd/main/main.exe
```

The 15 RDFLib comparisons cover shared semantics only; they do not certify
the full SPARQL standard. Python is a development oracle, not a runtime
requirement. `scripts/verify_repository.py` checks real source/history and
excludes private contest material from tracked paths and package ZIPs.

## Library use

Import the module in the consuming package's `moon.pkg`:

```text
import { "yyyt0807/moonsparql" @q, }
```

```moonbit
let data = @q.Dataset::from_turtle(
  "<urn:item> <urn:owner> \"Alice\" .",
)
let query = @q.prepare("SELECT ?owner {<urn:item> <urn:owner> ?owner}")
let result = query.execute(data)
assert_eq(result.rows()[0].get("owner").unwrap().lexical(), "Alice")
println(result.to_json())
```

Programmatic datasets use `iri`, `blank`, `literal`, `typed_literal`,
`language_literal`, `quad` and `Dataset::from_quads`. Named graphs are
available through that API. Datasets copy input collections and return copies;
bindings expose lookup and variable names without mutable internal maps.

## Three complete applications

- Asset impact: join ownership facts with transitive dependencies, retaining
  assets whose optional owner is missing. This supports inventories, software
  catalogs, equipment maintenance and change planning.
- Metadata discovery: combine catalog topic and publisher facts with VALUES
  restrictions. This supports datasets, documents, product catalogs and
  institutional metadata.
- Research summaries: group observations by site, calculate exact SUM/AVG,
  filter groups and construct a derived RDF view. This supports research,
  public data and reusable analytical metadata.

Each example contains assertions for its outputs. The 10,000-fact scale example
verifies indexed lookup work and an exact aggregate, without claiming a timing
advantage over another engine.

## Query compatibility in 0.2.0

MoonSparql supports SELECT subqueries, EXISTS and NOT EXISTS,
negated property sets, GROUP_CONCAT, GROUP BY aliases, trailing VALUES, and
local FROM and FROM NAMED datasets. Extended string and date-time builtins and
selected datatype casts are documented with their limits in the
[query profile](docs/PROFILE.md).

The pinned W3C suite runs 236 query evaluations. The release checks show 219 passes
and 17 documented unsupported-function cases. Coverage and reproduction
commands appear in the [query profile](docs/PROFILE.md).

Three interfaces support integration in this release.

- `Dataset::from_documents` assembles independent RDF sources with named and
  empty graph support. The Native CLI accepts the same catalogue with
  `--dataset DATA.json QUERY.rq json|tsv|rdf`.
- `PreparedQuery::profile` and CLI `--inspect QUERY.rq` expose static
  projection, data-source IRIs and subquery, existence, path and aggregate
  counts for validation tools and local catalogues.
- `CONSTRUCT WHERE` exports the matched RDF subgraph for catalogue snapshots,
  metadata exchange and downstream graph processing.

```sh
moon run examples/compatibility --target native --deny-warn
moon run cmd/main --target native -- --inspect examples/data/catalog.rq
python scripts/check_w3c.py _build/native/debug/build/cmd/main/main.exe --fetch
```

The example joins a release catalogue with an advisory graph, aggregates the
eligible versions and exports a version subgraph.

## Ecosystem integration and sources

MoonTTL provides RDF parsing and materialization. MoonSHACL validates RDF
contracts and JSON-LD supplies linked-data interchange. MoonSparql adds query
execution over RDF datasets; it does not replace those packages. The dated
topic-search evidence and contest materials are stored outside public Git.

Apache-2.0. Dependency sources, AI assistance and original fixture provenance
are recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
Architecture and costs: [docs/architecture.md](docs/architecture.md).


## 十一月新增功能

**精确前置条件的原子数据补丁**（`Dataset::apply_patch`）；**SELECT结果多重集变化分析**（`QueryResult::binding_delta`）。详见[功能、用途和边界](docs/NOVEMBER_FEATURES.md)，运行 `moon run examples/november --target native --deny-warn`。这些功能纳入 0.1.0 首次公开发布。


## RDF 数据集与结果合并

新增 **独立空白节点作用域的 RDF 合并**、**按列对齐的 SELECT 袋并集**，用途、限制和复杂度见 [功能文档](docs/EXPANSION_20261106.md)。
从本仓库源码运行 `moon run examples/expansion --target native --deny-warn`。
这两项 API 自 0.2.0 起可用。
