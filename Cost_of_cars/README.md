# 🚗 Определение стоимости автомобилей

## 📌 Описание проекта

Сервис по продаже автомобилей с пробегом «Не бит, не крашен» разрабатывает приложение для быстрой оценки рыночной стоимости автомобиля. На основе исторических данных о технических характеристиках, комплектациях и ценах необходимо построить модель, которая будет предсказывать стоимость автомобиля.

**Данные:** 1 таблица `autos.csv` с 15 признаками:
- `DateCrawled` — дата скачивания анкеты
- `VehicleType` — тип кузова
- `RegistrationYear` — год регистрации
- `Gearbox` — тип КПП
- `Power` — мощность (л. с.)
- `Model` — модель
- `Kilometer` — пробег (км)
- `RegistrationMonth` — месяц регистрации
- `FuelType` — тип топлива
- `Brand` — марка
- `Repaired` — была ли машина в ремонте
- `DateCreated` — дата создания анкеты
- `NumberOfPictures` — количество фото
- `PostalCode` — почтовый индекс
- `LastSeen` — дата последней активности

**Целевой признак:** `Price` — цена (евро)

---

## 🔧 Предобработка данных

- Обработка пропусков в категориальных признаках (замена на `unknown`).
- Удаление аномалий.
- Изменение типов.
- Удаление явных и неявных дубликатов.

---

## 🤖 Моделирование

**Целевая метрика:** RMSE (среднеквадратичная ошибка)

### Сравнение моделей на кросс-валидации

| Модель | RMSE | Время обучения (сек) | Время предсказания (сек) |
|--------|------|---------------------|--------------------------|
| LinearRegression | 1463.33 | 8.95 | 2.33 |
| Ridge | 1463.17 | 29.63 | 0.30 |
| DecisionTreeRegressor | 1122.84 | 38.35 | 0.03 |
| CatBoostRegressor | 989.85 | 52.53 | 12.43 |
| **LGBMRegressor** | **972.60** | 28.55 | 0.43 |

**Лучшая модель по качеству:** LGBMRegressor  
**Самая быстрая в обучении:** LinearRegression  
**Самая быстрая в предсказании:** DecisionTreeRegressor

---

## 🎯 Результат на тестовой выборке

| Модель | RMSE | Время обучения | Время предсказания |
|--------|------|----------------|---------------------|
| **LGBMRegressor** | **970.14** | 792 ms | 116 ms |

> **Примечание:** реальное время выполнения (Wall time) меньше общего времени CPU благодаря использованию нескольких ядер процессора (параллельные вычисления).

---

## 💡 Выводы и рекомендации

- **Лучшая модель по совокупности факторов (качество + скорость):** `LGBMRegressor`.
- Для практического использования в приложении можно рассмотреть компромисс между скоростью и точностью, но текущая LGBM-модель показывает оптимальный баланс.

---

### 🛠 Используемые библиотеки

```python
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import time
from sklearn.model_selection import train_test_split, GridSearchCV, cross_val_score
from sklearn.preprocessing import StandardScaler, OrdinalEncoder
from sklearn.linear_model import LinearRegression, Ridge
from sklearn.tree import DecisionTreeRegressor
from sklearn.ensemble import ExtraTreesRegressor
from catboost import CatBoostRegressor
from lightgbm import LGBMRegressor
from sklearn.pipeline import Pipeline
from sklearn.metrics import mean_squared_error
