# MoonSparql 增量功能：2026-11-06

状态：本地未发布增量。使用本目录源码运行，已发布的 0.1.0 不包含本页新增 API。

## 独立空白节点作用域的 RDF 合并与按列对齐的 SELECT 袋并集
`Dataset::merge_scoped(other, limits~)` 合并来自独立文档的 RDF 数据集。
为右侧所有 blank node 生成全新、不与两侧原标签冲突的标签；同一右侧节点在所有 subject/object 位置保持一致。
相同 ground quad 按集合去重，保留左侧顺序、右侧新增顺序及 IRI named graph。
这是 RDF merge，不是图同构规范化；不推断两个不同空白节点代表相同实体。
输入四元组数量之和须不超过 max_triples（去重前保守预算），工作受 max_steps 限制。

`QueryResult::union_bindings(other, shared_blank_scope~=false, limits~)` 接受有声明变量的 SELECT 结果。
输出变量先左后右去重、行先左后右拼接；保留重复行与 unbound，缺列不伪造空字符串或 null term。
默认两个结果的空白节点作用域独立，右侧一致重命名；仅确知共享原始 RDF 作用域时设置 shared_blank_scope=true。
拒绝 ASK/CONSTRUCT 结果；合并行数受 max_results/max_bindings、列数受 max_tokens、扫描受 max_steps 限制。
返回 stats 描述本次合并的工作量，而非原查询耗时的求和。源结果不变。

用于知识目录整合、多个本地数据源的查询导出、资产目录拼接和离线分析。
不发起网络请求，不实现 SERVICE、SPARQL UPDATE、联邦查询或 blank graph name 支持。

RDF 合并期望时间/空间 O(Q+T)，Q 为四元组数、T 为术语键与空白标签文本量；
结果合并时间 O(声明列+已绑定项扫描)，空间 O(输出绑定+空白映射)。两者通过预算拒绝过大工作。
测试含同名空白节点隔离、重命名碰撞、引用一致、ground quad 去重、named graph 查询、重复/unbound、共享作用域及预算拒绝。

## 运行

```sh
moon run examples/expansion --target native --deny-warn
moon test --target all --deny-warn
```

Windows 使用 README 中对应的 Moon 包装脚本替代 `moon`。
CI 已添加该示例；无需网络服务、私钥或真实设备。
