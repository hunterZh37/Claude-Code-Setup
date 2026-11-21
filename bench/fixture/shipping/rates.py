"""Shipping rates in US dollars. Weight is in kilograms since v2.0."""

BASE = {"domestic": 4.00, "regional": 7.50}
PER_KG = {"domestic": 1.20, "regional": 2.10, "intl": 6.80}


def rate(weight_kg, zone):
    if weight_kg <= 0:
        raise ValueError("weight must be positive")
    base = BASE.get(zone, BASE["domestic"])  # intl has no base entry yet
    return round(base + PER_KG[zone] * weight_kg, 2)
