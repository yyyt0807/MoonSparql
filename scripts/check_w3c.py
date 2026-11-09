"""Execute pinned W3C SPARQL query fixtures against the Native CLI.

RDFLib reads manifests and RDF fixtures. It never executes the test queries.
Official queries are passed verbatim to MoonSparql; RDF input graphs are
serialized as explicit triples so the test isolates query semantics.
"""

import argparse
from collections import Counter
from decimal import Decimal, InvalidOperation
import json
from pathlib import Path
import subprocess
import tempfile
from urllib.parse import quote, urlsplit
from urllib.request import url2pathname
from xml.etree import ElementTree

from rdflib import BNode, Dataset, Graph, Literal, Namespace, RDF, RDFS, URIRef, XSD
import rdflib
from rdflib.compare import isomorphic

ROOT = Path(__file__).resolve().parents[1]
REVISION = "202a74eb81f47bcad13bbafdd37eba69c361c1c2"
REPOSITORY = "https://github.com/w3c/rdf-tests.git"
SUITES = {
    "sparql11": ("subquery", "exists", "negation", "property-path", "functions",
                 "aggregates", "grouping", "bindings", "construct"),
    "sparql10": ("dataset",),
}
MF = Namespace("http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#")
QT = Namespace("http://www.w3.org/2001/sw/DataAccess/tests/test-query#")
RS = Namespace("http://www.w3.org/2001/sw/DataAccess/tests/result-set#")
SRX = "{http://www.w3.org/2005/sparql-results#}"
rdflib.NORMALIZE_LITERALS = False


def checkout(root, fetch):
    if not root.exists() and fetch:
        root.mkdir(parents=True)
        subprocess.run(["git", "init", str(root)], check=True)
        subprocess.run(["git", "-C", str(root), "fetch", "--depth=1",
                        REPOSITORY, REVISION], check=True, timeout=180)
        subprocess.run(["git", "-C", str(root), "sparse-checkout", "init", "--cone"],
                       check=True)
        subprocess.run(["git", "-C", str(root), "sparse-checkout", "set",
                        "sparql/sparql11", "sparql/sparql10/dataset"], check=True)
        subprocess.run(["git", "-C", str(root), "checkout", "--detach", "FETCH_HEAD"],
                       check=True)
    head = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True
    ).strip()
    if head != REVISION:
        raise ValueError(f"W3C checkout must be {REVISION}, got {head}")


def local_file(uri, root):
    location = urlsplit(str(uri))
    if location.scheme != "file" or location.netloc or location.query or location.fragment:
        raise ValueError(f"fixture is not a local file: {uri}")
    path = Path(url2pathname(location.path)).resolve(strict=True)
    path.relative_to(root)
    return path


def rdf_graph(path):
    fmt = {".rdf": "xml", ".nt": "nt", ".ttl": "turtle"}[path.suffix.lower()]
    return Graph().parse(path, format=fmt, publicID=path.as_uri())


def query_manifest(action, manifest, query, root):
    default_graph = Graph()
    sources = {}
    named = {}
    for uri in manifest.objects(action, QT.data):
        path = local_file(uri, root)
        if path.suffix == ".trig":
            dataset = Dataset()
            dataset.parse(path, format="trig", publicID=path.as_uri())
            graph = dataset.default_graph
            for context in dataset.graphs():
                if context.identifier != graph.identifier:
                    named[str(context.identifier)] = context.serialize(format="nt")
        else:
            graph = rdf_graph(path)
        default_graph += graph
        sources[str(uri)] = graph.serialize(format="nt")
    for item in manifest.objects(action, QT.graphData):
        if isinstance(item, BNode):
            uri = manifest.value(item, QT.graph)
            label = manifest.value(item, RDFS.label)
            if uri is None or label is None:
                raise ValueError(f"malformed named-graph fixture in {query}")
        else:
            uri = label = item
        named[str(label)] = rdf_graph(local_file(uri, root)).serialize(format="nt")
    return {"base": query.as_uri(), "default": default_graph.serialize(format="nt"),
            "named": named, "sources": {k: v for k, v in sources.items() if k not in named}}


def literal(text, datatype=None, lang=None):
    if lang is not None:
        return Literal(text, lang=lang.lower(), normalize=False)
    datatype = URIRef(datatype) if datatype else XSD.string
    # Compare known numeric and Boolean values without converting datatypes or
    # allowing a tolerance. Unknown datatypes retain their lexical form.
    try:
        if datatype == XSD.integer:
            text = str(int(text))
        elif datatype == XSD.decimal:
            value = Decimal(text)
            if value.is_finite():
                text = format(value, "f")
                if "." in text:
                    text = text.rstrip("0").rstrip(".")
                if value == 0:
                    text = "0"
        elif datatype in (XSD.double, XSD.float):
            number = float(text)
            text = repr(0.0 if number == 0 else number)
        elif datatype == XSD.boolean:
            text = {"0": "false", "1": "true"}.get(text, text)
    except (InvalidOperation, ValueError, OverflowError):
        pass
    return Literal(text, datatype=datatype, normalize=False)


def normalized_term(term):
    if isinstance(term, Literal):
        return literal(str(term), term.datatype, term.language)
    return term


def json_result(document):
    if "boolean" in document:
        if type(document["boolean"]) is not bool:
            raise ValueError("non-Boolean ASK output")
        return document["boolean"]
    rows = []
    for binding in document["results"]["bindings"]:
        row = {}
        for variable, cell in binding.items():
            kind, text = cell["type"], cell["value"]
            if kind == "uri":
                row[variable] = URIRef(text)
            elif kind == "bnode":
                row[variable] = BNode(text)
            elif kind in ("literal", "typed-literal"):
                row[variable] = literal(text, cell.get("datatype"), cell.get("xml:lang"))
            else:
                raise ValueError(f"unexpected result term type {kind}")
        rows.append(row)
    return frozenset(document["head"]["vars"]), rows, False


def xml_result(path):
    xml = ElementTree.parse(path).getroot()
    answer = xml.find(SRX + "boolean")
    if answer is not None:
        return answer.text.strip() == "true"
    variables = frozenset(v.attrib["name"] for v in xml.findall(f"{SRX}head/{SRX}variable"))
    results = xml.find(SRX + "results")
    rows = []
    for item in results.findall(SRX + "result"):
        row = {}
        for binding in item.findall(SRX + "binding"):
            term = binding[0]
            text = term.text or ""
            if term.tag == SRX + "uri":
                value = URIRef(text)
            elif term.tag == SRX + "bnode":
                value = BNode(text)
            elif term.tag == SRX + "literal":
                value = literal(text, term.get("datatype"),
                                term.get("{http://www.w3.org/XML/1998/namespace}lang"))
            elif term.tag == SRX + "unbound":
                continue
            else:
                raise ValueError(f"unexpected SRX term: {term.tag}")
            row[binding.attrib["name"]] = value
        rows.append(row)
    return variables, rows, results.get("ordered") == "true"


def expected_result(path):
    if path.suffix == ".srx":
        return xml_result(path)
    if path.suffix == ".srj":
        return json_result(json.loads(path.read_text(encoding="utf-8")))
    graph = rdf_graph(path)
    result_set = graph.value(predicate=RDF.type, object=RS.ResultSet)
    if result_set is None:
        return graph
    answer = graph.value(result_set, RS.boolean)
    if answer is not None:
        return bool(answer.toPython())
    variables = frozenset(map(str, graph.objects(result_set, RS.resultVariable)))
    rows = []
    for item in graph.objects(result_set, RS.solution):
        index = graph.value(item, RS["index"])
        row = {str(graph.value(b, RS.variable)): normalized_term(graph.value(b, RS.value))
               for b in graph.objects(item, RS.binding)}
        rows.append((None if index is None else int(index), row))
    ordered = bool(rows) and all(i is not None for i, _ in rows)
    if ordered:
        rows.sort(key=lambda entry: entry[0])
    return variables, [row for _, row in rows], ordered


def result_graph(rows, ordered):
    graph = Graph()
    for i, row in enumerate(rows):
        node = BNode(f"row:{i}")
        graph.add((node, RDF.type, RS.solution))
        if ordered:
            graph.add((node, RS["index"], Literal(i)))
        for name, value in row.items():
            predicate = URIRef("urn:variable:" + quote(name, safe=""))
            if isinstance(value, BNode):
                value = BNode("value:" + str(value))
            graph.add((node, predicate, value))
    return graph


def equal_result(actual, expected):
    if isinstance(expected, Graph):
        return isomorphic(actual, expected)
    if isinstance(expected, bool):
        return actual is expected
    actual_vars, actual_rows, _ = actual
    variables, rows, ordered = expected
    if actual_vars != variables or len(actual_rows) != len(rows):
        return False
    if any(isinstance(v, BNode) for row in actual_rows + rows for v in row.values()):
        return isomorphic(result_graph(actual_rows, ordered), result_graph(rows, ordered))
    signatures = lambda rs: [frozenset(row.items()) for row in rs]
    if ordered:
        return signatures(actual_rows) == signatures(rows)
    return Counter(signatures(actual_rows)) == Counter(signatures(rows))


def run_case(executable, manifest, case, root, input_file):
    action = manifest.value(case, MF.action)
    query = local_file(manifest.value(action, QT.query), root)
    expected = expected_result(local_file(manifest.value(case, MF.result), root))
    input_file.write_text(json.dumps(query_manifest(action, manifest, query, root)),
                          encoding="utf-8")
    graph_result = isinstance(expected, Graph)
    execution = subprocess.run(
        [str(executable), "--dataset", str(input_file), str(query), "rdf" if graph_result else "json"],
        capture_output=True, encoding="utf-8", errors="replace", timeout=20,
    )
    if execution.returncode:
        diagnostic = (execution.stderr + execution.stdout).strip()[-600:]
        kind = "unsupported" if ".QueryError.Unsupported" in diagnostic else "query-error"
        return kind, diagnostic
    try:
        actual = (Graph().parse(data=execution.stdout, format="nt") if graph_result
                  else json_result(json.loads(execution.stdout)))
    except (KeyError, ValueError, TypeError) as error:
        return "invalid-output", str(error)
    if not equal_result(actual, expected):
        return "result-mismatch", f"expected {str(expected)[:400]} actual {execution.stdout[:400]}"
    return "pass", ""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--suite", type=Path, default=ROOT / "_build/w3c-rdf-tests")
    parser.add_argument("--fetch", action="store_true")
    parser.add_argument("--audit", action="store_true", help="report every failure without exceptions")
    parser.add_argument("--case", help="limit a diagnostic run to an exact category/test ID")
    parser.add_argument("--output", type=Path, default=ROOT / "_build/w3c-results.json")
    args = parser.parse_args()
    root = args.suite.resolve()
    checkout(root, args.fetch)
    executable = args.executable.resolve(strict=True)
    gaps = {} if args.audit else json.loads((ROOT / "scripts/w3c_known_gaps.json").read_text(encoding="utf-8"))
    outcomes = []
    with tempfile.TemporaryDirectory() as folder:
        input_file = Path(folder) / "dataset.json"
        for version, category in ((v, c) for v, categories in SUITES.items() for c in categories):
            manifest = rdf_graph(root / "sparql" / version / category / "manifest.ttl")
            entries = next(manifest.objects(None, MF.entries))
            for case in manifest.items(entries):
                if (case, RDF.type, MF.QueryEvaluationTest) not in manifest:
                    continue
                case_id = category + "/" + urlsplit(str(case)).fragment
                if args.case and args.case != case_id:
                    continue
                kind, detail = run_case(executable, manifest, case, root, input_file)
                gap = gaps.get(case_id)
                status = ("pass" if kind == "pass" and gap is None else
                          "known-gap" if gap and gap["kind"] == kind else
                          "unexpected-pass" if kind == "pass" else "unexpected-failure")
                outcomes.append(dict(case=case_id, status=status, kind=kind, detail=detail))
    if not outcomes:
        raise SystemExit("No W3C query cases executed")
    if not args.case and set(gaps) - {item["case"] for item in outcomes}:
        raise SystemExit("Known-gap list contains unexecuted W3C case IDs")
    summary = dict(Counter(item["status"] for item in outcomes))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(dict(revision=REVISION, counts=summary, cases=outcomes),
                                      ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"W3C {REVISION}: {len(outcomes)} cases {summary}")
    unexpected = [item for item in outcomes if item["status"].startswith("unexpected")]
    for item in unexpected[:12]:
        print(item["case"], item["status"], item["kind"], item["detail"])
    raise SystemExit(bool(unexpected))


if __name__ == "__main__":
    main()
