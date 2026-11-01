# MoonSparql 十一月功能扩展

已有RDF解析与约束库解决输入和验证，应用仍需要关联、路径、聚合和可复核的查询结果。项目补充有界查询执行，新增精确快照补丁和保留重复次数的结果差异，支持资产、目录和研究元数据变更的消费方分析。

## 1. 精确前置条件的原子数据补丁

`Dataset::apply_patch`：对原快照检查全部remove/add；缺失/重复删除、已存在/重复新增和重叠操作明确拒绝，通过后建立新快照与查询索引。命名图身份属于匹配条件，旧数据保持可查询。

复杂度与代价：预期O(旧事实+操作数)时间及空间，含term/key文本成本；遵守输入/结果规模与工作预算。这是宿主API，不是SPARQL UPDATE语法实现。

## 2. SELECT结果多重集变化分析

`QueryResult::binding_delta`：要求一致的变量契约，按精确RDF term与未绑定状态比较，返回新增/移除的具体binding occurrence及保留数；重复行次数变化不会被set去重掩盖。

复杂度与代价：预期O((旧行+新行)·变量数)及term文本成本；有步数/输出预算。不比较顺序，不处理ASK/CONSTRUCT，不做blank-node图同构。

## 运行

```sh
moon run examples/november --target native --deny-warn
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
```

Windows当前工具链路径问题沿用README的项目适配脚本；源代码临时命名空间尚未发布。

## 范围

不实现完整SPARQL1.1、SERVICE/UPDATE/DESCRIBE、推理、持久数据库或分布式执行；blank node需共用稳定标识范围，bag delta不会推断跨快照匿名节点同构。

现有查询语义和10,000事实规模测试；新增补丁原子性/命名图及bag差异/UNDEF/预算边界。 具体当前执行结果由本地检查记录提供，不以CI配置代替远端成功记录。
