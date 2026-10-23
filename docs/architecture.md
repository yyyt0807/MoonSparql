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
UNION and MINUS use materialized compatible joins; worst-case O(A*B*V) work
for A/B bindings and V shared variables. This correctness-first implementation
is suited to bounded in-memory work, not massive distributed queries.

Sequence paths index intermediate endpoints. Reachability uses adjacency lists
and iterative visited-set traversal. For each starting node, closure is
O(V+E); all-pairs closure can cost O(V*(V+E)) time and O(V^2) result storage.
Bound endpoints narrow the starting-node set. Pair and step limits cap work.

Grouping uses hash keys with exact term identity and materializes each group's
members. Aggregates are evaluated per requested expression, so repeated
aggregates can rescan a group; no common-subexpression optimization is claimed.
Big integer/decimal operations additionally depend on digit count.

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
