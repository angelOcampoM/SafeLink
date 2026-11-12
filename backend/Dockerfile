# syntax=docker/dockerfile:1
FROM node:24-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
# Sin scripts: el cliente de Prisma lo genera `npm run build` (prisma generate + tsc).
RUN npm ci --ignore-scripts
COPY prisma ./prisma
COPY prisma.config.ts ./
COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN npm run build

FROM node:24-alpine AS prod-deps
WORKDIR /app
COPY package.json package-lock.json ./
# argon2 trae binarios precompilados (incluido linux-musl): no necesita sus scripts de instalación.
RUN npm ci --omit=dev --ignore-scripts

# Tarea de una sola vez: aplica las migraciones (docker compose run migrate).
FROM build AS migrate
ENV NODE_ENV=production
USER node
CMD ["node_modules/.bin/prisma", "migrate", "deploy"]

FROM node:24-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./
USER node
EXPOSE 3000
CMD ["node", "dist/server.js"]
