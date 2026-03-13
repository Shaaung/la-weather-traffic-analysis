import os
from pathlib import Path
import snowflake.connector

def clean(name: str) -> str:
    return os.environ[name].replace("\r", "").strip()

def main() -> None:
    conn = snowflake.connector.connect(
        user=clean("SNOWFLAKE_USER"),
        password=clean("SNOWFLAKE_PASSWORD"),
        account=clean("SNOWFLAKE_ACCOUNT"),
        warehouse=clean("SNOWFLAKE_WAREHOUSE"),
        database=clean("SNOWFLAKE_DATABASE"),
        schema=clean("SNOWFLAKE_SCHEMA"),
        role=clean("SNOWFLAKE_ROLE"),
    )

    sql_file = Path("405 new code.sql")

    try:
        with conn.cursor() as cur:
            # Read the file and split by semicolon to run multiple commands
            sql_content = sql_file.read_text()
            statements = [s.strip() for s in sql_content.split(";") if s.strip()]
            
            for stmt in statements:
                print(f"Executing: {stmt[:50]}...")
                cur.execute(stmt)
                
        print("######## Snowflake Process Complete.")
        
    except Exception as e:
        print(f"Error occurred: {e}")
        raise
    finally:
        conn.close()

if __name__ == "__main__":
    main()