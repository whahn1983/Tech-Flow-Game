# Pin to a specific Node.js patch release on Alpine for reproducible builds.
# To pin even further, replace with `node:24.1.0-alpine3.20@sha256:<digest>`
# (look up the current digest with `docker buildx imagetools inspect node:24.1.0-alpine3.20`).
FROM node:24.1.0-alpine3.20

WORKDIR /app

# Pin the UID/GID so a persisted /app/data volume keeps matching ownership
# across rebuilds. With `adduser -S` (no explicit UID) Alpine auto-assigns,
# and the value can drift when the base image's existing system users change —
# leaving the volume owned by a UID the rebuilt container no longer maps to,
# which surfaces as EACCES on leaderboard writes.
RUN addgroup -S -g 1001 app && adduser -S -u 1001 -G app app

COPY --chown=app:app . .

RUN mkdir -p /app/data \
    && chown -R app:app /app/data \
    && chmod 0755 /app/data \
    && chmod -R go-w /app

USER app

ENV NODE_ENV=production \
    PORT=5001
EXPOSE 5001

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://127.0.0.1:'+(process.env.PORT||5001)+'/api/leaderboard',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "server.js"]
