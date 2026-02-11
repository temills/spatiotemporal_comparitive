from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

class Trial(db.Model):
    __tablename__ = 'trials'
    row_id = db.Column(db.String, primary_key=True)
    subject_id = db.Column(db.String)
    passed_ic = db.Column(db.String)
    true_x = db.Column(db.String)
    true_y = db.Column(db.String)
    response_x = db.Column(db.String)
    response_y = db.Column(db.String)
    rts = db.Column(db.String)
    success = db.Column(db.String)
    scales = db.Column(db.String)
    func = db.Column(db.String)
    func_idx = db.Column(db.String)
    session = db.Column(db.String)
    expt_start_time = db.Column(db.String)
    trial_start_time = db.Column(db.String)
    trial_end_time = db.Column(db.String)

    
    def __repr__(self):
        return '<Subject %r>' % self.id