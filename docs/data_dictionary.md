# 数据字典

三张事实表的字段说明、取值范围、业务含义。数据由 `python/generate_data.py` 生成。

---

## `users` — 用户主数据

记录每个注册用户的画像信息。一行一个用户。

| 字段 | 类型 | 说明 | 取值范围 |
|---|---|---|---|
| `user_id` | VARCHAR (PK) | 用户唯一标识 | `U000001` ~ `U005500` |
| `register_date` | DATE | 注册日期 | `2024-01-01` ~ `2025-12-31` |
| `country` | VARCHAR | 用户所在国家 | US / UK / Germany / India / Japan / China / Brazil / France / Canada / Australia |
| `device_type` | VARCHAR | 主要使用设备 | Desktop / Mobile / Tablet |
| `acquisition_channel` | VARCHAR | 获客渠道 | Organic / Social Media / Google Ads / Email |
| `plan_type` | VARCHAR | 当前订阅套餐 | Free / Basic / Pro / Enterprise |
| `company_size` | VARCHAR | 用户所在公司规模 | 1-10 / 11-50 / 51-200 / 201-1000 / 1000+ |

**业务说明：**

- `plan_type` 是**当前**所属套餐，不是历史套餐——这意味着无法直接还原"Free → Paid 升级"事件。
- `country` 分布有意偏向美 / 印 / 欧洲，模拟一个全球化 SaaS 平台。
- `register_date` 在 2024-2025 之间按时间递增加权（越靠后注册量越多，模拟产品成长期）。

---

## `activity` — 用户行为日志

记录用户的每一次 session。一行一个 session。

| 字段 | 类型 | 说明 | 取值范围 |
|---|---|---|---|
| `activity_id` | VARCHAR (PK) | 行为事件唯一标识 | `A0000001` 起 |
| `user_id` | VARCHAR (FK → users) | 行为发生者 | 必须存在于 `users` |
| `activity_date` | DATE | 行为发生日期 | ≥ 用户的 `register_date` |
| `session_duration` | INTEGER | 单次 session 时长（分钟） | 1 ~ 180 |
| `pages_viewed` | INTEGER | 单次 session 浏览页数 | 1 ~ 80 |
| `feature_used` | VARCHAR | 主要使用功能 | Design / Comment / Export / Share / Template / Collaborate |

**业务说明：**

- `feature_used` 的概率分布按 `plan_type` 不同——Enterprise 用户更多使用 Collaborate，Free 用户更多用 Design。
- 单 session 的 `session_duration` 和 `pages_viewed` 不强相关（设计上独立采样），但都受用户的"engagement 系数"影响（渠道 × 套餐）。
- 行为发生时间按**指数分布**集中在注册后的 1-2 个月，长尾衰减——还原典型 SaaS 留存曲线。

---

## `subscription` — 订阅付费记录

记录每一笔付款事件。**注意：这不是订阅状态表**。

| 字段 | 类型 | 说明 | 取值范围 |
|---|---|---|---|
| `subscription_id` | VARCHAR (PK) | 付款记录唯一标识 | `S000001` 起 |
| `user_id` | VARCHAR (FK → users) | 付款人 | 必须存在于 `users` |
| `payment_date` | DATE | 付款日期 | ≥ 用户的 `register_date` |
| `amount` | DOUBLE | 付款金额（USD） | Basic ~$12 / Pro ~$35 / Enterprise ~$99（月付）；年付为 10× 月付 |
| `subscription_type` | VARCHAR | 订阅周期 | Monthly / Annual |
| `payment_status` | VARCHAR | 付款状态 | Success / Failed / Refunded（≈ 96% / 3% / 1%） |

**业务说明 / 重要边界：**

- 一个用户可能有**多条付款记录**——同一 user_id 的 ≥2 条 Success 记录在本项目里视为"续费"（详见 `docs/metric_definitions.md`）。
- **没有"取消订阅"事件**。本表只记录付款发生，不记录退订。因此**真实订阅状态（active / churned）无法从本表直接还原**。
- `amount` 在套餐基准价附近 ±5% 浮动，模拟促销、税费、汇率扰动。
- Free 用户不会出现在 `subscription` 表中。

---

## 三表关系

```
users (1) ──┬── (N) activity
            └── (N) subscription
```

- `activity.user_id` 和 `subscription.user_id` 都引用 `users.user_id`。
- 完整性校验：`python/load_to_duckdb.py` 在导入时检查孤立外键，当前 = 0。

---

## 数据生成假设（可被反向验证）

`generate_data.py` 把以下业务规律写成显式权重：

| 规律 | 体现 |
|---|---|
| Organic / Social Media 用户活跃度更高 | `CHANNEL_ENGAGEMENT` 字典：Organic 1.30 / Social 1.20 / Google Ads 1.00 / Email 0.70 |
| Enterprise 用户 session 更长、页数更多 | `PLAN_ENGAGEMENT` 字典：Free 0.60 / Basic 0.95 / Pro 1.35 / Enterprise 1.85 |
| Desktop 用户中 Enterprise 占比更高 | 套餐分布按 device 微调 |
| 公司规模与套餐正相关 | Free 多为 1-10，Enterprise 多为 1000+ |
| 活动时间集中在注册后 1-2 个月 | 用 Exponential(scale=30 days) 而非均匀分布 |

这些规律可以用 SQL 反向验证（见 `sql/00_verify_import.sql` 末尾的"业务规律快速验证"段）。
