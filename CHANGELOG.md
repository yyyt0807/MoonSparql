# Changelog

## Unreleased — 2026-11-09

- 完善 SELECT 子查询、EXISTS／NOT EXISTS、否定属性集合及零长度路径语义。
- 支持 GROUP_CONCAT、分组别名、尾部 VALUES、字符串与日期时间内置函数，以及 integer／double 转换。
- 支持本地 FROM／FROM NAMED 数据集、BASE 与相对查询 IRI、查询匿名节点及 RDF 集合。
- 增加离线多文档数据目录、查询结构检查和 CONSTRUCT WHERE 子图导出。
- 接入固定版本的 W3C 查询测试。236 项执行中 219 项通过，17 项为明示的函数缺口。

- 独立空白节点作用域的 RDF 合并。
- 按列对齐的 SELECT 袋并集。
- 增加回归测试、独立可运行示例与 CI 示例步骤；详见 docs/EXPANSION_20261106.md。

## 0.1.0 — 2026-11-01

- 精确前置条件的原子数据补丁：Dataset::apply_patch
- SELECT结果多重集变化分析：QueryResult::binding_delta
- RDF 查询内核：SELECT/ASK/CONSTRUCT、关联、可选匹配、聚合、路径及明确的 SPARQL 1.1 子集。
- 增加边界回归、可运行集成示例、RDFLib 独立对照和 CI 步骤。
- 正式模块为 yyyt0807/moonsparql；公开维护账号为 yyyt0807。
