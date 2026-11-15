import numpy as np
from src.agro import eto_pm, trapecio, gdd_diario


def test_eto_rango():
    e = eto_pm(np.array([15.0]), np.array([20.0]), np.array([10.0]), np.array([80.0]), np.array([2.0]),
               np.array([16.0]), 2.4, 2200, np.array([100]))
    assert 2.0 < e[0] < 4.5


def test_trapecio_gdd():
    assert trapecio(np.array([16.0]), 6, 16, 26, 34)[0] == 1
    assert trapecio(np.array([40.0]), 6, 16, 26, 34)[0] == 0
    assert gdd_diario(np.array([20.0]), 10)[0] == 10
