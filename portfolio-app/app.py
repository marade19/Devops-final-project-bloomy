# pyright: reportMissingImports=false
from flask import Flask, render_template  # type: ignore[import-not-found]

app = Flask(__name__)

@app.route('/')
def home():
    return render_template('index.html')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)