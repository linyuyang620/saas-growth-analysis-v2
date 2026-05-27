# 指标定义

本项目用到的所有指标的计算口径、SQL 位置、以及与真实业务实现的差异。

数据基线：`MAX(activity.activity_date)` 视为"今天"。

---

## 1. 活跃指标 (Activity)

### DAU — Daily Active Users
- **定义**：当日有任意 activity 记录的去重用户数。
- **公式**：`COUNT(DISTINCT user_id) GROUP BY activity_date`
- **SQL**：`sql/01_user_growth_analysis.sql § 2`
- **注意**：同一用户当日多次活动只计 1 次。

### WAU — Weekly Active Users
- **定义**：自然周（周一起）内有任意 activity 的去重用户数。
- **公式**：`COUNT(DISTINCT user_id) GROUP BY DATE_TRUNC('week', activity_date)`
- **SQL**：`sql/01_user_growth_analysis.sql § 3`

### MAU — Monthly Active Users
- **定义**：自然月内有任意 activity 的去重用户数。
- **公式**：`COUNT(DISTINCT user_id) GROUP BY DATE_TRUNC('month', activity_date)`
- **SQL**：`sql/01_user_growth_analysis.sql § 4`

### Stickiness — 粘性
- **定义**：用户在一个月内平均有几天打开产品 → 反映使用频次。
- **公式**：`AVG(daily DAU within month) / MAU`
- **SQL**：`sql/01_user_growth_analysis.sql § 4`
- **基线**：社交产品 ~50%、工具类 ~20%、B2B SaaS ~10-30%（参考 Mixpanel/Amplitude 行业报告）。

---

## 2. 留存指标 (Retention)

### D1 / D7 / D30 Rolling Retention
- **定义**：注册后 1 / 7 / 30 天**内任意一天**有活动的用户比例（滚动 / rolling 口径）。
- **公式**：
  ```
  DN_retention = COUNT(eligible_users with any activity in days 1..N)
              / COUNT(eligible_users registered at least N days ago)
  ```
- **SQL**：`sql/02_retention_analysis.sql § 1`
- **窗口约定**：`(register_date, register_date + N days]`（不含注册当天，含第 N 天）。
- **资格过滤**：用户必须注册满 N 天才进入分母，避免新用户被误算为"未留存"。

### Cohort Retention — 队列留存矩阵
- **定义**：
  - 行 = `cohort_month`（注册月份）
  - 列 = `months_since_register`（注册后第 K 个月）
  - 值 = 该 cohort 在第 K 个月仍有任意活动的用户比例
- **SQL**：`sql/02_retention_analysis.sql § 2`
- **⚠ 重要边界 — Cohort 成熟度**：
  - 近期 cohort（如 2025-H2）的高 `months_since_register` 列**数据稀疏或缺失**——因为它们还没"存在"够久。
  - **不要跨 cohort 直接做平均**；做对比时要控制 cohort 年龄。
  - 早期 cohort（2024-H1）可观察到 M12+ 的长尾留存。

---

## 3. 收入指标 (Revenue)

### MRR — Monthly Recurring Revenue
- **本项目实现**：
  - Monthly 订阅：在 `payment_date` 所在月计 `amount`
  - Annual 订阅：在 `payment_date` 起 12 个月，每月计 `amount / 12`
  - 仅统计 `payment_status = 'Success'`
- **SQL**：`sql/03_revenue_analysis.sql § 2`、视图 `v_mrr_trend`

#### ⚠ 重要差异 — 这其实是 Recognized Revenue 月分摊，不是严格 MRR

本项目**没有订阅状态表**，也没有 churn / downgrade / upgrade 事件记录。
所有 annual 订阅按 12 个月**全额**分摊，无论用户实际上是否还在使用。

因此严格来说，本项目算的是：
> **"已确认收入的月度分摊"（recognized revenue monthly allocation）**

而不是真实业务里"由订阅状态驱动的 MRR"。

**真实业务中 MRR 必须动态调整：**

| 事件 | MRR 调整 |
|---|---|
| 用户 churn（取消订阅） | 从下一周期开始扣减该用户的 MRR |
| 用户 downgrade（降级） | 减少 (旧套餐 MRR - 新套餐 MRR) |
| 用户 upgrade（升级） | 增加 (新套餐 MRR - 旧套餐 MRR)，记为 Expansion MRR |
| 新用户开通付费 | 增加 New MRR |

行业标准 MRR 报告通常拆为 4 块：**New + Expansion - Contraction - Churn = Net New MRR**。
本项目暂未做此拆分（schema 限制）。

### ARR — Annual Recurring Revenue
- **公式**：`MRR × 12`
- **同样的局限性**：继承 MRR 的口径问题。

### ARPU — Average Revenue Per User
- **公式**：`总成功收入 / 总用户数`（**分母含 Free 用户**）
- **SQL**：`sql/03_revenue_analysis.sql § 3`
- **用途**：看整体商业化效率（Free 用户多 → ARPU 被拉低）。

### ARPPU — Average Revenue Per Paying User
- **公式**：`总成功收入 / 付费用户数`
- **SQL**：`sql/03_revenue_analysis.sql § 3`
- **本项目近似**：用 `plan_type <> 'Free'` 当作付费用户。
- **⚠ 局限**：漏掉了"曾付费但已降级为 Free"的用户——schema 里没有套餐变更历史。

### 收入集中度 — Pareto Distribution
- **定义**：付费用户按累计 lifetime revenue 排名后分桶（Top 1% / 10% / 20% / 50% / Bottom 50%）。
- **SQL**：`sql/03_revenue_analysis.sql § 7`，用 `NTILE(100) OVER (ORDER BY rev DESC)`。

---

## 4. 漏斗指标 (Funnel)

5 段嵌套漏斗，每一段是前一段的子集：

```
Registered → Activated → Retained → Paid → Renewed
```

| 阶段 | 定义 | 备注 |
|---|---|---|
| **Eligible (基线)** | 注册满 30 天 | 不满 30 天的新用户排除 |
| **Activated** | 注册后 0~7 天内 activity ≥ 3 次 | 首周用 3 次表示"已尝试使用" |
| **Retained** | 注册后第 **8~30 天**仍有任意 activity | **激活窗口之后**的留存（注 1） |
| **Paid** | 当前 `plan_type <> 'Free'` | 见 ARPPU 局限性 |
| **Renewed** | 该用户的 `Success` 付款次数 ≥ 2 | 见注 2 |

- **SQL**：`sql/04_funnel_analysis.sql § 6`、视图 `v_funnel_summary`

**注 1：为什么 Retained 用 8-30 天？**
最早一版用"注册后 1-30 天有活动"，结果 Activated → Retained 永远是 100%——因为首周有 ≥3 次活动的用户必然在 1-30 天内有活动，是数学必然不是业务洞察。
改为"注册第 8-30 天"后，这一步衡量的是"激活之后是否真的留下来用"，才有真正的转化率含义。

**注 2：为什么续费用"付款次数 ≥ 2"？**
`subscription` 表里没有 `renewal_count` 字段。**"同一用户出现 ≥ 2 次 Success 付款"** 是行业标准的等价口径——见 `docs/data_dictionary.md` 关于 subscription 表的说明。

---

## 5. 渠道质量指标

- **付费转化率**：`paid_users / total_users`，按 `acquisition_channel` 切片
- **渠道 ARPU**：`channel_revenue / channel_users`（分母含 Free）
- **渠道 ARPPU**：`channel_revenue / channel_paying_users`
- **渠道收入占比**：`channel_revenue / total_revenue`

全部在 `sql/03_revenue_analysis.sql § 6`、视图 `v_revenue_by_channel`。

---

## 速查表

| 指标 | SQL 文件 | 视图 |
|---|---|---|
| DAU / WAU / MAU | `01_user_growth_analysis.sql` | — |
| MAU MoM / Stickiness | `01_user_growth_analysis.sql` | — |
| D1 / D7 / D30 | `02_retention_analysis.sql` | `retention_tableau` |
| Cohort 矩阵 | `02_retention_analysis.sql` | `cohort_retention_tableau` |
| MRR / ARR / ARPU / ARPPU | `03_revenue_analysis.sql` | `v_mrr_trend` |
| 渠道收入 | `03_revenue_analysis.sql` | `v_revenue_by_channel` |
| 套餐收入 | `03_revenue_analysis.sql` | `v_revenue_by_plan` |
| 漏斗 5 段 | `04_funnel_analysis.sql` | `v_funnel_summary` |
| 激活率分群 | `04_funnel_analysis.sql` | `v_activation_analysis` |
| 付费率分群 | `04_funnel_analysis.sql` | `v_paid_conversion` |
| 续费率分群 | `04_funnel_analysis.sql` | `v_renewal_analysis` |
