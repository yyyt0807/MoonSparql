# Changelog

## Unreleased — 2026-11-06

- 独立空白节点作用域的 RDF 合并。
- 按列对齐的 SELECT 袋并集。
- 增加回归测试、独立可运行示例与 CI 示例步骤；详见 docs/EXPANSION_20261106.md。

## 0.1.0 — 2026-11-01

- 精确前置条件的原子数据补丁：Dataset::apply_patch
- SELECT结果多重集变化分析：QueryResult::binding_delta
- RDF 查询内核：SELECT/ASK/CONSTRUCT、关联、可选匹配、聚合、路径及明确的 SPARQL 1.1 子集。
- 增加边界回归、可运行集成示例、RDFLib 独立对照和 CI 步骤。
- 正式模块为 yyyt0807/moonsparql；公开维护账号为 yyyt0807。
