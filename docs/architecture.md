# Architecture and complexity

The pipeline is lexer -> bounded AST -> scope checks -> indexed dataset matching
-> graph algebra -> grouping -> projection/order/distinct/slice -> result encoding.
Prepared queries and datasets can be reused after failed executions.

For N quads and total term text L, dataset construction uses expected O(N+L)
hash work and O(N+L) storage. Four posting-list indexes cover subject, predicate,
object and graph. A triple match starts from the shortest bound posting list;
it still verifies all remaining constraints. K candidates cost O(K) plus term
comparison costs. No composite indexes or cost-based join reordering are claimed.

A BGP joins left solutions against indexed matches. OPTIONAL, nested groups,
UNION, subqueries and MINUS use materialized compatible joins with worst-case
O(A*B*V) work for A/B bindings and V binding width. Subqueries share the
execution budget and join only projected bindings. EXISTS evaluates its
pattern for each outer solution using the current graph and bound terms.
The resulting intermediate work is charged to the same budget.

Sequence paths index intermediate endpoints. Reachability uses adjacency lists
and iterative visited-set traversal. For each starting node, closure is
O(V+E); all-pairs closure can cost O(V*(V+E)) time and O(V^2) result storage.
Bound endpoints narrow the starting-node set. Pair and step limits cap work.
Negated paths hash their excluded predicates and deduplicate matching endpoint
pairs. For E active graph edges and K excluded predicates this takes expected
O(E+K) work for each direction. Closure marks nodes at enqueue time to avoid
duplicate pending entries.

Grouping uses hash keys with exact term identity and materializes each group's
members. Aggregates are evaluated per requested expression, so repeated
aggregates can rescan a group; no common-subexpression optimization is claimed.
Big integer/decimal operations additionally depend on digit count.
Group aliases are evaluated before aggregate members are collected.
Trailing VALUES joins grouped rows before projection without duplicating
the rows contributing to an aggregate.

ORDER BY uses stable iterative mergesort: O(R log R) comparisons, O(R) auxiliary
row references. DISTINCT uses hash keys, and OFFSET/LIMIT apply after ordering
and distinct projection. Intermediate materialization is limited independently.

Core computation is MoonBit and portable across wasm, wasm-gc, JS and Native.
The Native CLI alone uses async filesystem IO; it checks byte size before loading.
Its file-size check is advisory if another process changes a file concurrently;
the library still enforces decoded input budgets after reading.

No untrusted query loads remote content or executes external code. This does
not sandbox a host application or make arbitrary data volumes safe: applications
must configure budgets and isolate requests according to their own workload.

Local dataset clauses use graph posting lists and build a new scoped snapshot.
Blank-node maps are reset per merged source while allocated labels remain
reserved across the view. Static query inspection traverses the bounded AST
without opening any data source.
