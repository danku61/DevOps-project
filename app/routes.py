# app/routes.py

import math
from datetime import datetime

from flask import Blueprint, flash, redirect, render_template, request, url_for
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError

from . import db
from .models import Exercise, WorkoutSet
from .logger import log_event  # предполагается app/logger.py

bp = Blueprint("main", __name__)


@bp.get("/")
def index():
    exercises = Exercise.query.order_by(Exercise.name.asc()).all()
    return render_template("index.html", exercises=exercises)


@bp.post("/exercises")
def create_exercise():
    name = (request.form.get("name") or "").strip()

    if not name:
        flash("Название упражнения не может быть пустым.", "error")
        log_event("ПУСТОЕ имя упражнения")
        return redirect(url_for("main.index"))

    try:
        ex = Exercise(name=name)
        db.session.add(ex)
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        flash("Такое упражнение уже существует.", "error")
        log_event(f"упражнение уже существует")
        return redirect(url_for("main.index"))
    except Exception as e:
        db.session.rollback()
        flash("Ошибка сервера при добавлении упражнения.", "error")
        log_event(f"CREATE_EXERCISE db_error name={name!r} err={type(e).__name__}")
        return redirect(url_for("main.index"))

    flash("Упражнение добавлено.", "success")
    log_event(f"Упражнение добавлено")
    return redirect(url_for("main.index"))


@bp.get("/exercise/<int:exercise_id>")
def exercise_page(exercise_id: int):
    exercise = Exercise.query.get_or_404(exercise_id)

    sets = (
        WorkoutSet.query.filter_by(exercise_id=exercise_id)
        .order_by(WorkoutSet.performed_at.desc())
        .all()
    )

    pr = (
        db.session.query(func.max(WorkoutSet.weight))
        .filter(WorkoutSet.exercise_id == exercise_id)
        .scalar()
    )

    return render_template("exercise.html", exercise=exercise, sets=sets, pr=pr)


@bp.post("/exercise/<int:exercise_id>/sets")
def add_set(exercise_id: int):
    # Проверяем, что упражнение существует
    Exercise.query.get_or_404(exercise_id)

    # Сырые значения из формы — полезны для логов
    raw_w = (request.form.get("weight") or "").strip()
    raw_r = (request.form.get("reps") or "").strip()
    raw_dt = (request.form.get("performed_at") or "").strip()  # если поля нет — будет ""

    # (не обязательно, но удобно для отладки)
    # log_event(f"ADD_SET handler reached ex_id={exercise_id} weight={raw_w!r} reps={raw_r!r} performed_at={raw_dt!r}")

    # Парсинг чисел
    try:
        weight = float(raw_w)
        reps = int(raw_r)
    except ValueError as e:
        flash("Вес и повторы должны быть числами.", "error")
        log_event("ошибка типов данных повтора или подхода" )
        return redirect(url_for("main.exercise_page", exercise_id=exercise_id))

    # Серверная валидация (даже если HTML что-то ограничивает)
    if (not math.isfinite(weight)) or weight <= 0 or reps <= 0:
        flash("Вес и повторы должны быть больше нуля.", "error")
        log_event("Повтор или вес МЕНЬШЕ 0")
        return redirect(url_for("main.exercise_page", exercise_id=exercise_id))

    # Дата/время (опционально)
    performed_at = None
    if raw_dt:
        try:
            # для input type="datetime-local" обычно приходит 'YYYY-MM-DDTHH:MM'
            performed_at = datetime.fromisoformat(raw_dt)
        except ValueError as e:
            flash("Некорректная дата/время.", "error")
            log_event(
                f"ADD_SET invalid_datetime ex_id={exercise_id} performed_at={raw_dt!r} "
                f"err={type(e).__name__}:{e}"
            )
            return redirect(url_for("main.exercise_page", exercise_id=exercise_id))

    ws = WorkoutSet(
        exercise_id=exercise_id,
        weight=weight,
        reps=reps,
        performed_at=performed_at or datetime.now(),
    )

    # Сохранение в БД
    try:
        db.session.add(ws)
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        flash("Ошибка сервера при сохранении подхода.", "error")
        log_event(f"ADD_SET db_error ex_id={exercise_id} err={type(e).__name__}")
        return redirect(url_for("main.exercise_page", exercise_id=exercise_id))

    flash("Подход добавлен.", "success")
    log_event(
        f"ADD_SET success ex_id={exercise_id} weight={weight} reps={reps} "
        f"performed_at={(performed_at.isoformat() if performed_at else 'auto_now')}"
    )
    return redirect(url_for("main.exercise_page", exercise_id=exercise_id))
