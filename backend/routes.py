from flask import request, jsonify
from app import app, db
from models import User, UserPreference
from ai_services import generate_code, explain_error, answer_question

@app.route('/')
def home():
    return jsonify({"message": "Welcome to Xcode GPT Pilot API"}), 200

@app.route('/api/generate_code', methods=['POST'])
def api_generate_code():
    data = request.json
    context = data.get('context', '')
    prompt = data.get('prompt', '')
    generated_code = generate_code(context, prompt)
    return jsonify({'generated_code': generated_code})

@app.route('/api/debug_assist', methods=['POST'])
def api_debug_assist():
    data = request.json
    error_message = data.get('error_message', '')
    code_snippet = data.get('code_snippet', '')
    explanation = explain_error(error_message, code_snippet)
    return jsonify({'explanation': explanation})

@app.route('/api/qa', methods=['POST'])
def api_qa():
    data = request.json
    question = data.get('question', '')
    context = data.get('context', '')
    answer = answer_question(question, context)
    return jsonify({'answer': answer})

@app.route('/api/user_preferences', methods=['GET', 'POST'])
def user_preferences():
    if request.method == 'GET':
        user_id = request.args.get('user_id')
        preferences = UserPreference.query.filter_by(user_id=user_id).all()
        return jsonify([{'key': pref.preference_key, 'value': pref.preference_value} for pref in preferences])
    elif request.method == 'POST':
        data = request.json
        user_id = data.get('user_id')
        preference_key = data.get('key')
        preference_value = data.get('value')
        
        preference = UserPreference.query.filter_by(user_id=user_id, preference_key=preference_key).first()
        if preference:
            preference.preference_value = preference_value
        else:
            preference = UserPreference(user_id=user_id, preference_key=preference_key, preference_value=preference_value)
            db.session.add(preference)
        
        db.session.commit()
        return jsonify({'message': 'Preference saved successfully'})
