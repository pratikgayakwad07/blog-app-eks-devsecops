FROM node:22-bookworm-slim AS build

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev --no-audit --no-fund

COPY server.js ./

FROM gcr.io/distroless/nodejs22-debian13:nonroot

WORKDIR /app
ENV NODE_ENV=production
EXPOSE 5000
USER 65532:65532

COPY --from=build --chown=nonroot:nonroot /app/node_modules ./node_modules
COPY --from=build --chown=nonroot:nonroot /app/server.js ./server.js

COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["server.js"]
