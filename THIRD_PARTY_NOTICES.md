# Sources and licenses

- Original MoonBit query implementation, assisted by AI and subject to owner
  review. No implementation is copied from RDFLib, Jena, Oxigraph or other query
  engines. Synthetic examples and test facts are authored for this repository.
- SPARQL syntax and semantics are informed by the W3C Recommendation:
  https://www.w3.org/TR/sparql11-query/ . Normative prose is referenced, not copied.
- RDF input uses `thy1016/moonttl@0.3.0` (Apache-2.0):
  https://www.gitlink.org.cn/thy7/mbt.ttl . Its parser is a dependency, not an
  original contribution claimed by this project.
- The SPARQL hash functions use the MD5, SHA-1 and SHA-2 packages in [moonbitstack/mooncrypt 0.3.1](https://github.com/moonbitstack/mooncrypt), licensed under Apache-2.0.
- MoonBit core, async and quickcheck are Apache-2.0. The latter module versions
  are explicitly selected for current toolchain compatibility; query execution
  does not use a network service or async runtime.
- The Windows path adapter, if needed, is generic local tooling originally
  developed in the owner's MoonUriTemplate repository, not query engine code.
- RDFLib 7.6.0 (BSD-3-Clause) and pyparsing 3.3.3 (MIT) are separately installed
  development-only dependencies for 15 CLI comparisons on the common supported
  domain. Their implementation is not copied, translated, bundled or required
  by the MoonBit runtime. Aggregate-error and other deliberate profile
  differences are verified by MoonBit semantic tests instead of treating the
  oracle as universal SPARQL conformance authority.
- The W3C compatibility runner uses the separate
  [W3C RDF test suites](https://github.com/w3c/rdf-tests) checkout at
  `202a74eb81f47bcad13bbafdd37eba69c361c1c2`. The fixtures are covered by the
  [W3C test suite licenses](https://www.w3.org/Consortium/Legal/2008/04-testsuite-copyright.html).
  They are fetched into an ignored build directory. The MoonSparql repository
  and package contain the runner and the case baseline.
- Relative IRI resolution follows the hierarchical resolution model in
  [RFC 3986 Section 5](https://www.rfc-editor.org/rfc/rfc3986#section-5).
