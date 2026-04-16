# Build static Redoc docs from the OpenAPI spec and serve them from
# nginx. The image has no runtime dependencies on node or the source
# tree — it ships a single pre-rendered HTML plus the bundled spec.

FROM node:20-alpine AS builder
WORKDIR /build
COPY openapi ./openapi
COPY redocly.yaml ./
RUN npx --yes @redocly/cli@1.25.15 bundle openapi/openapi.yaml -o /build/dist/openapi.bundled.yaml \
 && npx --yes @redocly/cli@1.25.15 build-docs openapi/openapi.yaml -o /build/dist/index.html

FROM nginx:1.27-alpine
COPY --from=builder /build/dist/index.html /usr/share/nginx/html/index.html
COPY --from=builder /build/dist/openapi.bundled.yaml /usr/share/nginx/html/openapi.yaml
EXPOSE 80
