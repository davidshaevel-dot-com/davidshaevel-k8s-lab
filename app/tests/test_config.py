import pytest

from labapp.config import ConfigError, load_config

BASE = {
    "DB_HOST": "postgres",
    "DB_NAME": "labapp",
    "DB_USER": "labapp",
    "DB_PASSWORD": "secret",
}


def test_required_values_and_defaults():
    cfg = load_config(BASE)
    assert cfg.db_host == "postgres"
    assert cfg.db_name == "labapp"
    assert cfg.db_user == "labapp"
    assert cfg.db_password == "secret"
    assert cfg.db_port == 5432
    assert cfg.db_connect_timeout == 3
    assert cfg.db_sslmode == "prefer"


def test_overrides_are_parsed():
    cfg = load_config({**BASE, "DB_PORT": "6432", "DB_CONNECT_TIMEOUT": "10", "DB_SSLMODE": "require"})
    assert cfg.db_port == 6432
    assert cfg.db_connect_timeout == 10
    assert cfg.db_sslmode == "require"


@pytest.mark.parametrize("missing", sorted(BASE))
def test_missing_required_value_names_the_variable(missing):
    env = {k: v for k, v in BASE.items() if k != missing}
    with pytest.raises(ConfigError, match=missing):
        load_config(env)


@pytest.mark.parametrize("name", ["DB_PORT", "DB_CONNECT_TIMEOUT"])
def test_non_integer_value_names_the_variable_and_value(name):
    with pytest.raises(ConfigError, match=f"{name}='5s'"):
        load_config({**BASE, name: "5s"})


def test_conninfo_carries_every_setting():
    cfg = load_config({**BASE, "DB_SSLMODE": "require"})
    info = cfg.conninfo()
    for part in ("host=postgres", "port=5432", "dbname=labapp", "user=labapp",
                 "password=secret", "connect_timeout=3", "sslmode=require"):
        assert part in info
