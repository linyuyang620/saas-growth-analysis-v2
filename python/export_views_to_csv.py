# -*- coding: utf-8 -*-
"""
================================================================
SaaS 平台用户增长与经营分析  ——  DuckDB 视图导出脚本
================================================================

功能：
    把 DuckDB 中的 9 个 Tableau-ready 视图全部导出为 CSV，
    写入 tableau/ 目录，供 Tableau Public 直接连接使用。
    （Tableau Public 不支持 DuckDB 直连，必须走 CSV）

幂等性：
    - 如果检测到视图缺失（例如用户刚跑过 load_to_duckdb.py
      重建了数据库），会自动执行 sql/02、03、04 把视图建回来
    - 每次运行都会覆盖 tableau/ 下的旧 CSV，保证内容最新

使用：
    cd saas-growth-analysis/
    python python/export_views_to_csv.py
================================================================
"""

import os
import sys
import glob
import re
import subprocess

# ----------------------------------------------------------------
# 0. 自动安装 duckdb
# ----------------------------------------------------------------
try:
    import duckdb
except ImportError:
    print("[依赖] 当前 Python 缺少 duckdb，正在 pip 安装 ...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "duckdb"])
    import duckdb


# ----------------------------------------------------------------
# 1. 路径
# ----------------------------------------------------------------
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR     = os.path.join(PROJECT_ROOT, "data")
DB_PATH      = os.path.join(DATA_DIR,    "saas_analysis.duckdb")
TABLEAU_DIR  = os.path.join(PROJECT_ROOT, "tableau")
SQL_DIR      = os.path.join(PROJECT_ROOT, "sql")

# 自动创建 tableau/ 目录
os.makedirs(TABLEAU_DIR, exist_ok=True)


# ----------------------------------------------------------------
# 2. 视图清单（顺序 = Tableau 看板里的使用频率）
#     name              : 视图名（DuckDB 中）
#     dashboard         : 主要服务于哪个看板
#     primary_use       : 用于哪类图表
# ----------------------------------------------------------------
VIEWS = [
    # —— Dashboard 1: Executive Overview ——
    ("v_mrr_trend",             "D1 / D4", "MRR/ARR 时序图"),
    ("v_funnel_summary",        "D1 / D2", "漏斗 5 段（柱形 / 桑基）"),
    ("v_revenue_by_channel",    "D1 / D4", "渠道收入 Donut / 横向 Bar"),
    ("v_revenue_by_plan",       "D1 / D4", "套餐收入 Donut / 堆叠图"),

    # —— Dashboard 2: Acquisition & Funnel ——
    ("v_activation_analysis",   "D2",      "激活率 long-format（分渠道/套餐）"),
    ("v_paid_conversion",       "D2 / D4", "付费率 long-format（含设备/公司规模）"),

    # —— Dashboard 3: Engagement & Retention ——
    ("cohort_retention_tableau","D3",      "Cohort 留存热力图（主图）"),
    ("retention_tableau",       "D3",      "留存曲线（分渠道/分套餐）"),

    # —— Dashboard 4: Revenue & Customer Health ——
    ("v_renewal_analysis",      "D4",      "续费率多维 + 平均付款次数"),
]


def banner(title: str) -> None:
    print("\n" + "=" * 64)
    print(f"  {title}")
    print("=" * 64)


# ----------------------------------------------------------------
# 3. 工具函数
# ----------------------------------------------------------------
def get_existing_views(con) -> set:
    """返回数据库中现有的所有非系统视图名集合。"""
    rows = con.execute(
        "SELECT view_name FROM duckdb_views WHERE NOT internal"
    ).fetchall()
    return {r[0] for r in rows}


def run_sql_file(con, path: str) -> None:
    """
    执行一个 SQL 文件（按分号切分逐条执行）。
    用于：当视图缺失时，重新跑 sql/02、03、04 把视图建回来。
    SELECT 类语句也会被执行但无副作用，可接受。
    """
    sql_text = open(path, encoding="utf-8").read()
    # 简单移除单行注释
    lines = [l for l in sql_text.splitlines() if not l.strip().startswith("--")]
    stmts = [s.strip() for s in "\n".join(lines).split(";") if s.strip()]
    for s in stmts:
        try:
            con.execute(s)
        except Exception as e:
            # 容错：某些 SELECT 失败不影响视图创建
            print(f"    ⚠ 跳过失败语句：{str(e)[:80]}")


def ensure_views_exist(con, required: list) -> None:
    """检查视图是否齐全，缺少则自动从 sql/ 重新创建。"""
    existing = get_existing_views(con)
    missing  = [v for v in required if v not in existing]
    if not missing:
        print("  ✓ 所有视图已就绪")
        return

    print(f"  ⚠ 检测到 {len(missing)} 个视图缺失：{missing}")
    print("  → 自动从 sql/ 重新创建 ...")

    # sql/02、03、04 各创建一部分视图，全跑一遍即可
    for sql_path in sorted(glob.glob(os.path.join(SQL_DIR, "0[234]_*.sql"))):
        print(f"    执行 {os.path.basename(sql_path)} ...")
        run_sql_file(con, sql_path)

    # 二次校验
    existing = get_existing_views(con)
    still_missing = [v for v in required if v not in existing]
    if still_missing:
        sys.exit(f"❌ 视图重建后仍缺失：{still_missing}\n"
                 f"   请手动检查 sql/ 中的 CREATE VIEW 语句")
    print("  ✓ 视图已重建")


# ----------------------------------------------------------------
# 4. 主流程
# ----------------------------------------------------------------
def main() -> None:
    banner("DuckDB 视图 → Tableau CSV 导出")
    print(f"  数据库     : {DB_PATH}")
    print(f"  输出目录   : {TABLEAU_DIR}")
    print(f"  视图数量   : {len(VIEWS)}")

    # 4.1 校验数据库存在
    if not os.path.exists(DB_PATH):
        sys.exit(f"❌ 找不到 DuckDB 文件：{DB_PATH}\n"
                 f"   请先运行：python python/load_to_duckdb.py")

    # 4.2 连接（read-write，因为可能需要重建视图）
    con = duckdb.connect(DB_PATH)

    # 4.3 确保视图存在
    banner("Step 1/2 — 校验视图")
    required = [v[0] for v in VIEWS]
    ensure_views_exist(con, required)

    # 4.4 逐个导出 CSV
    banner("Step 2/2 — 导出 CSV")
    summary = []
    for name, dashboard, use in VIEWS:
        csv_path = os.path.join(TABLEAU_DIR, f"{name}.csv")
        # 行数（先 count 一下，方便打印）
        n_rows = con.execute(f"SELECT COUNT(*) FROM {name}").fetchone()[0]
        # DuckDB COPY：UTF-8 / 带表头 / 逗号分隔（Tableau 默认友好）
        con.execute(
            f"COPY {name} TO '{csv_path}' "
            f"(FORMAT CSV, HEADER, DELIMITER ',')"
        )
        size_kb = os.path.getsize(csv_path) / 1024
        summary.append((name, dashboard, n_rows, size_kb, use))
        print(f"  ✓ {name:30s} {n_rows:>6,d} 行  {size_kb:>7.1f} KB")

    con.close()

    # 4.5 写一个 manifest，方便 Tableau 里挑视图
    manifest_path = os.path.join(TABLEAU_DIR, "_manifest.csv")
    with open(manifest_path, "w", encoding="utf-8") as f:
        f.write("view_name,dashboard,rows,size_kb,primary_use\n")
        for name, dash, n, kb, use in summary:
            f.write(f"{name},{dash},{n},{kb:.1f},{use}\n")
    print(f"\n  ✓ Manifest    : {manifest_path}")

    # 4.6 总结
    banner("✅ 全部完成")
    print(f"  导出文件数 : {len(VIEWS)} 个视图 + 1 个 manifest")
    print(f"  位置       : {TABLEAU_DIR}")
    print()
    print("  下一步（Tableau Public）：")
    print("    1. 打开 Tableau Public Desktop")
    print("    2. Connect → To a File → Text File")
    print(f"    3. 选择 {TABLEAU_DIR} 下的任一 CSV")
    print("    4. 在 Data Source 页用 UNION / JOIN 把多个 CSV 合并")
    print()
    print("  或者：Tableau Desktop (付费版) 可用 DuckDB JDBC 直连数据库，")
    print(f"        无需 CSV 中转，连 {DB_PATH} 即可。")


if __name__ == "__main__":
    main()
