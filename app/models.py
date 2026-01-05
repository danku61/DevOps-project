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
