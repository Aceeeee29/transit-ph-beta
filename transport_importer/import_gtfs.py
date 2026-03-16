import pandas as pd
import psycopg2

# Replace with your Supabase connection string
DB_CONN = "postgresql://postgres.rruijvorkljjpfkbamls:%23yh%23.md_3JS4k9i@aws-1-ap-northeast-1.pooler.supabase.com:5432/postgres"
try:
    conn = psycopg2.connect(DB_CONN)
    cursor = conn.cursor()
    print("Connected to Supabase")

    # Load stops file
    stops = pd.read_csv("transport_data/stops.txt")

    inserted = 0

    for _, row in stops.iterrows():

        cursor.execute(
            """
            INSERT INTO stops (id, name, lat, lon)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (id) DO NOTHING
            """,
            (
                str(row["stop_id"]),
                str(row["stop_name"]),
                float(row["stop_lat"]),
                float(row["stop_lon"]),
            )
        )

        inserted += 1

        # commit every 500 rows (faster for large data)
        if inserted % 500 == 0:
            conn.commit()
            print(f"{inserted} stops imported...")

    conn.commit()

    print(f"Finished importing {inserted} stops!")

except Exception as e:
    print("Error:", e)

finally:
    if conn:
        cursor.close()
        conn.close()
        print("Connection closed")
