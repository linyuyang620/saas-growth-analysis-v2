# Tableau Dashboard 搭建指引

把项目里 9 个 CSV 搭成 4 个 Dashboard，最后导出截图放到 README 和简历里。

**预计耗时**：3-4 小时（首次搭建）
**前置条件**：已经跑过 `python python/export_views_to_csv.py`，`tableau/` 目录下有 10 个 CSV

---

## 0. 环境准备（10 分钟）

### 0.1 下载 Tableau Public Desktop（免费）

https://public.tableau.com/en-us/s/download

注册账号、下载、安装。和 Tableau Desktop（付费版）功能基本一致，唯一限制是**工作簿必须保存到云端（公开）**——这对作品集反而是好事，可以拿到一个公开 URL 放简历。

### 0.2 连接数据

打开 Tableau Public → `Connect` → `To a File` → `Text file` → 选 `tableau/v_mrr_trend.csv`

**关键**：每个 dashboard 用到多少 CSV 就连多少。我建议**每个 CSV 作为独立 data source**，而不是 union/join，因为这些 CSV 已经是聚合好的 view，再 join 容易翻车。

切换 data source 用左侧 Data 面板的下拉。

### 0.3 检查字段类型

CSV 默认会把 `cohort_month`、`month_start` 之类的列识别成字符串。**右键字段名 → Change Data Type → Date**。日期字段一定要是 Date 类型，否则后面排序和 axis 都会出问题。

### 0.4 命名规范

每个 worksheet 命名清晰：`D1_MRR_Trend`、`D3_Cohort_Heatmap` 这种格式。后面拖到 dashboard 找起来快。

---

## 1. Dashboard 1: Executive Overview（45 分钟）

**目标**：高管 30 秒看完业务健康度
**用到的 CSV**：`v_mrr_trend.csv`、`v_funnel_summary.csv`、`v_revenue_by_channel.csv`、`v_revenue_by_plan.csv`

### 1.1 MRR 趋势图（worksheet 名：`D1_MRR_Trend`）

数据源：`v_mrr_trend.csv`

- `month_start` → Columns（确认是 `Continuous Month`，右键展开到 `Month + Year`）
- `mrr` → Rows
- Marks 卡：Mark type 选 `Area`
- 颜色：选品牌色（推荐 `#2563EB` 蓝）
- 加双轴：`paying_users` → 拖到 Rows 同一行右侧，右键选 `Dual Axis`
- 右轴改成 Line，调灰色 `#888`，把 Synchronize Axis **取消**（两条线尺度不同）

格式化：
- 隐藏轴标题（右键 Axis → Edit Axis → 清空 Title）
- 加 reference line：分析面板拖 `Constant Line` 到 mrr 轴，写一条"target = $50K"之类的虚线

### 1.2 漏斗图（`D1_Funnel`）

数据源：`v_funnel_summary.csv`

Tableau 没有原生漏斗，用"横向条 + 排序"代替：

- `users` → Columns
- `stage` → Rows（按 `step_order` 排序：右键 stage → Sort → By Field → step_order, Ascending）
- Marks：Bar
- 颜色：用 `step_order` 做渐变（深 → 浅模拟漏斗收窄感）
- Labels：拖 `step_conversion_pct` 到 Label，右键 → 格式化为百分数

### 1.3 渠道收入 Donut（`D1_Channel_Donut`）

数据源：`v_revenue_by_channel.csv`

Tableau Donut 也是 hack 出来的，步骤：

- Marks type 选 `Pie`
- `revenue` → Size 和 Angle
- `acquisition_channel` → Color
- 再拖一个空 measure `MIN(1)` 到 Rows，再拖一次 `MIN(1)` 到 Rows
- 右键第二个 → `Dual Axis`、`Synchronize Axis`
- 第二层 Pie 的 size 调小、颜色改成白色——视觉上就是甜甜圈中间挖空

**省事方案**：直接用 Pie chart 不做 donut，差别不大。

### 1.4 套餐收入 Donut（`D1_Plan_Donut`）

复制 1.3 的步骤，换数据源 `v_revenue_by_plan.csv`，把 `acquisition_channel` 换成 `plan_type`。

### 1.5 KPI Cards（`D1_KPI_Cards`）

这是最容易"出片"的部分。每个 KPI 一个 worksheet：

- 数据源：直接用相关 CSV（例如 MRR 用 `v_mrr_trend.csv`）
- 拖 `mrr` 到 Text marks
- 设置聚合为 `MAX` 或具体某一行（用 filter 限定 `month_start = max`）
- 字号调到 36pt，加粗，主色蓝
- 标题手写："MRR (latest)"

做 6 个：Total Users / MAU / MRR / ARPU / Conversion / Renewal Rate

### 1.6 组装 Dashboard

`Dashboard` → `New Dashboard`
- Size 选 `Automatic` 或固定 `1400×900`
- 把 6 个 KPI 横向排顶部（用 Horizontal container）
- MRR 趋势放中间偏左大区域
- 漏斗放右侧
- 两个 donut 放底部

**Tip**：左侧 `Dashboard → Objects` 拖 `Horizontal/Vertical container` 控制布局，比直接堆 worksheet 整齐得多。

📸 **截图机会 1**：D1 完成时截图，放到 README 顶部，效果最震撼。

---

## 2. Dashboard 2: Acquisition & Funnel（45 分钟）

**目标**：增长团队看渠道质量和漏斗瓶颈
**用到的 CSV**：`v_funnel_summary.csv`、`v_activation_analysis.csv`、`v_paid_conversion.csv`、`v_revenue_by_channel.csv`、`users.csv`（在 data/ 下，要单独连）

### 2.1 月度新增分渠道堆叠（`D2_Monthly_New_Stacked`）

需要从 `users.csv`（原表）算月新增。连 `data/users.csv`：

- `register_date` → Columns（改成 `MONTH(register_date)` 连续日期）
- `Number of Records`（或者拖 user_id 到 Rows 选 Count）→ Rows
- `acquisition_channel` → Color
- Marks type 选 `Bar`，会自动 stacked

### 2.2 漏斗大图（`D2_Funnel_Big`）

复用 D1 的漏斗 worksheet，但放大字体，标签同时显示绝对人数和 step%：

- Labels 卡：拖 `users` 和 `step_conversion_pct` 都进 Label
- Edit Label 改格式：`<users> users (<step_conversion_pct>%)`

### 2.3 激活率分渠道（`D2_Activation_By_Channel`）

数据源：`v_activation_analysis.csv`

- Filter：`segment_type` = `channel`
- `segment` → Rows
- `activation_pct` → Columns
- 排序：降序
- 加 Label 显示百分数

### 2.4 激活率分套餐（`D2_Activation_By_Plan`）

复制 2.3，filter 改成 `segment_type` = `plan`，注意 Rows 用同一个 `segment` 字段。

### 2.5 付费率分公司规模（`D2_Paid_By_Company_Size`）

数据源：`v_paid_conversion.csv`，filter `segment_type` = `company_size`。

**手动排序**：公司规模有自然顺序（1-10 < 11-50 < 51-200 < ...），不能按 alphabetical。右键 segment → Sort → Manual → 拖动排序。

### 2.6 渠道质量散点（`D2_Channel_Quality_Scatter`）

数据源：`v_revenue_by_channel.csv`

- `conversion_pct` → Columns
- `arpu` → Rows
- `acquisition_channel` → Color, Label
- `users` → Size
- Marks type 选 `Circle`
- 加象限参考线：分析面板拖 `Average Line` 到两个轴

这张图能识别"高 ARPU 低转化"这种值得优化的渠道，业务感很强，面试爱讲。

### 2.7 组装 D2

布局参考之前的 ASCII：顶部 5 个 KPI → 左侧月度新增大图 → 右侧 3 个小条形图 → 中部大漏斗 → 底部散点。

📸 **截图机会 2**：D2 完成。

---

## 3. Dashboard 3: Retention（45 分钟）— **GitHub 视觉核心**

**目标**：产品团队看 Cohort 衰减
**用到的 CSV**：`cohort_retention_tableau.csv`（主）、`retention_tableau.csv`、`activity.csv`、`users.csv`

### 3.1 Cohort 留存热力图（`D3_Cohort_Heatmap`）— **最重要的图**

数据源：`cohort_retention_tableau.csv`

步骤：

1. `cohort_month` → Rows（改为 `Discrete Month + Year`，右键选第二个 MONTH 那个绿色丸子）
2. `months_since_register` → Columns（Discrete，保持整数）
3. `retention_pct` → Color
4. `retention_pct` → Label（同时拖一份到 Label）
5. Marks type 选 `Square`

颜色配置：
- 双击 Color → Edit Colors
- 配色选 `Green-Gold-Red Diverging` 反转，或者用 sequential `Green`
- Stepped Color 选 `8 steps`，让格子之间区分更明显

Label 格式：
- 右键 Label → Format → 数字格式选 1 位小数 + %
- 字号 9pt，看不清就调

**关键调整**：
- 设置 Cell size：Format → Cell Size → 调到约 60×35 像素，让每个格子都能看清数字
- 限定 cols 到 M0..M12（filter `months_since_register` ≤ 12）

这张图做好之后非常 striking——视觉上能直接看到 2024 年 H1 cohort 的长尾、近期 cohort 的早期表现。这是简历最好的截图。

📸 **关键截图**：单独把这张图截一张高清版本，README 顶部"主要发现"那段放它。

### 3.2 D1/D7/D30 总览（`D3_Retention_Cards`）

3 个 KPI 数字。数据源 `retention_tableau.csv`：

- Filter：`segment_type` = `overall`
- 一个 worksheet 显示 D1：filter `period` = `1`，拖 `retention_pct` 到 Text
- 复制两遍做 D7 和 D30

### 3.3 分渠道留存曲线（`D3_Channel_Retention_Curves`）

数据源：`retention_tableau.csv`

- Filter：`segment_type` = `channel`
- `period` → Columns（Continuous）
- `retention_pct` → Rows
- `segment` → Color
- Marks type 选 `Line`

### 3.4 Free vs Paid 留存（`D3_Free_vs_Paid`）

数据源：`retention_tableau.csv`

- Filter：`segment_type` = `tier`
- `period` → Columns（Discrete）
- `segment` → Color
- `retention_pct` → Rows
- Marks type 选 `Bar`

### 3.5 激活 vs 未激活留存对比（`D3_Activation_Lift`）

需要自定义查询——Tableau Public 不能直接连 DuckDB，所以提前在 DuckDB 里 export 一份：

```sql
COPY (
    WITH today AS (SELECT MAX(activity_date) AS d FROM activity),
    e AS (SELECT u.user_id, u.register_date FROM users u, today
          WHERE u.register_date <= today.d - INTERVAL 30 DAY),
    l AS (SELECT e.user_id,
          CASE WHEN (SELECT COUNT(*) FROM activity a WHERE a.user_id=e.user_id
                      AND a.activity_date>=e.register_date
                      AND a.activity_date<=e.register_date+INTERVAL 7 DAY) >= 3
                THEN 'Activated' ELSE 'Not Activated' END AS segment,
          EXISTS(SELECT 1 FROM activity a WHERE a.user_id=e.user_id
                  AND a.activity_date>e.register_date
                  AND a.activity_date<=e.register_date+INTERVAL 30 DAY) AS retained,
          (SELECT u.plan_type FROM users u WHERE u.user_id=e.user_id) AS plan_type
          FROM e)
    SELECT segment, COUNT(*) AS users,
           SUM(CASE WHEN retained THEN 1 ELSE 0 END) AS retained_users,
           ROUND(100.0*SUM(CASE WHEN retained THEN 1 ELSE 0 END)/COUNT(*),2) AS retention_pct,
           SUM(CASE WHEN plan_type<>'Free' THEN 1 ELSE 0 END) AS paid_users,
           ROUND(100.0*SUM(CASE WHEN plan_type<>'Free' THEN 1 ELSE 0 END)/COUNT(*),2) AS paid_pct
    FROM l GROUP BY segment
) TO 'tableau/activation_lift.csv' (HEADER, DELIMITER ',');
```

跑一次得到 `tableau/activation_lift.csv`，在 Tableau 里连进去：

- `segment` → Columns
- `retention_pct` 和 `paid_pct` → Rows（两个 measure 并排）
- Marks 选 Bar，Label 显示数字

这张图直接证明"激活让付费率近乎翻倍"——回答 Q26 / 业务洞察核心。

### 3.6 组装 D3

布局：顶部 5 个 KPI → 中间巨大 Cohort 热力图（占 50% 屏幕）→ 底部三个分群对比小图。

📸 **截图机会 3**：D3 完成，特别是单独高清 Cohort 热力图。

---

## 4. Dashboard 4: Revenue & Customer Health（45 分钟）

**目标**：CFO / CS 看收入结构和客户健康
**用到的 CSV**：`v_mrr_trend.csv`、`v_revenue_by_channel.csv`、`v_revenue_by_plan.csv`、`v_renewal_analysis.csv`、Pareto 自定义 CSV、Top 10 客户自定义 CSV

### 4.1 MRR + ARR 双轴（`D4_MRR_ARR`）

复用 D1.1 的 MRR 趋势，但加上 ARR：

- 双轴换成 mrr + arr
- 颜色 mrr 深蓝、arr 浅蓝
- Synchronize Axis 这次**勾上**（同一个尺度）

### 4.2 套餐收入构成（堆叠面积图）（`D4_Plan_Revenue_Stack`）

需要补一个新 CSV——按月 × 套餐的 MRR 拆解。在 DuckDB 跑：

```sql
COPY (
    WITH active AS (
        SELECT s.user_id, u.plan_type,
               DATE_TRUNC('month', payment_date) AS start_month,
               CASE WHEN subscription_type='Monthly' THEN DATE_TRUNC('month', payment_date)
                    WHEN subscription_type='Annual' THEN DATE_TRUNC('month', payment_date)+INTERVAL 11 MONTH END AS end_month,
               CASE WHEN subscription_type='Monthly' THEN amount
                    WHEN subscription_type='Annual' THEN amount/12.0 END AS mv
        FROM subscription s JOIN users u USING(user_id)
        WHERE payment_status='Success'
    ),
    cal AS (SELECT DATE_TRUNC('month',d)::DATE AS m FROM generate_series(
        (SELECT MIN(start_month) FROM active),
        (SELECT MAX(start_month) FROM active)+INTERVAL 12 MONTH,
        INTERVAL 1 MONTH) AS t(d))
    SELECT cal.m AS month_start, a.plan_type, ROUND(SUM(a.mv),2) AS mrr
    FROM cal LEFT JOIN active a ON cal.m BETWEEN a.start_month AND a.end_month
    GROUP BY 1, 2 ORDER BY 1, 2
) TO 'tableau/mrr_by_plan.csv' (HEADER, DELIMITER ',');
```

然后连这个 CSV：

- `month_start` → Columns
- `mrr` → Rows
- `plan_type` → Color
- Marks type `Area`，自然 stacked

### 4.3 渠道收入横向条（`D4_Channel_Revenue_Bar`）

数据源：`v_revenue_by_channel.csv`

- `acquisition_channel` → Rows
- `revenue` → Columns
- 排序降序
- `revenue_share_pct` → Label（显示百分比）
- 颜色用单一色 + 渐变（按 revenue 高低）

### 4.4 Pareto 收入集中度（`D4_Pareto`）

需要新 CSV：

```sql
COPY (
    WITH ur AS (SELECT user_id, SUM(amount) AS rev FROM subscription
                WHERE payment_status='Success' GROUP BY user_id),
    r AS (SELECT *, NTILE(100) OVER (ORDER BY rev DESC) AS pct_rank,
                  SUM(rev) OVER () AS total_rev FROM ur)
    SELECT CASE WHEN pct_rank=1 THEN 'Top 1%'
                WHEN pct_rank<=10 THEN 'Top 10%'
                WHEN pct_rank<=20 THEN 'Top 20%'
                WHEN pct_rank<=50 THEN 'Top 50%'
                ELSE 'Bottom 50%' END AS segment,
           MIN(pct_rank) AS sort_order,
           COUNT(*) AS users,
           ROUND(SUM(rev),2) AS revenue,
           ROUND(100.0*SUM(rev)/MAX(total_rev),2) AS share_pct
    FROM r GROUP BY segment ORDER BY sort_order
) TO 'tableau/pareto.csv' (HEADER, DELIMITER ',');
```

- `segment` → Columns（按 sort_order 排序）
- `revenue` → Rows（bar）
- 加双轴 `share_pct` 累加 → 拖到右轴做 line + label
  - 累计计算：右键 share_pct → Quick Table Calculation → Running Total

### 4.5 Top 10 高价值客户表（`D4_Top10`）

新 CSV：

```sql
COPY (
    SELECT u.user_id, u.country, u.acquisition_channel, u.plan_type, u.company_size,
           ROUND(SUM(s.amount), 2) AS lifetime_revenue,
           COUNT(s.subscription_id) AS payments,
           MAX(s.payment_date) AS last_payment
    FROM users u JOIN subscription s ON s.user_id=u.user_id
    WHERE s.payment_status='Success'
    GROUP BY u.user_id, u.country, u.acquisition_channel, u.plan_type, u.company_size
    ORDER BY lifetime_revenue DESC LIMIT 10
) TO 'tableau/top10_customers.csv' (HEADER, DELIMITER ',');
```

Tableau 里：

- 所有字段拖到 Rows（按顺序：user_id, country, channel, plan, company_size, lifetime_revenue, payments）
- Marks type `Text`
- 按 lifetime_revenue 降序

这就是个普通表格，但放在 dashboard 里能让 CS 团队对号入座，很实用。

### 4.6 续费率 × 套餐 Combo（`D4_Renewal_Combo`）

数据源：`v_renewal_analysis.csv`，filter `segment_type` = `plan`

- `segment` → Columns
- `renewal_pct` → Rows（bar）
- `avg_payments` → Rows（再拖一个，双轴）
- bar 蓝色、line 橙色

### 4.7 组装 D4

布局：顶部 6 个 KPI → MRR+ARR 大趋势 → 中间左右 Plan Stack 和 Channel Bar → 底部 Pareto + Top10 表 + Renewal Combo。

📸 **截图机会 4**：D4 完成。

---

## 5. 全局筛选器（Global Filters）（20 分钟）

跨 dashboard 筛选器，让看板"活"起来：

### 5.1 创建 Date / Channel / Plan 三个筛选器

在任一 worksheet 上：
- 把 `month_start` 拖到 Filters → 选 Range of Dates
- 右键 filter → `Apply to Worksheets` → `Selected Worksheets` → 全选

Channel 同理，但有个问题：每个 CSV 都是聚合好的，不一定都有 `acquisition_channel` 列。所以 Channel 筛选器只能影响包含该字段的 worksheet（比如 v_revenue_by_channel、v_paid_conversion）。

### 5.2 显示在 Dashboard

在 dashboard 上：点 worksheet 右上角下拉箭头 → `Filters` → 选要显示的字段。
然后拖动到 dashboard 顶部，调整为水平 dropdown 样式。

### 5.3 图与图联动

在 dashboard 上点击某图右上角 → `Use as Filter`。
比如把渠道 donut 设成 filter，点击某块就过滤所有其他图。

---

## 6. 整体 Polish（30 分钟）

让 dashboard 看起来"上得了简历"，不是 Tableau 默认丑样：

### 6.1 配色统一

去 `Format` → `Workbook` → 设置一套色板：
- 主色：`#2563EB`（品牌蓝）
- 强调：`#10B981`（绿）
- 警示：`#EF4444`（红）
- 中性：`#6B7280`（灰）

### 6.2 字体统一

- Title：Arial Bold 14
- Body：Arial Regular 10
- Numbers：Arial Bold 28（KPI 大数字）

### 6.3 去除视觉噪音

- 去掉 gridlines：右键 axis → Format → Lines → None
- 去掉 worksheet 边框
- 调整 spacing：拖动 worksheet 之间留 8-12px 间距

### 6.4 加 dashboard 标题

每个 dashboard 顶部加 Text object：
- "Executive Overview · SaaS Growth Analysis"
- 加副标题写时间窗口："Data: 2024-01 to 2025-12"

### 6.5 加数据源说明

底部加小字脚注："Data is simulated based on realistic SaaS business patterns. Source: github.com/<你的用户名>/saas-growth-analysis"

---

## 7. 导出 & 截图（15 分钟）

### 7.1 发布到 Tableau Public

`File` → `Save to Tableau Public As...`
登录你的 Public 账号，输入 workbook 名（建议 `SaaS Growth Analytics`）。
保存后会自动打开浏览器，你的看板就在公网上了。

URL 长这样：`https://public.tableau.com/views/SaaSGrowthAnalytics/...`

### 7.2 截图

3 种截图都做：

**(a) 单 dashboard 全图**（4 张）
- 在 Tableau Public 网页上，每个 dashboard 用浏览器全屏，按 `Cmd+Shift+4` (Mac) 或截图工具截
- 建议截图尺寸 1400×900 或更大

**(b) 关键单图特写**（重点 3 张）
- Cohort 热力图（单独一张）
- 漏斗图（单独一张）
- MRR 趋势（单独一张）
- 这三张视觉冲击力最强，放 README 顶部

**(c) 缩略图组合**（1 张）
- 把 4 个 dashboard 截图拼成 2×2 网格
- 用 Figma / Canva / 截图工具的拼图功能
- 这是 GitHub 主图

### 7.3 截图存哪里

```
saas-growth-analysis/
└── docs/
    └── screenshots/        ← 新建
        ├── d1_executive_overview.png
        ├── d2_acquisition_funnel.png
        ├── d3_retention.png
        ├── d4_revenue.png
        ├── cohort_heatmap_closeup.png  ← 招牌
        ├── funnel_closeup.png
        ├── mrr_trend_closeup.png
        └── dashboard_grid_thumbnail.png
```

### 7.4 更新 README

在 README 顶部"项目背景"之前加一段：

```markdown
## Dashboards

[![Cohort Heatmap](docs/screenshots/cohort_heatmap_closeup.png)](https://public.tableau.com/views/...)

完整 4 个 dashboard 在线版：[Tableau Public](https://public.tableau.com/views/...)

| Dashboard | 受众 | 预览 |
|---|---|---|
| Executive Overview | 高管 | ![](docs/screenshots/d1_executive_overview.png) |
| Acquisition & Funnel | 增长 | ![](docs/screenshots/d2_acquisition_funnel.png) |
| Retention | 产品 | ![](docs/screenshots/d3_retention.png) |
| Revenue & Customer | CFO/CS | ![](docs/screenshots/d4_revenue.png) |
```

简历上也放一张 Cohort 热力图 + Tableau Public URL。

---

## 8. 常见踩坑

| 问题 | 解决 |
|---|---|
| Cohort 热力图列太多挤在一起 | Filter `months_since_register` ≤ 12 |
| 日期字段被识别成字符串 | 右键 → Change Data Type → Date |
| 百分比显示成 0.4066 | Format Number → Percentage → 2 decimals |
| 双轴两条线尺度差太多看不清 | 取消 Synchronize Axis |
| MoM% 算出来不对 | 用 Table Calculation → Percent Difference → 沿 Table Across |
| 公司规模 / 套餐排序乱 | 右键字段 → Sort → Manual → 拖动 |
| Dashboard 看起来很挤 | 用 Container 控制布局，给每个区块留 padding |
| 颜色太花 | 全局色板限制到 3-4 个色调，多了就乱 |
| Tableau Public 保存提示要联网 | 必须有账号 + 必须公开，这是 Public 版的限制 |
| Tableau 卡顿 | 关掉不用的 worksheet，data source 太多时切换会慢 |

---

## 9. 时间预算 vs 加分项 vs 偷懒方案

| 加分项 | 时间 | 简历价值 | 偷懒方案 |
|---|---|---|---|
| Cohort 热力图（单独） | 30 min | ⭐⭐⭐⭐⭐ | 必做 |
| 漏斗图（单独） | 20 min | ⭐⭐⭐⭐ | 必做 |
| MRR 趋势 | 15 min | ⭐⭐⭐⭐ | 必做 |
| Dashboard 1 (Exec) | 45 min | ⭐⭐⭐⭐⭐ | 必做 |
| Dashboard 2 (Funnel) | 45 min | ⭐⭐⭐⭐ | 推荐 |
| Dashboard 3 (Retention) | 45 min | ⭐⭐⭐⭐⭐ | 必做（含 Cohort） |
| Dashboard 4 (Revenue) | 45 min | ⭐⭐⭐ | 可后做 |
| 全局筛选器 + 联动 | 20 min | ⭐⭐⭐ | 可省 |
| Polish (配色字体) | 30 min | ⭐⭐⭐⭐ | 推荐 |
| 截图 + 上传 GitHub | 15 min | ⭐⭐⭐⭐⭐ | 必做 |

**最小可发布版本（MVP, ~2 小时）**：
Dashboard 1（Exec Overview）+ Dashboard 3（Retention，含 Cohort 热力图）+ Polish + 截图。

这两个 dashboard 足以撑起整个项目的视觉门面，后两个可以之后慢慢补。

---

## 10. 检查清单（搭完之后过一遍）

- [ ] 所有日期字段是 Date 类型，不是 String
- [ ] 所有百分比字段格式化为 % 而不是 0.xx
- [ ] 每个 dashboard 有清晰标题 + 时间窗口副标题
- [ ] 颜色全局统一（主色 + 强调 + 中性 3 色板）
- [ ] 没有默认的 Tableau 配色（蓝橙色搭配是 AI 感最强的特征）
- [ ] KPI 数字字号 ≥ 24pt，加粗
- [ ] Cohort 热力图能看清每个格子的数字
- [ ] 漏斗图标签同时显示绝对人数和百分比
- [ ] Dashboard 大小固定（不要 Automatic，截图会变形）
- [ ] 已发布到 Tableau Public，能拿到公开 URL
- [ ] 截图存到 `docs/screenshots/` 目录
- [ ] README 顶部已加 Tableau Public 链接和招牌截图
- [ ] 简历上写了 Tableau Public URL

---

完成后你会有：

1. **公开的 Tableau Public 链接** —— 简历放一行就够
2. **4 张 dashboard 全图 + 3 张特写** —— GitHub README 撑场面
3. **完整的"数据 → 分析 → 可视化"叙事** —— 面试 demo 时打开看板，效果远胜对着 SQL 讲

到这一步，整个项目从"个人练手"升级成"可对外展示的作品"。
