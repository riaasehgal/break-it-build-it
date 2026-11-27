# Stock OWASP Juice Shop + the Break It / Build It theme (juice-theme/apply.js).
# The official image is distroless (no shell), so the theme is applied in a throwaway Node stage
# and only the patched frontend is copied back. Build from the repo root:
#   docker build -f hosting/juice-image/Dockerfile -t bib-juice-shop:v20.1.1-bib .
ARG JUICE_SHOP_VERSION=v20.1.1

FROM bkimminich/juice-shop:${JUICE_SHOP_VERSION} AS stock

FROM node:24-alpine AS theme
COPY --from=stock /juice-shop/frontend/dist /juice-shop/frontend/dist
COPY juice-theme /juice-theme
RUN JUICE_ROOT=/juice-shop node /juice-theme/apply.js

FROM bkimminich/juice-shop:${JUICE_SHOP_VERSION}
COPY --from=theme --chown=65532:0 /juice-shop/frontend/dist /juice-shop/frontend/dist
