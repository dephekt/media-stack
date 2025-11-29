# Build stage
FROM hugomods/hugo:0.152.1 AS builder
ARG DOMAIN
ENV DOMAIN=${DOMAIN}
WORKDIR /src
COPY tech-blog/ .
# Strip /static prefix from markdown files for Hugo build
RUN find content -type f -name "*.md" -exec sed -i 's|/static/images/|/images/|g' {} +
RUN hugo --minify --baseURL "https://www.${DOMAIN}/"

# Production stage
FROM nginx:1.27-alpine
COPY --from=builder /src/public /usr/share/nginx/html
EXPOSE 80
