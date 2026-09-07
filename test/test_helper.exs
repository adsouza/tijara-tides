ExUnit.start(exclude: if(System.get_env("TIJARA_TEST_DB_PORT"), do: [], else: [:game_database]))
