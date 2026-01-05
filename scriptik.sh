#!/usr/bin/env bash
set -euo pipefail

# Создаёт минимальный GymLog (Flask + SQLite) прямо в текущей директории (корень репозитория).

mkdir -p app/templates app/static

cat > requirements.txt <<'EOF'
Flask==3.0.3
Flask-SQLAlchemy==3.1.1
EOF

cat > app/__init__.py <<'EOF'
import os
from flask import Flask
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

def create_app() -> Flask:
    app = Flask(__name__)
    app.config["SECRET_KEY"] = os.getenv("SECRET_KEY", "dev")
    # По умолчанию — SQLite файл в корне проекта
    app.config["SQLALCHEMY_DATABASE_URI"] = os.getenv("DATABASE_URL", "sqlite:///gymlog.db")
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    db.init_app(app)

    from .routes import bp
    app.register_blueprint(bp)

    with app.app_context():
        from .models import Exercise, WorkoutSet  # noqa: F401
        db.create_all()

    return app
EOF

cat > app/models.py <<'EOF'
from datetime import datetime
from . import db

class Exercise(db.Model):
    __tablename__ = "exercises"
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), nullable=False, unique=True)

    sets = db.relationship(
        "WorkoutSet",
        back_populates="exercise",
        cascade="all, delete-orphan",
        order_by="WorkoutSet.performed_at.desc()",
    )

class WorkoutSet(db.Model):
    __tablename__ = "sets"
    id = db.Column(db.Integer, primary_key=True)

    exercise_id = db.Column(db.Integer, db.ForeignKey("exercises.id"), nullable=False)
    weight = db.Column(db.Float, nullable=False)
    reps = db.Column(db.Integer, nullable=False)
    performed_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    exercise = db.relationship("Exercise", back_populates="sets")
EOF

cat > app/routes.py <<'EOF'
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
EOF

cat > app/templates/base.html <<'EOF'
<!doctype html>
<html lang="ru">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <title>{{ title or "GymLog" }}</title>
    <link rel="stylesheet" href="{{ url_for('static', filename='style.css') }}" />
  </head>
  <body>
    <header class="header">
      <a class="brand" href="{{ url_for('main.index') }}">GymLog</a>
      <div class="sub">локальный запуск (Flask + SQLite)</div>
    </header>

    <main class="container">
      {% with messages = get_flashed_messages(with_categories=true) %}
        {% if messages %}
          <div class="flash-wrap">
            {% for category, msg in messages %}
              <div class="flash {{ category }}">{{ msg }}</div>
            {% endfor %}
          </div>
        {% endif %}
      {% endwith %}

      {% block content %}{% endblock %}
    </main>
  </body>
</html>
EOF

cat > app/templates/index.html <<'EOF'
{% extends "base.html" %}
{% block content %}
  <h1>Упражнения</h1>

  <section class="card">
    <h2>Добавить упражнение</h2>
    <form method="post" action="{{ url_for('main.create_exercise') }}" class="row">
      <input name="name" placeholder="Например: Жим лёжа" required />
      <button type="submit">Добавить</button>
    </form>
  </section>

  <section class="card">
    <h2>Список</h2>
    {% if exercises %}
      <ul class="list">
        {% for ex in exercises %}
          <li class="list-item">
            <a href="{{ url_for('main.exercise_page', exercise_id=ex.id) }}">{{ ex.name }}</a>
          </li>
        {% endfor %}
      </ul>
    {% else %}
      <p class="muted">Пока пусто. Добавь первое упражнение.</p>
    {% endif %}
  </section>
{% endblock %}
EOF

cat > app/templates/exercise.html <<'EOF'
{% extends "base.html" %}
{% block content %}
  <h1>{{ exercise.name }}</h1>

  <p class="muted">
    Личный рекорд (макс. вес): <b>{{ "%.1f"|format(pr) if pr else "—" }}</b>
  </p>

  <section class="card">
    <h2>Добавить подход</h2>
    <form method="post" action="{{ url_for('main.add_set', exercise_id=exercise.id) }}" class="grid">
      <label>
        Вес (кг)
        <input name="weight" type="number" step="0.5" min="0.5" required />
      </label>

      <label>
        Повторы
        <input name="reps" type="number" step="1" min="1" required />
      </label>

      <label>
        Дата/время (необязательно)
        <input name="performed_at" type="datetime-local" />
      </label>

      <button type="submit">Добавить</button>
    </form>
  </section>

  <section class="card">
    <h2>История</h2>
    {% if sets %}
      <ul class="list">
        {% for s in sets %}
          <li class="list-item">
            {{ s.performed_at.strftime("%Y-%m-%d %H:%M") }} — {{ "%.1f"|format(s.weight) }} кг × {{ s.reps }}
          </li>
        {% endfor %}
      </ul>
    {% else %}
      <p class="muted">Подходов пока нет.</p>
    {% endif %}
  </section>

  <p><a href="{{ url_for('main.index') }}">← назад</a></p>
{% endblock %}
EOF

cat > app/static/style.css <<'EOF'
:root { font-family: system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif; }
body { margin: 0; background: #0b0f14; color: #e8eef6; }
a { color: #7dc4ff; text-decoration: none; }
a:hover { text-decoration: underline; }
.header { padding: 18px 20px; border-bottom: 1px solid #1d2733; background: #0f1620; }
.brand { font-size: 20px; font-weight: 700; }
.sub { color: #a9b6c5; font-size: 13px; margin-top: 4px; }
.container { max-width: 900px; margin: 0 auto; padding: 20px; }
.card { background: #0f1620; border: 1px solid #1d2733; border-radius: 12px; padding: 16px; margin: 14px 0; }
.muted { color: #a9b6c5; }
.row { display: flex; gap: 10px; align-items: center; }
.grid { display: grid; gap: 10px; grid-template-columns: repeat(2, minmax(0, 1fr)); }
.grid button { grid-column: 1 / -1; }
input { width: 100%; padding: 10px 12px; border-radius: 10px; border: 1px solid #223044; background: #0b0f14; color: #e8eef6; }
button { padding: 10px 14px; border: 0; border-radius: 10px; background: #2a7bff; color: white; cursor: pointer; }
.list { list-style: none; padding: 0; margin: 0; }
.list-item { padding: 10px 0; border-bottom: 1px solid #1d2733; }
.flash-wrap { display: grid; gap: 8px; margin: 10px 0 16px; }
.flash { padding: 10px 12px; border-radius: 10px; border: 1px solid #223044; background: #0f1620; }
.flash.ok { border-color: #1e6b3a; }
.flash.error { border-color: #7a1f1f; }
EOF

cat > run.py <<'EOF'
from app import create_app

app = create_app()

if __name__ == "__main__":
    # 0.0.0.0 — доступно и с хоста (если сеть ВМ позволяет)
    app.run(host="0.0.0.0", port=8000, debug=True)
EOF

echo "OK: files created. Next: install python + venv + run."
