# MoonSparql

A bounded, in-process RDF query engine in MoonBit. The project extends RDF
read/write libraries with query execution: related facts become variable
bindings, aggregate tables, or constructed RDF graphs.

Development is local. The temporary module is `local/moonsparql`; its account,
public repository and Mooncakes publication will be set by the owner later.

The intended release profile is documented in `docs/PROFILE.md`. Features are
only described as implemented after their code and tests land.

## Intended applications

- Join asset ownership, dependency and support facts to identify affected assets.
- Query catalog metadata across datasets, publications and responsible teams.
- Summarize research observations and build derived, traceable RDF views.

## Development

Requires MoonBit 0.10.16 or newer. The engine uses no network, clock or storage
service. MoonTTL is the RDF input integration; it is not reimplemented here.

```sh
moon update
moon check
moon test
```

Apache-2.0. See `THIRD_PARTY_NOTICES.md` for dependency and specification sources.
