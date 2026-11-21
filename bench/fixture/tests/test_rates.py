import pytest

from shipping.rates import rate


def test_domestic():
    assert rate(2, "domestic") == 6.40


def test_regional():
    assert rate(1, "regional") == 9.60


def test_intl_has_its_own_base():
    # International parcels start at 18.00 before weight.
    assert rate(1, "intl") == 24.80


def test_rejects_zero_weight():
    with pytest.raises(ValueError):
        rate(0, "domestic")
