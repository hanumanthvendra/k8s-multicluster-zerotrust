# Base image is mirrored to the kind registry so Kaniko does not hit Docker Hub rate limits.
FROM 172.18.0.20:5000/python:3.12-alpine
WORKDIR /app
COPY server.py .
RUN adduser -D -H app && chown app /app
USER app
EXPOSE 8080
ENV PORT=8080
CMD ["python", "-u", "server.py"]
