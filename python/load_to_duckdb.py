# -*- coding: utf-8 -*-
"""
================================================================
SaaS 平台用户增长与经营分析  ——  DuckDB 数据导入脚本
================================================================

功能：
    1. 自动创建 DuckDB 数据库   data/saas_analysis.duckdb
    2. 自动读取 data/ 下的三张 CSV
    3. 用显式 schema 建表（带主键、合理类型），便于后续分析
    4. 将 CSV 导入对应表
    5. 自动执行 SHOW TABLES 和 SELECT COUNT(*) 验证
    6. 检查 activity / subscription 是否存在孤立 user_id
    7. 打印各表前 5 行预览

使用：
    cd saas-growth-analysis/
    python python/load_to_duckdb.py
================================================================
"""

import os
import sys
import subprocess

# ----------------------------------------------------------------
# 0. 自动安装 duckdb（如果当前 Python 环境没装）
# ----------------------------------------------------------------
try:
    import duckdb
except ImportError:
    print("[依赖] 当前 Python 缺少 duckdb，正在 pip 安装 ...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "duckdb"])
    import duckdb


# ----------------------------------------------------------------
# 1. 路径配置（脚本位于 python/，项目根目录是上一级）
# ----------------------------------------------------------------
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR     = os.path.join(PROJECT_ROOT, "data")
DB_PATH      = os.path.join(DATA_DIR, "saas_analysis.duckdb")

USERS_CSV        = os.path.join(DATA_DIR, "users.csv")
ACTIVITY_CSV     = os.path.join(DATA_DIR, "activity.csv")
SUBSCRIPTION_CSV = os.path.join(DATA_DIR, "subscription.csv")


def banner(title: str) -> None:
    """打印分节标题，便于阅读输出。"""
    print("\n" + "=" * 64)
    print(f"  {title}")
    print("=" * 64)


# ----------------------------------------------------------------
# 2. 主流程
# ----------------------------------------------------------------
def main() -> None:
    banner("SaaS 数据导入 DuckDB")
    print(f"  Python      : {sys.executable}")
    print(f"  DuckDB 版本 : {duckdb.__version__}")
    print(f"  数据库文件  : {DB_PATH}")

    # 2.1 检查 CSV 文件是否齐全
    for path in (USERS_CSV, ACTIVITY_CSV, SUBSCRIPTION_CSV):
        if not os.path.exists(path):
            sys.exit(f"❌ 找不到 CSV：{path}\n   请先运行 python/generate_data.py")

    # 2.2 删除旧库，保证脚本可重复执行（每次都是干净状态）
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
        print(f"\n[清理] 已删除旧库 {DB_PATH}")

    # 2.3 连接（文件不存在则创建）
    con = duckdb.connect(DB_PATH)

    # ------------------------------------------------------------
    # 3. 创建表（显式 schema + 主键 + 合理类型）
    #     主键约束 = 帮助后续 JOIN 时的语义清晰，也防止重复 ID
    # ------------------------------------------------------------
    banner("创建表结构")

    # ---- users ----
    con.execute("""
        CREATE TABLE users (
            user_id              VARCHAR PRIMARY KEY,
            register_date        DATE,
            country              VARCHAR,
            device_type          VARCHAR,
            acquisition_channel  VARCHAR,
            plan_type            VARCHAR,
            company_size         VARCHAR
        );
    """)
    print("  ✓ users           已创建")

    # ---- activity ----
    con.execute("""
        CREATE TABLE activity (
            activity_id       VARCHAR PRIMARY KEY,
            user_id           VARCHAR,
            activity_date     DATE,
            session_duration  INTEGER,
            pages_viewed      INTEGER,
            feature_used      VARCHAR
        );
    """)
    print("  ✓ activity        已创建")

    # ---- subscription ----
    con.execute("""
        CREATE TABLE subscription (
            subscription_id    VARCHAR PRIMARY KEY,
            user_id            VARCHAR,
            payment_date       DATE,
            amount             DOUBLE,
            subscription_type  VARCHAR,
            payment_status     VARCHAR
        );
    """)
    print("  ✓ subscription    已创建")

    # ------------------------------------------------------------
    # 4. 从 CSV 批量导入
    #     用 read_csv_auto + INSERT INTO，让 DuckDB 自动推断类型
    #     再由建表时的显式 schema 做最终类型约束
    # ------------------------------------------------------------
    banner("从 CSV 导入数据")

    con.execute(f"""
        INSERT INTO users
        SELECT * FROM read_csv_auto('{USERS_CSV}', header=True);
    """)
    print(f"  ✓ users           ← {USERS_CSV}")

    con.execute(f"""
        INSERT INTO activity
        SELECT * FROM read_csv_auto('{ACTIVITY_CSV}', header=True);
    """)
    print(f"  ✓ activity        ← {ACTIVITY_CSV}")

    con.execute(f"""
        INSERT INTO subscription
        SELECT * FROM read_csv_auto('{SUBSCRIPTION_CSV}', header=True);
    """)
    print(f"  ✓ subscription    ← {SUBSCRIPTION_CSV}")

    # ------------------------------------------------------------
    # 5. SHOW TABLES
    # ------------------------------------------------------------
    banner("SHOW TABLES")
    tables = con.execute("SHOW TABLES").fetchall()
    for (name,) in tables:
        print(f"  - {name}")

    # ------------------------------------------------------------
    # 6. 各表行数（业务用 COUNT(*) 验证导入完整性）
    # ------------------------------------------------------------
    banner("行数验证 (SELECT COUNT(*))")
    for tbl in ("users", "activity", "subscription"):
        n = con.execute(f"SELECT COUNT(*) FROM {tbl}").fetchone()[0]
        print(f"  {tbl:15s} {n:>7,d} 行")

    # ------------------------------------------------------------
    # 7. 外键完整性检查
    #     activity.user_id / subscription.user_id 必须能在 users 找到
    # ------------------------------------------------------------
    banner("外键完整性检查")

    orphan_act = con.execute("""
        SELECT COUNT(*) FROM activity a
        LEFT JOIN users u ON a.user_id = u.user_id
        WHERE u.user_id IS NULL
    """).fetchone()[0]
    print(f"  activity     孤立 user_id 数：{orphan_act}  "
          f"{'✓ 通过' if orphan_act == 0 else '❌ 有问题'}")

    orphan_sub = con.execute("""
        SELECT COUNT(*) FROM subscription s
        LEFT JOIN users u ON s.user_id = u.user_id
        WHERE u.user_id IS NULL
    """).fetchone()[0]
    print(f"  subscription 孤立 user_id 数：{orphan_sub}  "
          f"{'✓ 通过' if orphan_sub == 0 else '❌ 有问题'}")

    # ------------------------------------------------------------
    # 8. 表结构 + 数据预览
    # ------------------------------------------------------------
    banner("表结构 (DESCRIBE)")
    for tbl in ("users", "activity", "subscription"):
        print(f"\n--- {tbl} ---")
        print(con.execute(f"DESCRIBE {tbl}").df()
              .to_string(index=False))

    banner("数据预览 (LIMIT 5)")
    for tbl in ("users", "activity", "subscription"):
        print(f"\n--- {tbl} ---")
        print(con.execute(f"SELECT * FROM {tbl} LIMIT 5").df()
              .to_string(index=False))

    con.close()

    banner("✅ 全部完成")
    print(f"  数据库已就绪：{DB_PATH}")
    print("  后续在 Jupyter / Python 脚本中：")
    print("      import duckdb")
    print(f"      con = duckdb.connect('{DB_PATH}')")
    print("      con.execute('SELECT * FROM users LIMIT 10').df()")


if __name__ == "__main__":
    main()
