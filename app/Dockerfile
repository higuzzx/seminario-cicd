# Imagem da app. A versão e o commit entram como build args
# e ficam gravados na imagem (variáveis de ambiente + labels OCI).
FROM node:24-alpine

ARG APP_VERSION=0.0.0-dev
ARG APP_COMMIT=local

ENV NODE_ENV=production \
    PORT=3000 \
    APP_VERSION=${APP_VERSION} \
    APP_COMMIT=${APP_COMMIT}

LABEL org.opencontainers.image.title="seminario-cicd-app" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${APP_COMMIT}"

WORKDIR /app
COPY package.json server.js ./

# Não roda como root
USER node

EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/health || exit 1

CMD ["node", "server.js"]
