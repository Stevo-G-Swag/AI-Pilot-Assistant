from app import socketio, app
from routes import *
from ai_services import *

if __name__ == "__main__":
    socketio.run(app, host="0.0.0.0", port=5000)
