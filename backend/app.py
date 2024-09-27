import os
from flask import Flask, request
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.orm import DeclarativeBase
from flask_socketio import SocketIO, emit

class Base(DeclarativeBase):
    pass

db = SQLAlchemy(model_class=Base)
app = Flask(__name__)
socketio = SocketIO(app, cors_allowed_origins="*")

app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL")
db.init_app(app)

with app.app_context():
    db.create_all()

connected_users = set()

@socketio.on('connect')
def handle_connect():
    print('Client connected')
    connected_users.add(request.sid)
    emit('user_list', list(connected_users), broadcast=True)

@socketio.on('disconnect')
def handle_disconnect():
    print('Client disconnected')
    connected_users.remove(request.sid)
    emit('user_list', list(connected_users), broadcast=True)

@socketio.on('code_update')
def handle_code_update(data):
    emit('code_update', data, broadcast=True, include_self=False)

@socketio.on('chat_message')
def handle_chat_message(data):
    emit('chat_message', data, broadcast=True)

from routes import *

if __name__ == '__main__':
    socketio.run(app, host='0.0.0.0', port=5000)
