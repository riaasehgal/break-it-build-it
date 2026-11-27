# Hosted Build-It (Ria's buildit/ site) in sandbox mode: every visitor gets a private in-memory practice
# copy, Save/Reset never touch disk, no Juice Shop attached. Build from the repo root:
#   docker build -f hosting/buildit-image/Dockerfile -t bib-buildit:v1 .
FROM node:24-alpine
WORKDIR /app
COPY buildit/ /app/buildit/
ENV BUILDIT_MODE=sandbox PORT=3100 NODE_ENV=production
USER node
EXPOSE 3100
CMD ["node", "/app/buildit/server.js"]
