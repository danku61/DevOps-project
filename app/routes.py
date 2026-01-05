from datetime import datetime
from flask import Blueprint, flash, redirect, render_template, request, url_for
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError

from . import db
from .models import Exercise, WorkoutSet

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
        return redirect(url_for("main.index"))

    ex = Exercise(name=name)
    db.session.add(ex)
    try:
        db.session.commit()
        flash("Упражнение добавлено.", "ok")
    except IntegrityError:
        db.session.rollback()
        flash("Такое упражнение уже существует.", "error")

    return redirect(url_for("main.index"))

@bp.get("/exercise/<int:exercise_id>")
def exercise_page(exercise_id: int):
    ex = Exercise.query.get_or_404(exercise_id)

    pr = (
        db.session.query(func.max(WorkoutSet.weight))
        .filter(WorkoutSet.exercise_id == exercise_id)
        .scalar()
    )

    sets = (
        WorkoutSet.query
        .filter_by(exercise_id=exercise_id)
        .order_by(WorkoutSet.performed_at.desc())
        .all()
    )
    return render_template("exercise.html", exercise=ex, sets=sets, pr=pr)

@bp.post("/exercise/<int:exercise_id>/sets")
def add_set(exercise_id: int):
    Exercise.query.get_or_404(exercise_id)

    try:
        weight = float((request.form.get("weight") or "").strip())
        reps = int((request.form.get("reps") or "").strip())
    except ValueError:
        flash("Вес и повторы должны быть числами.", "error")
        return redirect(url_for("main.exercise_page", exercise_id=exercise_id))

    if weight <= 0 or reps <= 0:
        flash("Вес и повторы должны быть больше нуля.", "error")
        return redirect(url_for("main.exercise_page", exercise_id=exercise_id))

    performed_at_raw = (request.form.get("performed_at") or "").strip()
    performed_at = None
    if performed_at_raw:
        try:
            performed_at = datetime.fromisoformat(performed_at_raw)
        except ValueError:
            flash("Неверный формат даты/времени.", "error")
            return redirect(url_for("main.exercise_page", exercise_id=exercise_id))

    ws = WorkoutSet(
        exercise_id=exercise_id,
        weight=weight,
        reps=reps,
        performed_at=performed_at or datetime.utcnow(),
    )
    db.session.add(ws)
    db.session.commit()

    flash("Подход добавлен.", "ok")
    return redirect(url_for("main.exercise_page", exercise_id=exercise_id))
