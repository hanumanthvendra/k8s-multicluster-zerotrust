FROM python:3.12-alpine
WORKDIR /app
COPY server.py .
RUN adduser -D -H app && chown app /app
USER app
EXPOSE 8080
ENV PORT=8080
CMD ["python", "-u", "server.py"]
