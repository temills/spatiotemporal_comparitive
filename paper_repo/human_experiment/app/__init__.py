from flask import Flask
import os
import json
from flask_cors import CORS
from .models import db

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] =  "sqlite:///local.db" 

CORS(app)
from . import views
if __name__ == '__main__':
    app.run()