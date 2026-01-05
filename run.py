from app import create_app

app = create_app()

if __name__ == "__main__":
    # 0.0.0.0 — доступно и с хоста (если сеть ВМ позволяет)
    app.run(host="0.0.0.0", port=8000, debug=True)
