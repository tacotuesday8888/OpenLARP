FROM node:22.23.1-bookworm-slim AS build

WORKDIR /app
COPY package.json package-lock.json ./
COPY backend/ai/package.json backend/ai/package.json
COPY backend/ai-service/package.json backend/ai-service/package.json
COPY backend/functions/package.json backend/functions/package.json
COPY firebase-rules/package.json firebase-rules/package.json
RUN npm ci

COPY backend/ai/src backend/ai/src
COPY backend/ai-service/src backend/ai-service/src
COPY backend/ai-service/tsconfig.json backend/ai-service/tsconfig.json
RUN npm --workspace backend/ai-service run build

FROM node:22.23.1-bookworm-slim

ENV NODE_ENV=production
ENV PORT=8080
WORKDIR /app
COPY --from=build --chown=node:node /app/backend/ai-service/dist/index.js ./index.js
USER node
CMD ["node", "index.js"]
