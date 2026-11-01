# MoonSparql

MoonSparql is a bounded, in-process RDF query engine written in MoonBit.
It extends existing RDF IO libraries with query execution: joins, optional facts,
aggregates and paths return bindings or a derived graph.

This is a local development repository. The temporary private module is
`local/moonsparql`. The owner will choose the publication account and repository.
No public package installation command is claimed before publication.

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

## Library use

Import `"local/moonsparql" @q` in a package in this checkout. After the owner
sets the publication namespace, replace this temporary import accordingly.

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

## Supported release profile

SELECT, ASK and CONSTRUCT; PREFIX with absolute IRIs; BGP, OPTIONAL, UNION,
MINUS, FILTER, BIND, VALUES and GRAPH; inverse/sequence/alternative/*/+/? paths;
DISTINCT, GROUP BY, HAVING, COUNT/SUM/AVG/MIN/MAX/SAMPLE, ORDER BY, OFFSET/LIMIT.
See [the exact profile](docs/PROFILE.md) for limitations and expression functions.

This is an explicit subset of SPARQL 1.1, not a claim of full conformance.
SERVICE, UPDATE, DESCRIBE, subqueries, entailment and remote loading are excluded.
Unsupported syntax is rejected. Exhausted budgets fail the query without
returning a partial-success table.

## Ecosystem integration and sources

MoonTTL provides RDF parsing and materialization. MoonSHACL validates RDF
contracts and JSON-LD supplies linked-data interchange. MoonSparql adds query
execution over RDF datasets; it does not replace those packages. The dated
topic-search evidence and contest materials are stored outside public Git.

Apache-2.0. Dependency sources, AI assistance and original fixture provenance
are recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
Architecture and costs: [docs/architecture.md](docs/architecture.md).


## 十一月新增功能

**精确前置条件的原子数据补丁**（`Dataset::apply_patch`）；**SELECT结果多重集变化分析**（`QueryResult::binding_delta`）。详见[功能、用途和边界](docs/NOVEMBER_FEATURES.md)，运行 `moon run examples/november --target native --deny-warn`。当前仍为本地未发布源码，不提供虚构安装地址。
