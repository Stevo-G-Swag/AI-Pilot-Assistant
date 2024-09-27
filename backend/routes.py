from flask import request, jsonify, render_template
from app import app, db, socketio
from models import User, UserPreference
from ai_services import generate_code, explain_error, answer_question, suggest_refactoring

@app.route('/')
def home():
    return render_template('index.html')

@app.route('/api/generate_code', methods=['POST'])
def api_generate_code():
    data = request.json
    context = data.get('context', '')
    prompt = data.get('prompt', '')
    model = data.get('model', 'openai/gpt-4o')
    generated_code = generate_code(context, prompt, model)
    return jsonify({'generated_code': generated_code})

@app.route('/api/debug_assist', methods=['POST'])
def api_debug_assist():
    data = request.json
    error_message = data.get('error_message', '')
    code_snippet = data.get('code_snippet', '')
    model = data.get('model', 'openai/gpt-4o')
    explanation = explain_error(error_message, code_snippet, model)
    return jsonify({'explanation': explanation})

@app.route('/api/qa', methods=['POST'])
def api_qa():
    data = request.json
    question = data.get('question', '')
    context = data.get('context', '')
    model = data.get('model', 'openai/gpt-4o')
    answer = answer_question(question, context, model)
    return jsonify({'answer': answer})

@app.route('/api/refactor', methods=['POST'])
def api_refactor():
    data = request.json
    code_snippet = data.get('code_snippet', '')
    model = data.get('model', 'openai/gpt-4o')
    suggestions = suggest_refactoring(code_snippet, model)
    return jsonify({'refactoring_suggestions': suggestions})

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

@app.route('/api/models', methods=['GET'])
def get_available_models():
    models = [
        {"id": "openai/gpt-4o", "name": "OpenAI GPT-4o"},
        {"id": "openai/gpt-4o-mini", "name": "OpenAI GPT-4o Mini"},
        {"id": "openrouter/anthropic/claude-2", "name": "Anthropic Claude 2"},
        {"id": "huggingface/microsoft/phi-2", "name": "Microsoft Phi-2"},
        {"id": "github/copilot-chat", "name": "GitHub Copilot"}
    ]
    return jsonify(models)

@app.route('/api/code_update', methods=['POST'])
def api_code_update():
    data = request.json
    code = data.get('code', '')
    file_path = data.get('file_path', '')
    socketio.emit('code_update', {'code': code, 'file_path': file_path}, broadcast=True)
    return jsonify({'success': True})

@socketio.on('message')
def handle_message(message):
    print('Received message:', message)
    socketio.emit('message', message)