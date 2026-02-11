from flask import render_template, request, make_response, session
from . import app
from .models import db, Trial
import json
import os

@app.route('/get_stim', methods=['POST'])
def get_stim():
    subj_id = request.get_json(force=True)
    
    all_stimuli = ['plus', 'hourglass_1', 'zigzag_2', 'radial_1', 'spiral_outward', 'square_spiral', 'stairs_2', 'hexagon', 'zigzag_1', 'sine', 'zigzag_widening','alternating_diff_1', 'alternating_diff_2', 'f_curly_2', 'stairs', '3_pts', 'increasing_lines', 'square_2', 'triangle_1', 'zigzag_3', 'line', 'radial_increasing', '123', 'decreasing_y']
    path = "app/static/subj_stimuli/" + subj_id + ".json"
    if os.path.exists(path):
        with open(path) as f:
            d = json.load(f)
    else:
        d = {'stimuli_completed':[], 'last_session':0}
        with open(path, 'w') as f:
            json.dump(d, f)

    stimuli_completed = d['stimuli_completed']
    last_session = d['last_session']
    remaining_stimuli = [s for s in all_stimuli if s not in stimuli_completed]
    session = last_session + 1
        
    return [remaining_stimuli, session]


@app.route('/', methods=['GET', 'POST'])
def experiment():
    if request.method == 'GET':
        return render_template('experiment.html')
    if request.method == 'POST':
        dd = request.get_json(force=True)['data']
        print('recording trial data')
        with open("app/static/subj_stimuli/" + dd['subject_id'] + ".json") as f:
            subj_data = json.load(f)
        subj_data['stimuli_completed'].append(dd['func'])
        subj_data['last_session'] = dd['session']
        with open("app/static/subj_stimuli/" + dd['subject_id'] + ".json", 'w') as f:
            json.dump(subj_data, f)

        ret = Trial( row_id = str(dd['row_id']),
                        subject_id = str(dd['subject_id']),
                        passed_ic = str(dd['passed_ic']),
                        true_x = str(dd['true_x']),
                        true_y = str(dd['true_y']),
                        response_x = str(dd['response_x']),
                        response_y = str(dd['response_y']),
                        rts = str(dd['rts']),
                        scales = str(dd['scales']),
                        success = str(dd['success']),
                        func = str(dd['func']),
                        func_idx = str(dd['func_idx']),
                        expt_start_time = str(dd['expt_start_time']),
                        trial_start_time = str(dd['trial_start_time']),
                        trial_end_time = str(dd['trial_end_time']),
                        session = str(dd['session']))

        db.session.add(ret)
        db.session.commit()
        return make_response("", 200)