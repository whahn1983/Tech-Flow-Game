# Pin to a specific Node.js patch release on Alpine for reproducible builds.
# To pin even further, replace with `node:24.1.0-alpine3.20@sha256:<digest>`
# (look up the current digest with `docker buildx imagetools inspect node:24.1.0-alpine3.20`).
FROM node:24.1.0-alpine3.20

WORKDIR /app

RUN addgroup -S app && adduser -S app -G app

COPY --chown=app:app . .

RUN mkdir -p /app/data \
    && ln -sf /app/data/leaderboard.txt /app/leaderboard.txt \
    && chown -R app:app /app/data \
    && chmod -R go-w /app

USER app

ENV NODE_ENV=production \
    PORT=5001
EXPOSE 5001

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://127.0.0.1:'+(process.env.PORT||5001)+'/api/leaderboard',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "server.js"]
