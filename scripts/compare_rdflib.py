"""Independent CLI comparison on the common supported semantic domain.

Install rdflib==7.6.0 in an ignored development venv, build the Native CLI,
then pass its executable path. Aggregate-error cases are intentionally tested
against W3C semantics in MoonBit tests, not RDFLib's error-dropping behavior.
"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import rdflib

rdflib.NORMALIZE_LITERALS = False
data = '''@prefix e: <urn:e:> .
e:a e:kind e:Asset .
e:b e:kind e:Asset .
e:a e:owner "Alice" .
e:a e:value 10 .
e:b e:value 20 .
e:a e:depends e:b .
e:b e:depends e:c .
'''
queries = [
    'SELECT ?s WHERE {?s <urn:e:kind> <urn:e:Asset>} ORDER BY ?s',
    'SELECT ?s ?owner WHERE {?s <urn:e:kind> ?k OPTIONAL {?s <urn:e:owner> ?owner}} ORDER BY ?s',
    'SELECT ?s WHERE {?s <urn:e:value> ?n FILTER(?n>15)}',
    'SELECT ?s WHERE {{?s <urn:e:owner> ?o} UNION {?s <urn:e:owner> ?o}}',
    'SELECT ?x WHERE {VALUES ?x {1 1 UNDEF}}',
    'SELECT DISTINCT ?k WHERE {?s <urn:e:kind> ?k}',
    'SELECT ?s WHERE {?s <urn:e:kind> ?k MINUS {?s <urn:e:owner> ?o}}',
    'SELECT ?v WHERE {<urn:e:a> <urn:e:depends>+ ?v} ORDER BY ?v',
    'SELECT ?v WHERE {?v ^<urn:e:depends> <urn:e:a>}',
    'SELECT (?n+1 AS ?next) WHERE {?s <urn:e:value> ?n} ORDER BY DESC(?next) LIMIT 1',
    'SELECT (COUNT(*) AS ?n) (SUM(?v) AS ?s) WHERE {?x <urn:e:value> ?v}',
    'SELECT ?k (COUNT(*) AS ?n) WHERE {?s <urn:e:kind> ?k} GROUP BY ?k',
    'SELECT (STRLEN("α🙂") AS ?n) WHERE {}',
    'SELECT (IF(true,1,1/0) AS ?n) WHERE {}',
    'ASK WHERE {<urn:e:a> <urn:e:depends>+ <urn:e:c>}',
]

def normalize(document):
    if "boolean" in document:
        return document["boolean"]
    rows = []
    for row in document["results"]["bindings"]:
        converted = {}
        for variable, term in row.items():
            term = term.copy()
            if term["type"] == "literal" and "xml:lang" not in term:
                term.setdefault("datatype", str(rdflib.XSD.string))
            converted[variable] = term
        rows.append(json.dumps(converted, sort_keys=True, ensure_ascii=False))
    # Compare bags independently of implementation-specific stable order.
    return sorted(rows)

executable = str(Path(sys.argv[1]).resolve())
graph = rdflib.Graph().parse(data=data, format="turtle")
with tempfile.TemporaryDirectory() as directory:
    folder = Path(directory)
    rdf_file, query_file = folder / "data.ttl", folder / "query.rq"
    rdf_file.write_text(data, encoding="utf-8")
    for index, query in enumerate(queries):
        query_file.write_text(query, encoding="utf-8")
        actual = subprocess.check_output(
            [executable, str(rdf_file), str(query_file), "json"], encoding="utf-8"
        )
        expected = graph.query(query).serialize(format="json")
        assert normalize(json.loads(actual)) == normalize(json.loads(expected)), (index, query, actual, expected)
print(f"{len(queries)} independent RDFLib comparisons passed")
