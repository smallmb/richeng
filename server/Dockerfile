FROM python:3.13-slim

WORKDIR /app
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt
COPY server.py /app/server.py

# 数据库通过具名卷挂载，容器更新不会删除用户数据。
ENV RICHENG_HOST=0.0.0.0
ENV RICHENG_PORT=5318
ENV RICHENG_WS_PORT=5319
EXPOSE 5318 5319

CMD ["python", "/app/server.py"]
