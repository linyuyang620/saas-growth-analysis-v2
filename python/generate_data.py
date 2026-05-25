# -*- coding: utf-8 -*-
"""
SaaS 平台用户增长与经营分析 —— 模拟数据生成脚本
================================================================

本脚本生成三张接近真实 SaaS 业务规律的数据表：

    1. users.csv          —— 用户注册信息
    2. activity.csv       —— 用户行为活动
    3. subscription.csv   —— 用户订阅付费记录

数据生成原则（区别于纯随机）：

    - 渠道差异：Organic / Social Media 的用户活跃度与转化率高于 Email
    - 套餐差异：Enterprise > Pro > Basic > Free（活跃度与 ARPU）
    - 设备差异：Desktop 用户中 Enterprise 占比更高
    - 行为关联：活跃度高、浏览页数多的用户更可能付费/升级
    - 时间合理：activity_date 在 register_date 之后；
                  payment_date 在 register_date 之后

输出位置：
    saas-growth-analysis/data/users.csv
    saas-growth-analysis/data/activity.csv
    saas-growth-analysis/data/subscription.csv
"""

import os
import numpy as np
import pandas as pd
from datetime import datetime, timedelta

# ----------------------------------------------------------------
# 0. 全局配置
# ----------------------------------------------------------------

# 固定随机种子，保证结果可复现
np.random.seed(42)

# 项目根目录（脚本位于 python/ 子目录，所以根目录是上一级）
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(PROJECT_ROOT, "data")

# 自动创建 data 文件夹（若不存在）
os.makedirs(DATA_DIR, exist_ok=True)

# 业务时间窗口（2024-01-01 至 2025-12-31，共 2 年）
START_DATE = datetime(2024, 1, 1)
END_DATE = datetime(2025, 12, 31)
TOTAL_DAYS = (END_DATE - START_DATE).days

# 数据量
N_USERS = 5500  # 用户数（>5000）


# ----------------------------------------------------------------
# 1. 业务规则字典（核心：把业务规律写成可调权重）
# ----------------------------------------------------------------

# 1.1 渠道权重 —— 渠道分布
CHANNELS = ["Organic", "Social Media", "Google Ads", "Email"]
CHANNEL_WEIGHTS = [0.30, 0.25, 0.30, 0.15]  # 概率分布

# 1.2 渠道 → 活跃度系数（影响 session 数量、时长、页数）
CHANNEL_ENGAGEMENT = {
    "Organic":      1.30,   # 自然流量：用户主动来，留存活跃最高
    "Social Media": 1.20,   # 社交媒体：传播性强，用户质量较高
    "Google Ads":   1.00,   # 付费广告：标准基线
    "Email":        0.70,   # 邮件营销：被动触达，活跃度较低
}

# 1.3 渠道 → 付费转化率
CHANNEL_CONVERSION = {
    "Organic":      0.42,
    "Social Media": 0.36,
    "Google Ads":   0.25,
    "Email":        0.13,
}

# 1.4 国家分布（SaaS 全球化平台的典型分布）
COUNTRIES = ["US", "UK", "Germany", "India", "Japan",
             "China", "Brazil", "France", "Canada", "Australia"]
COUNTRY_WEIGHTS = [0.30, 0.10, 0.08, 0.12, 0.06,
                   0.08, 0.05, 0.06, 0.08, 0.07]

# 1.5 设备类型分布（基线，后续会按 plan_type 微调）
DEVICES = ["Desktop", "Mobile", "Tablet"]
DEVICE_WEIGHTS = [0.55, 0.35, 0.10]

# 1.6 套餐定价（USD / 月）—— 也作为订阅金额的基础
PLAN_PRICE_MONTHLY = {
    "Free":       0,
    "Basic":      12,
    "Pro":        35,
    "Enterprise": 99,
}

# 1.7 套餐 → 活跃度系数
PLAN_ENGAGEMENT = {
    "Free":       0.60,
    "Basic":      0.95,
    "Pro":        1.35,
    "Enterprise": 1.85,
}

# 1.8 公司规模分布
COMPANY_SIZES = ["1-10", "11-50", "51-200", "201-1000", "1000+"]

# 1.9 平台功能模块（feature_used 取值）
FEATURES = ["Design", "Comment", "Export", "Share", "Template", "Collaborate"]
# 不同套餐使用的功能侧重不同
FEATURE_WEIGHTS_BY_PLAN = {
    "Free":       [0.50, 0.10, 0.10, 0.10, 0.15, 0.05],
    "Basic":      [0.40, 0.15, 0.15, 0.10, 0.15, 0.05],
    "Pro":        [0.30, 0.20, 0.15, 0.10, 0.10, 0.15],
    "Enterprise": [0.25, 0.20, 0.15, 0.10, 0.05, 0.25],  # 协作功能用得多
}


# ----------------------------------------------------------------
# 2. 生成 users 表
# ----------------------------------------------------------------

def generate_users(n_users: int) -> pd.DataFrame:
    """
    生成用户表。

    生成顺序很关键：
        channel → device → plan → company_size
    因为后面的字段依赖前面的字段（业务相关性）。
    """
    print(f"[1/3] 生成 users 表（{n_users} 条）...")

    user_ids = [f"U{str(i).zfill(6)}" for i in range(1, n_users + 1)]

    # ---- 注册日期：越靠后注册的用户越多（业务增长趋势） ----
    # 用线性增长权重，越近的日期权重越大
    day_weights = np.linspace(0.5, 1.5, TOTAL_DAYS + 1)
    day_weights = day_weights / day_weights.sum()
    day_offsets = np.random.choice(TOTAL_DAYS + 1, size=n_users, p=day_weights)
    register_dates = [START_DATE + timedelta(days=int(d)) for d in day_offsets]

    # ---- 国家 ----
    countries = np.random.choice(COUNTRIES, size=n_users, p=COUNTRY_WEIGHTS)

    # ---- 获客渠道 ----
    channels = np.random.choice(CHANNELS, size=n_users, p=CHANNEL_WEIGHTS)

    # ---- 设备类型：基线分布 ----
    devices = np.random.choice(DEVICES, size=n_users, p=DEVICE_WEIGHTS)

    # ---- 套餐类型：受渠道 + 设备双重影响 ----
    # 规则：
    #   - Desktop 用户更可能成为 Enterprise
    #   - Organic/Social 渠道更可能升级到 Pro/Enterprise
    #   - Email 渠道大概率停留在 Free
    plan_types = []
    for ch, dv in zip(channels, devices):
        # 基础套餐概率
        if ch in ("Organic", "Social Media"):
            base = [0.45, 0.25, 0.20, 0.10]  # Free/Basic/Pro/Enterprise
        elif ch == "Google Ads":
            base = [0.55, 0.25, 0.15, 0.05]
        else:  # Email
            base = [0.75, 0.15, 0.07, 0.03]

        # Desktop 提升 Pro / Enterprise 概率
        if dv == "Desktop":
            base = [base[0] - 0.10, base[1], base[2] + 0.04, base[3] + 0.06]
        elif dv == "Mobile":
            # Mobile 用户更多停留在 Free / Basic
            base = [base[0] + 0.08, base[1] + 0.02, base[2] - 0.05, base[3] - 0.05]

        # 修正：确保概率非负且归一化
        base = [max(p, 0.01) for p in base]
        base = [p / sum(base) for p in base]

        plan_types.append(np.random.choice(
            ["Free", "Basic", "Pro", "Enterprise"], p=base))

    # ---- 公司规模：与套餐类型强相关 ----
    # Free 用户多为个人/小团队；Enterprise 多为大公司
    company_sizes = []
    for p in plan_types:
        if p == "Free":
            w = [0.60, 0.25, 0.10, 0.04, 0.01]
        elif p == "Basic":
            w = [0.30, 0.40, 0.20, 0.08, 0.02]
        elif p == "Pro":
            w = [0.10, 0.25, 0.35, 0.20, 0.10]
        else:  # Enterprise
            w = [0.02, 0.08, 0.20, 0.40, 0.30]
        company_sizes.append(np.random.choice(COMPANY_SIZES, p=w))

    df = pd.DataFrame({
        "user_id": user_ids,
        "register_date": [d.strftime("%Y-%m-%d") for d in register_dates],
        "country": countries,
        "device_type": devices,
        "acquisition_channel": channels,
        "plan_type": plan_types,
        "company_size": company_sizes,
    })

    print(f"      套餐分布：\n{df['plan_type'].value_counts().to_string()}")
    print(f"      渠道分布：\n{df['acquisition_channel'].value_counts().to_string()}")
    return df


# ----------------------------------------------------------------
# 3. 生成 activity 表
# ----------------------------------------------------------------

def generate_activity(users_df: pd.DataFrame) -> pd.DataFrame:
    """
    生成用户行为活动表。

    核心逻辑：
        每个用户的 session 数量 = 基础值 × 渠道系数 × 套餐系数 × 个体随机扰动
        session_duration、pages_viewed 也由同一活跃度水平驱动
        因此 "高浏览 → 高活跃 → 更可能付费" 这条业务链路天然成立
    """
    print("[2/3] 生成 activity 表 ...")

    activity_records = []
    activity_counter = 1

    # 预先把用户字段转成 ndarray，加速循环
    register_dates = pd.to_datetime(users_df["register_date"]).values
    channels = users_df["acquisition_channel"].values
    plans = users_df["plan_type"].values
    user_ids = users_df["user_id"].values

    for i in range(len(users_df)):
        uid = user_ids[i]
        reg_date = pd.Timestamp(register_dates[i]).to_pydatetime()
        ch = channels[i]
        plan = plans[i]

        # 计算个体的活跃度系数
        engagement = CHANNEL_ENGAGEMENT[ch] * PLAN_ENGAGEMENT[plan]

        # 该用户距今的可活跃天数（注册日 → END_DATE）
        days_since_reg = max((END_DATE - reg_date).days, 1)

        # session 数量：基线 8 次 × engagement × tenure 系数 × 随机扰动
        tenure_factor = min(days_since_reg / 180.0, 2.0)  # 注册时间越久，session 越多，但封顶
        base_sessions = 8 * engagement * tenure_factor
        n_sessions = max(1, int(np.random.normal(base_sessions, base_sessions * 0.4)))
        n_sessions = min(n_sessions, 60)  # 单用户最多 60 次（防止极端值）

        # session 日期：在 [reg_date, END_DATE] 区间内
        # 典型 SaaS 行为模式：注册后前 1-2 个月活动最密集，之后逐渐衰减
        # 用指数分布建模 —— scale=30 即"平均间隔 30 天"，
        # 这样首周/首月会出现自然的活动峰值，与真实 SaaS 留存曲线一致。
        if days_since_reg > 1:
            scale_days = 30.0
            session_offsets = np.random.exponential(scale=scale_days, size=n_sessions)
            session_offsets = np.clip(session_offsets, 0, days_since_reg).astype(int)
        else:
            session_offsets = np.zeros(n_sessions, dtype=int)

        # 取出该用户对应套餐的 feature 概率
        feature_w = FEATURE_WEIGHTS_BY_PLAN[plan]

        for offset in session_offsets:
            act_date = reg_date + timedelta(days=int(offset))
            if act_date > END_DATE:
                act_date = END_DATE

            # session_duration（分钟）：均值随活跃度提升
            mean_duration = 8 * engagement  # 分钟
            duration = max(1, int(np.random.gamma(shape=2.0, scale=mean_duration / 2.0)))
            duration = min(duration, 180)  # 单次最多 3 小时

            # pages_viewed：均值随活跃度提升
            mean_pages = 6 * engagement
            pages = max(1, int(np.random.gamma(shape=2.5, scale=mean_pages / 2.5)))
            pages = min(pages, 80)

            feature = np.random.choice(FEATURES, p=feature_w)

            activity_records.append({
                "activity_id":      f"A{str(activity_counter).zfill(7)}",
                "user_id":          uid,
                "activity_date":    act_date.strftime("%Y-%m-%d"),
                "session_duration": duration,
                "pages_viewed":     pages,
                "feature_used":     feature,
            })
            activity_counter += 1

    df = pd.DataFrame(activity_records)
    print(f"      共生成 {len(df)} 条活动记录")
    print(f"      session_duration 均值：{df['session_duration'].mean():.1f} 分钟")
    print(f"      pages_viewed     均值：{df['pages_viewed'].mean():.1f}")
    return df


# ----------------------------------------------------------------
# 4. 生成 subscription 表
# ----------------------------------------------------------------

def generate_subscription(users_df: pd.DataFrame,
                          activity_df: pd.DataFrame) -> pd.DataFrame:
    """
    生成订阅付费记录。

    业务规则：
        - Free 用户不产生订阅记录
        - 付费用户在注册之后会产生 1 ~ N 次付费（续费）
        - 月付/年付比例：Enterprise 更倾向年付，Basic 更倾向月付
        - 极少数支付失败 / 退款
        - 活跃度高的用户续费次数更多
    """
    print("[3/3] 生成 subscription 表 ...")

    # 先按 user_id 汇总活动次数（用于驱动续费次数）
    activity_count = activity_df.groupby("user_id").size().to_dict()

    sub_records = []
    sub_counter = 1

    for _, row in users_df.iterrows():
        plan = row["plan_type"]
        if plan == "Free":
            continue  # Free 用户不生成订阅记录

        uid = row["user_id"]
        reg_date = datetime.strptime(row["register_date"], "%Y-%m-%d")
        n_acts = activity_count.get(uid, 0)

        # 订阅类型：Enterprise 偏年付，Basic 偏月付
        if plan == "Enterprise":
            sub_type = np.random.choice(["Monthly", "Annual"], p=[0.30, 0.70])
        elif plan == "Pro":
            sub_type = np.random.choice(["Monthly", "Annual"], p=[0.55, 0.45])
        else:  # Basic
            sub_type = np.random.choice(["Monthly", "Annual"], p=[0.75, 0.25])

        # 计算最大可能的续费次数（基于注册到当前的时长）
        months_since_reg = max(1, (END_DATE - reg_date).days // 30)

        # 续费次数：活跃用户续费次数更多
        # 基础值受套餐和活动量影响
        engagement_score = (PLAN_ENGAGEMENT[plan] *
                            CHANNEL_ENGAGEMENT[row["acquisition_channel"]] *
                            (1 + min(n_acts, 30) / 30.0))

        if sub_type == "Monthly":
            # 月付：理论上最多 months_since_reg 次，乘以一个流失系数
            max_renewals = min(months_since_reg, int(6 * engagement_score))
            n_subs = max(1, int(np.random.uniform(1, max_renewals + 1)))
        else:
            # 年付：通常 1-2 次
            n_subs = 1 if months_since_reg < 12 else np.random.choice([1, 2], p=[0.7, 0.3])

        # 单价（USD）
        if sub_type == "Monthly":
            base_amount = PLAN_PRICE_MONTHLY[plan]
        else:
            # 年付通常打 8 折左右（12 * 0.8 = 9.6 个月的价格）
            base_amount = PLAN_PRICE_MONTHLY[plan] * 10

        # 产生 n_subs 条付费记录
        for k in range(n_subs):
            # 第 k 次付费的日期
            if sub_type == "Monthly":
                pay_date = reg_date + timedelta(days=30 * k + np.random.randint(0, 3))
            else:
                pay_date = reg_date + timedelta(days=365 * k + np.random.randint(0, 7))

            if pay_date > END_DATE:
                break  # 超过当前时间窗口的付费记录不生成

            # 金额：在基础价附近浮动（折扣、税费、汇率等）
            amount = round(base_amount * np.random.uniform(0.95, 1.05), 2)

            # 支付状态：96% 成功，3% 失败，1% 退款
            status = np.random.choice(
                ["Success", "Failed", "Refunded"], p=[0.96, 0.03, 0.01])

            sub_records.append({
                "subscription_id":   f"S{str(sub_counter).zfill(6)}",
                "user_id":           uid,
                "payment_date":      pay_date.strftime("%Y-%m-%d"),
                "amount":            amount,
                "subscription_type": sub_type,
                "payment_status":    status,
            })
            sub_counter += 1

    df = pd.DataFrame(sub_records)
    print(f"      共生成 {len(df)} 条订阅记录")
    print(f"      支付状态分布：\n{df['payment_status'].value_counts().to_string()}")
    print(f"      订阅类型分布：\n{df['subscription_type'].value_counts().to_string()}")
    return df


# ----------------------------------------------------------------
# 5. 主流程
# ----------------------------------------------------------------

def main():
    print("=" * 60)
    print("SaaS 用户增长与经营分析 —— 数据生成")
    print(f"输出目录：{DATA_DIR}")
    print("=" * 60)

    users_df        = generate_users(N_USERS)
    activity_df     = generate_activity(users_df)
    subscription_df = generate_subscription(users_df, activity_df)

    # 导出 CSV（UTF-8 编码，不写入索引）
    users_path        = os.path.join(DATA_DIR, "users.csv")
    activity_path     = os.path.join(DATA_DIR, "activity.csv")
    subscription_path = os.path.join(DATA_DIR, "subscription.csv")

    users_df.to_csv(users_path,               index=False, encoding="utf-8")
    activity_df.to_csv(activity_path,         index=False, encoding="utf-8")
    subscription_df.to_csv(subscription_path, index=False, encoding="utf-8")

    print("\n" + "=" * 60)
    print("生成完成！文件已写入：")
    print(f"  - {users_path}        ({len(users_df)} 行)")
    print(f"  - {activity_path}     ({len(activity_df)} 行)")
    print(f"  - {subscription_path} ({len(subscription_df)} 行)")
    print("=" * 60)


if __name__ == "__main__":
    main()
